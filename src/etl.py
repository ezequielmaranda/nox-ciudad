"""ETL del TP: del CSV crudo de calidad del aire a las tablas finales para Looker Studio.

    EXTRACT    verifica que esté data/raw/calidad-aire.csv (el CSV horario de BA Data)
    TRANSFORM  dbt build en arquitectura medallón: bronze (el CSV tal cual y las referencias)
    + LOAD     -> silver (valores horarios limpios y valor diario) -> gold (modelo estrella e
               indicadores), todo dentro de data/warehouse/aire.duckdb, con los tests de dbt
    EXPORT     capa gold -> data/final/*.csv, y de ahí las tablas planas de dashboard/looker/
    ANALIZAR   ejecuta sql/99_consultas_analisis.sql (verifica que todas las consultas corran)
    DOCUMENTAR docs/diccionario_datos.md a partir de las descripciones de dbt

Es idempotente: cada corrida reconstruye las tablas desde cero y sobrescribe las salidas, así
que correrlo dos veces da exactamente el mismo resultado.

Uso (desde la raíz del repo):  python -m src.etl
La descarga del CSV desde BA Data es un paso aparte y opcional: python -m src.extract
"""

import logging
import subprocess
import sys
import time

import duckdb

from src import config, diccionario, generar_looker

log = logging.getLogger("etl")


def verificar_crudo() -> None:
    """EXTRACT: el crudo ya está en el repo; acá solo se verifica que no falte."""
    if not config.RAW_AIRE.exists():
        sys.exit(f"Falta {config.RAW_AIRE.relative_to(config.RAIZ)}. Bajarlo con: python -m src.extract")


def transformar_y_cargar() -> None:
    """TRANSFORM + LOAD: corre `dbt build` (seeds, modelos y tests, en orden de dependencias).

    Se corre en un proceso aparte para que dbt suelte la base DuckDB al terminar
    (DuckDB admite un solo proceso escribiendo el archivo). Corre desde la carpeta dbt/, de
    donde salen el profiles.yml y las rutas relativas a los archivos del repo.
    """
    config.DIR_WAREHOUSE.mkdir(parents=True, exist_ok=True)
    comando = [sys.executable, "-c", "from dbt.cli.main import cli; cli()", "build"]
    resultado = subprocess.run(comando, cwd=config.DIR_DBT)
    if resultado.returncode != 0:
        sys.exit("dbt build falló: revisar el error de arriba (un modelo o un test de calidad).")
    log.info("dbt build OK (modelos y tests de calidad)")


def exportar() -> None:
    """EXPORT: tablas de gold a CSV (UTF-8, separador ',', decimal '.')."""
    config.DIR_FINAL.mkdir(parents=True, exist_ok=True)
    con = duckdb.connect(config.BASE_DUCKDB.as_posix(), read_only=True)
    for tabla in config.TABLAS_FINALES:
        nombre = tabla.split(".")[1]
        csv = (config.DIR_FINAL / f"{nombre}.csv").as_posix()
        # ORDER BY ALL: mismo orden de filas en cada corrida (archivos idénticos = idempotente)
        con.execute(f"copy (select * from {tabla} order by all) to '{csv}' (header, delimiter ',')")
        filas = con.execute(f"select count(*) from {tabla}").fetchone()[0]
        log.info("  %-28s %7s filas -> data/final/%s.csv", nombre, diccionario.miles(filas), nombre)
    con.close()
    generar_looker.generar()  # tablas planas para Looker Studio, a partir de los CSV recién exportados


def ejecutar_consultas_analisis() -> None:
    """ANALIZAR: corre una por una las consultas de sql/99_consultas_analisis.sql."""
    texto = (config.DIR_SQL / "99_consultas_analisis.sql").read_text(encoding="utf-8")
    con = duckdb.connect(config.BASE_DUCKDB.as_posix(), read_only=True)  # solo consultas de lectura
    sentencias = duckdb.extract_statements(texto)
    for sentencia in sentencias:
        con.execute(sentencia.query)
    con.close()
    log.info("%s sentencias de sql/99_consultas_analisis.sql ejecutadas sin errores", len(sentencias))


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s", datefmt="%H:%M:%S")
    inicio = time.time()

    log.info("1/5 EXTRACT: verificar el crudo")
    verificar_crudo()

    log.info("2/5 TRANSFORM + LOAD: dbt build")
    transformar_y_cargar()

    log.info("3/5 EXPORT: capa gold")
    exportar()

    log.info("4/5 ANALIZAR: consultas SQL de análisis")
    ejecutar_consultas_analisis()

    log.info("5/5 DOCUMENTAR: diccionario de datos")
    diccionario.generar()

    log.info("ETL terminado en %.0f s. Base: %s", time.time() - inicio, config.BASE_DUCKDB.relative_to(config.RAIZ))


if __name__ == "__main__":
    main()
