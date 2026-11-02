"""Convierte los .parquet horarios de Meteostat a un único CSV en formato largo.

Entrada: <base>/<año>.parquet, con datos horarios (UTC) de estaciones de todo el
mundo y una columna <variable>_source por variable. Se conservan sólo las
estaciones de ESTACIONES.

Salida: estacion, fecha_hora (ISO 8601), metrica, valor, unidad, fuente,
        fuente_tipo (observacion | modelo), descrip (descripción de la fuente)
"""

import argparse
import sys
from pathlib import Path

import pandas as pd
import pyarrow.parquet as pq

# id de estación Meteostat (= NRO_OMM) -> nombre, igual que en smn_to_csv.py
ESTACIONES = {
    "87582": "AEROPARQUE AERO",
    "87585": "BUENOS AIRES OBSERVATORIO",
}

# Columna de Meteostat -> (nombre de métrica, unidad)
METRICAS = {
    "temp": ("temp", "C"),
    "rhum": ("rhum", "%"),
    "prcp": ("prcp", "mm"),
    "snwd": ("snwd", "mm"),
    "wdir": ("wdir", "grados"),
    "wspd": ("wspd", "km/h"),
    "wpgt": ("wpgt", "km/h"),
    "pres": ("pres", "hPa"),
    "tsun": ("tsun", "min"),
    "cldc": ("cldc", "octavos"),
    "coco": ("coco", "codigo"),
}

# Fuente de Meteostat -> (tipo, descripción breve)
FUENTES = {
    "metar": ("observacion", "Reporte METAR de la estación (observación aeronáutica)"),
    "isd_lite": ("observacion", "NOAA ISD-Lite: observaciones horarias de estación"),
    "dwd_mosmix": ("modelo", "Pronóstico estadístico MOSMIX del servicio meteorológico alemán (DWD)"),
    "metno_forecast": ("modelo", "Pronóstico del instituto meteorológico noruego (MET Norway)"),
}

# Buenos Aires: UTC-03:00 todo el año (Argentina no usa horario de verano).
DESFASE_BA = pd.Timedelta(hours=-3)


def procesar_archivo(ruta: Path) -> pd.DataFrame:
    """Lee las estaciones de interés de un parquet y las pasa a formato largo."""
    cols = ["station", "time"] + [c for m in METRICAS for c in (m, f"{m}_source")]
    # El filtro se aplica al leer: los archivos pesan ~1 GB y casi todo sobra.
    df = pq.read_table(ruta, columns=cols, filters=[("station", "in", list(ESTACIONES))]).to_pandas()

    partes = []
    for col, (metrica, unidad) in METRICAS.items():
        parte = df[["station", "time", col, f"{col}_source"]].dropna(subset=[col])
        parte.columns = ["estacion", "time", "valor", "fuente"]
        parte["metrica"], parte["unidad"] = metrica, unidad
        partes.append(parte)
    return pd.concat(partes, ignore_index=True)


def main():
    aqui = Path(__file__).resolve().parent
    RAIZ = aqui.parent  # raíz del repo
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--base", type=Path, default=RAIZ / "data" / "raw" / "meteostat")
    ap.add_argument("--salida", type=Path, default=RAIZ / "data" / "landing" / "meteostat.csv")
    args = ap.parse_args()

    archivos = sorted(args.base.glob("*.parquet"))
    if not archivos:
        sys.exit(f"No se encontraron .parquet en {args.base}")

    partes = []
    for ruta in archivos:
        df = procesar_archivo(ruta)
        print(f"{ruta.name}: {len(df)} lecturas")
        partes.append(df)
    out = pd.concat(partes, ignore_index=True)

    # Meteostat guarda la hora en UTC (sin zona). Los parquet de 2026 llegan
    # hasta fechas futuras con pronósticos (dwd_mosmix, metno_forecast).
    futuro = out["time"] > pd.Timestamp.now(tz="UTC").tz_localize(None)
    if futuro.any():
        print(f"AVISO: {futuro.sum()} lecturas con fecha futura descartadas", file=sys.stderr)
        out = out[~futuro]

    out["estacion"] = out["estacion"].map(ESTACIONES)
    local = out["time"] + DESFASE_BA
    out["fecha_hora"] = local.dt.strftime("%Y-%m-%dT%H:%M:%S") + "-03:00"

    n = len(out)
    out = out.drop_duplicates(["estacion", "fecha_hora", "metrica"], keep="last")
    if len(out) != n:
        print(f"AVISO: {n - len(out)} duplicados eliminados", file=sys.stderr)

    out = out.sort_values(["estacion", "fecha_hora", "metrica"])
    desconocidas = set(out["fuente"]) - set(FUENTES)
    if desconocidas:
        print(f"AVISO: fuentes sin clasificar: {sorted(desconocidas)}", file=sys.stderr)
    out["fuente_tipo"] = out["fuente"].map(lambda f: FUENTES.get(f, (None, None))[0])
    out["descrip"] = out["fuente"].map(lambda f: FUENTES.get(f, (None, None))[1])
    out = out[["estacion", "fecha_hora", "metrica", "valor", "unidad", "fuente", "fuente_tipo", "descrip"]]
    out.to_csv(args.salida, index=False)
    print(f"\n{len(out)} filas -> {args.salida}")
    print(out.groupby(["fuente_tipo", "fuente"]).size().to_string())


if __name__ == "__main__":
    main()
