"""ETL del TP: del CSV crudo de calidad del aire a las tablas finales para Power BI.

    EXTRACT    data/raw/calidad-aire.csv  -> se verifica y se perfila (filas, fechas, tipos de valor)
    TRANSFORM  dbt build: referencias -> staging -> dimensiones y fact -> calidad -> indicadores,
    + LOAD     todo dentro de data/warehouse/aire.duckdb, con los tests de calidad de dbt
    EXPORT     tablas finales -> data/final/*.csv y *.parquet
    ANALIZAR   ejecuta sql/99_consultas_analisis.sql (verifica que todas las consultas corran y
               crea las vistas del schema `analisis`)
    DOCUMENTAR docs/diccionario_datos.md a partir de las descripciones de dbt

Es idempotente: cada corrida reconstruye las tablas desde cero y sobrescribe las salidas, así
que correrlo dos veces da exactamente el mismo resultado.

Uso (desde la raíz del repo):  python -m src.etl
La descarga del CSV desde BA Data es un paso aparte y opcional: python -m src.extract
"""

import logging
import os
import subprocess
import sys
import time

import duckdb

from src import calidad, config, diccionario

log = logging.getLogger("etl")


def extraer() -> dict:
    """EXTRACT: verifica que esté el crudo y deja en el log con qué datos se arranca."""
    if not config.RAW_AIRE.exists():
        sys.exit(f"Falta {config.RAW_AIRE.relative_to(config.RAIZ)}. Bajarlo con: python -m src.extract")
    perfil = calidad.perfil_raw(config.RAW_AIRE)
    log.info(
        "Crudo %s: %s filas (fecha × hora) × %s columnas, %s a %s (%s días)",
        perfil["archivo"], f"{perfil['filas']:,}".replace(",", "."), len(perfil["columnas"]),
        perfil["fecha_min"], perfil["fecha_max"], perfil["dias"],
    )
    log.info("Columnas: %s", ", ".join(perfil["columnas"]))
    log.info(
        "Duplicados por fecha + hora: %s · horas fuera de 1-24: %s",
        perfil["duplicados_clave"], perfil["horas_fuera_de_rango"],
    )
    log.info("Celdas por tipo de valor: %s", perfil["celdas_por_tipo"])
    return perfil


def transformar_y_cargar() -> None:
    """TRANSFORM + LOAD: corre `dbt build` (seeds, modelos y tests, en orden de dependencias).

    Se corre en un proceso aparte para que dbt suelte la base DuckDB al terminar
    (DuckDB admite un solo proceso escribiendo el archivo).
    """
    config.DIR_WAREHOUSE.mkdir(parents=True, exist_ok=True)
    # dbt arma las rutas de los archivos con esta variable (macro ruta() y profiles.yml)
    entorno = {**os.environ, "AIRE_RAIZ": config.RAIZ.as_posix()}
    comando = [
        sys.executable, "-c", "from dbt.cli.main import cli; cli()",
        "build", "--project-dir", str(config.DIR_DBT), "--profiles-dir", str(config.DIR_DBT),
    ]
    resultado = subprocess.run(comando, env=entorno, cwd=config.DIR_DBT)
    if resultado.returncode != 0:
        sys.exit("dbt build falló: revisar el error de arriba (un modelo o un test de calidad).")
    log.info("dbt build OK (modelos y tests de calidad)")


def exportar() -> None:
    """EXPORT: tablas finales a CSV (UTF-8, separador ',', decimal '.') y Parquet."""
    config.DIR_FINAL.mkdir(parents=True, exist_ok=True)
    con = duckdb.connect(config.BASE_DUCKDB.as_posix(), read_only=True)
    for tabla in config.TABLAS_FINALES:
        nombre = tabla.split(".")[1]
        csv = (config.DIR_FINAL / f"{nombre}.csv").as_posix()
        parquet = (config.DIR_FINAL / f"{nombre}.parquet").as_posix()
        # ORDER BY ALL: mismo orden de filas en cada corrida (archivos idénticos = idempotente)
        consulta = f"select * from {tabla} order by all"
        con.execute(f"copy ({consulta}) to '{csv}' (header, delimiter ',')")
        con.execute(f"copy ({consulta}) to '{parquet}' (format parquet)")
        filas = con.execute(f"select count(*) from {tabla}").fetchone()[0]
        log.info("  %-28s %7s filas -> data/final/%s.{csv,parquet}", nombre, f"{filas:,}".replace(",", "."), nombre)
    con.close()


def ejecutar_consultas_analisis() -> None:
    """ANALIZAR: corre una por una las consultas de sql/99_consultas_analisis.sql."""
    texto = (config.DIR_SQL / "99_consultas_analisis.sql").read_text(encoding="utf-8")
    con = duckdb.connect(config.BASE_DUCKDB.as_posix())  # lectura y escritura: crea vistas
    sentencias = duckdb.extract_statements(texto)
    for sentencia in sentencias:
        con.execute(sentencia.query)
    con.close()
    log.info("%s sentencias de sql/99_consultas_analisis.sql ejecutadas sin errores", len(sentencias))


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s", datefmt="%H:%M:%S")
    inicio = time.time()

    log.info("1/5 EXTRACT: perfil del crudo")
    extraer()

    log.info("2/5 TRANSFORM + LOAD: dbt build")
    transformar_y_cargar()

    log.info("3/5 EXPORT: tablas finales")
    exportar()

    log.info("4/5 ANALIZAR: consultas SQL de análisis")
    ejecutar_consultas_analisis()

    log.info("5/5 DOCUMENTAR: diccionario de datos")
    diccionario.generar()

    for titulo, tabla in calidad.resumen_post_etl(config.BASE_DUCKDB).items():
        log.info("Calidad · %s:\n%s", titulo, tabla.to_string(index=False))
    log.info("ETL terminado en %.0f s. Base: %s", time.time() - inicio, config.BASE_DUCKDB.relative_to(config.RAIZ))


if __name__ == "__main__":
    main()
