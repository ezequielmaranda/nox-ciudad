"""Rutas y parámetros del proyecto, todo relativo a la raíz del repo (sin rutas absolutas)."""

from pathlib import Path

# Raíz del repo: la carpeta que contiene a src/
RAIZ = Path(__file__).resolve().parent.parent

# Datos
DIR_RAW = RAIZ / "data" / "raw"                    # crudos (no se modifican a mano)
RAW_AIRE = DIR_RAW / "calidad-aire.csv"            # CSV horario de BA Data, tal como se publica
DIR_WAREHOUSE = RAIZ / "data" / "warehouse"
BASE_DUCKDB = DIR_WAREHOUSE / "aire.duckdb"        # base analítica que arma dbt
DIR_FINAL = RAIZ / "data" / "final"                # CSV para Power BI y el EDA

# Fuente: dataset "Calidad del aire" de BA Data (Buenos Aires Data, GCBA), publicado por la APrA.
# Página: https://data.buenosaires.gob.ar/dataset/calidad-aire
URL_CALIDAD_AIRE = (
    "https://cdn.buenosaires.gob.ar/datosabiertos/datasets/"
    "agencia-de-proteccion-ambiental/calidad-aire/calidad-aire.csv"
)

# Transformaciones y salidas
DIR_DBT = RAIZ / "dbt"
DIR_SQL = RAIZ / "sql"
DIR_DOCS = RAIZ / "docs"

# Tablas que se exportan a data/final (schema.tabla de la base DuckDB).
# El orden es el que conviene seguir al importarlas en Power BI: dimensiones, hechos, agregados.
TABLAS_FINALES = [
    "modelo.dim_estacion",
    "modelo.dim_contaminante",
    "modelo.dim_calendario",
    "modelo.dim_periodo",
    "modelo.ref_oms",
    "modelo.ref_oms_niveles",
    "modelo.fact_medicion_diaria",
    "modelo.fact_medicion_horaria",
    "indicadores.agg_cumplimiento_diario",
    "indicadores.agg_anual",
    "indicadores.agg_cumplimiento_niveles",
    "indicadores.agg_rachas",
    "indicadores.agg_contexto_anual",
    "calidad.agg_completitud_mensual",
    "calidad.calidad_resumen",
    "calidad.calidad_violaciones",
    "calidad.calidad_outliers",
]
