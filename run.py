"""Corre el pipeline completo: extract -> dbt build -> export a Parquet.

Uso (desde la raíz del proyecto):
    uv run python run.py              # dbt build + export (los datos crudos ya están en data/)
    uv run python run.py --extraer    # además vuelve a correr los scripts de extract/
    uv run python run.py --solo-export

dbt no es un orquestador: solo transforma lo que ya está en data/landing y data/raw.
Este script encadena los pasos en orden y corta si alguno falla.

Paso manual previo (no se puede automatizar porque hay que aceptar términos):
    bajar los datos diarios del SMN y descomprimirlos en data/raw/smn/ (ver README, Fuentes).
"""
import argparse
import subprocess
import sys
from pathlib import Path

import duckdb

RAIZ = Path(__file__).resolve().parent
BASE = RAIZ / "data" / "nox.duckdb"
EXPORT = RAIZ / "export"

EXTRACT = [
    ["extract/aire_publico.py"],
    ["extract/sube_descarga.py"],
    ["extract/smn_to_csv.py"],
]

# Tablas que salen a Parquet para Power BI y el EDA en Colab.
TABLAS_EXPORT = [
    "gold.gold_analitico",      # estación × día: la tabla del análisis
    "gold.gold_aire_diario",
    "gold.gold_sube_diario",
    "gold.gold_meteo_diario",
    "silver.dim_calendario",
    "bronze.eventos",
]


def correr(cmd, cwd=RAIZ):
    print(f"\n>> {' '.join(cmd)}", flush=True)
    r = subprocess.run(cmd, cwd=cwd)
    if r.returncode != 0:
        sys.exit(f"Falló: {' '.join(cmd)} (código {r.returncode})")


def exportar():
    EXPORT.mkdir(exist_ok=True)
    con = duckdb.connect(str(BASE), read_only=True)
    print(f"\n>> export a {EXPORT}")
    for tabla in TABLAS_EXPORT:
        destino = EXPORT / f"{tabla.split('.')[1]}.parquet"
        con.execute(f"copy {tabla} to '{destino.as_posix()}' (format parquet)")
        filas = con.execute(f"select count(*) from {tabla}").fetchone()[0]
        print(f"   {destino.name:28s} {filas:>7,} filas")
    con.close()


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--extraer", action="store_true", help="correr también los scripts de extract/")
    ap.add_argument("--solo-export", action="store_true", help="no correr dbt; solo exportar")
    args = ap.parse_args()

    if args.extraer:
        for script in EXTRACT:
            correr([sys.executable, *script])
    if not args.solo_export:
        correr(["dbt", "build", "--profiles-dir", "."], cwd=RAIZ / "dbt")
    exportar()
    print("\nListo.")


if __name__ == "__main__":
    main()
