"""Convierte los datos diarios del SMN a un único CSV en formato largo.

Fuente: SMN, https://www.smn.gob.ar/descarga-de-datos (aceptar términos y condiciones).
Zip: https://ssl.smn.gob.ar/dpd/zipopendata.php?dato=datosdiarios20212026

Entrada: <base>/smn_datos_meteorologicos_desde_2021.lst (TSV, una fila por
estación y día, fecha DD/MM/AAAA, "S/D" = sin dato). Se conservan sólo las
estaciones de ESTACIONES.

Salida: estacion, fecha (ISO 8601), metrica, valor, unidad
"""

import argparse
import sys
from pathlib import Path

import pandas as pd

# NRO_OMM -> nombre de estación
ESTACIONES = {
    87582: "AEROPARQUE AERO",
    87585: "BUENOS AIRES OBSERVATORIO",
}

# Columna del archivo -> (nombre de métrica, unidad).
# El LEAME no documenta unidades, por eso van fijas acá (convención del SMN).
METRICAS = {
    "TMAX": ("TMAX", "C"),
    "TMIN": ("TMIN", "C"),
    "TMEDIA": ("TMEDIA", "C"),
    "PRECIP": ("PRECIP", "mm"),
    "HELIOF": ("HELIOF", "h"),
    "VTO_MDIR": ("VTO_MDIR", "decenas de grado"),
    "VTO_MVEL": ("VTO_MVEL", "km/h"),
    "VEL_MED": ("VEL_MED", "km/h"),
    "PRE_EST": ("PRE_EST", "hPa"),
    "HUM_REL": ("HUM_REL", "%"),
    "NUB_TOT": ("NUB_TOT", "octavos"),
}


def main():
    aqui = Path(__file__).resolve().parent
    RAIZ = aqui.parent  # raíz del repo
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--base", type=Path, default=RAIZ / "data" / "raw" / "smn")
    ap.add_argument("--salida", type=Path, default=RAIZ / "data" / "landing" / "smn.csv")
    args = ap.parse_args()

    ruta = args.base / "smn_datos_meteorologicos_desde_2021.lst"
    if not ruta.is_file():
        sys.exit(f"No se encontró {ruta}")

    # dtype=str: la conversión numérica se hace después, para poder avisar de
    # valores raros. Se desactiva keep_default_na para distinguir celdas vacías.
    df = pd.read_csv(ruta, sep="\t", dtype=str, keep_default_na=False)
    df.columns = df.columns.str.strip()
    # El encabezado se repite cada 50.000 líneas dentro del archivo.
    df = df[df["NRO_OMM"].str.strip() != "NRO_OMM"]
    df = df[df["NRO_OMM"].str.strip().astype(int).isin(ESTACIONES)].copy()
    print(f"{ruta.name}: {len(df)} filas de {len(ESTACIONES)} estaciones")

    df["estacion"] = df["NRO_OMM"].str.strip().astype(int).map(ESTACIONES)
    df["fecha"] = pd.to_datetime(df["FECHA"].str.strip(), format="%d/%m/%Y")

    out = df.melt(
        id_vars=["estacion", "fecha"],
        value_vars=list(METRICAS),
        var_name="metrica",
        value_name="valor",
    )
    out["unidad"] = out["metrica"].map(lambda m: METRICAS[m][1])
    out["metrica"] = out["metrica"].map(lambda m: METRICAS[m][0])

    # Valores: "S/D" (sin dato) y celdas vacías se descartan; cualquier otro
    # texto no numérico se avisa y también se descarta.
    crudo = out["valor"].str.strip()
    out["valor"] = pd.to_numeric(crudo, errors="coerce")
    raros = crudo[out["valor"].isna()]
    raros = raros[~raros.str.upper().isin(["S/D", ""])]
    if len(raros):
        print(f"AVISO: {len(raros)} valores no numéricos descartados: "
              f"{raros.value_counts().head(10).to_dict()}", file=sys.stderr)
    out = out.dropna(subset=["valor"])

    n = len(out)
    out = out.drop_duplicates(["estacion", "fecha", "metrica"], keep="last")
    if len(out) != n:
        print(f"AVISO: {n - len(out)} duplicados eliminados", file=sys.stderr)

    out["fecha"] = out["fecha"].dt.strftime("%Y-%m-%d")
    out = out.sort_values(["estacion", "fecha", "metrica"])
    out = out[["estacion", "fecha", "metrica", "valor", "unidad"]]
    out.to_csv(args.salida, index=False)
    print(f"\n{len(out)} filas -> {args.salida}")


if __name__ == "__main__":
    main()
