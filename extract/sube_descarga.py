"""Descarga los CSV anuales de SUBE (transacciones por línea y día) a data/raw/sube/.

Fuente: datos.transporte.gob.ar, dataset "SUBE - Cantidad de transacciones (usos) por fecha".
Las URLs se piden a la API del portal (CKAN); si la API no responde, se usa el patrón conocido.
Si un archivo ya existe no se vuelve a bajar, salvo con --forzar (útil para el año en curso,
que el portal va actualizando).

Uso:
    uv run python extract/sube_descarga.py                       # 2024, 2025 y 2026
    uv run python extract/sube_descarga.py --anios 2025 2026 --forzar
"""

import argparse
import re
import sys
from pathlib import Path

import requests

RAIZ = Path(__file__).resolve().parent.parent
API = "https://datos.transporte.gob.ar/api/3/action/package_show?id=sube-cantidad-de-transacciones-usos-por-fecha"
PATRON = "https://archivos-datos.transporte.gob.ar/upload/Dat_Ab_Usos/dat-ab-usos-{anio}.csv"


def urls_por_anio() -> dict:
    """Pide al portal las URLs vigentes de cada año."""
    try:
        recursos = requests.get(API, timeout=60).json()["result"]["resources"]
    except Exception as e:  # el portal a veces no responde
        print(f"AVISO: no respondió la API del portal ({e}); uso el patrón conocido", file=sys.stderr)
        return {}
    urls = {}
    for r in recursos:
        m = re.search(r"(20\d{2})", r.get("name", "") + " " + r.get("url", ""))
        if m and r.get("url", "").lower().endswith(".csv"):
            urls[int(m.group(1))] = r["url"]
    return urls


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--anios", type=int, nargs="+", default=[2024, 2025, 2026])
    ap.add_argument("--destino", type=Path, default=RAIZ / "data" / "raw" / "sube")
    ap.add_argument("--forzar", action="store_true", help="vuelve a bajar aunque el archivo exista")
    args = ap.parse_args()
    args.destino.mkdir(parents=True, exist_ok=True)

    urls = urls_por_anio()
    for anio in args.anios:
        destino = args.destino / f"dat-ab-usos-{anio}.csv"
        if destino.exists() and not args.forzar:
            print(f"{destino.name}: ya existe, no se descarga")
            continue
        url = urls.get(anio, PATRON.format(anio=anio))
        print(f"{destino.name}: descargando {url}")
        with requests.get(url, stream=True, timeout=300) as r:
            r.raise_for_status()
            tmp = destino.with_suffix(".parcial")
            with tmp.open("wb") as fh:
                for bloque in r.iter_content(chunk_size=1 << 20):
                    fh.write(bloque)
            tmp.replace(destino)  # solo reemplaza si la descarga terminó bien
        print(f"   {destino.stat().st_size / 1e6:.1f} MB")


if __name__ == "__main__":
    main()
