"""Rutas y parámetros del proyecto, todo relativo a la raíz del repo (sin rutas absolutas)."""

from pathlib import Path

# Raíz del repo: la carpeta que contiene a src/
RAIZ = Path(__file__).resolve().parent.parent

# Datos
DIR_RAW = RAIZ / "data" / "raw"                    # crudos (no se modifican a mano)
DIR_PDF = DIR_RAW / "pdf"                          # PDF originales de la APrA (fuera de git)
RAW_AIRE = DIR_RAW / "aire_publico.csv"            # salida de la extracción de los PDF
RAW_MANIFIESTO = DIR_RAW / "aire_publico_manifiesto.csv"
DIR_REFERENCIA = RAIZ / "data" / "reference"       # tablas de referencia (OMS, feriados, etc.)
DIR_WAREHOUSE = RAIZ / "data" / "warehouse"
BASE_DUCKDB = DIR_WAREHOUSE / "aire.duckdb"        # base analítica que arma dbt
DIR_FINAL = RAIZ / "data" / "final"                # CSV y Parquet para Power BI y el EDA

# Transformaciones y salidas
DIR_DBT = RAIZ / "dbt"
DIR_SQL = RAIZ / "sql"
DIR_FIGURAS = RAIZ / "reports" / "figures"
DIR_DOCS = RAIZ / "docs"

# Tablas que se exportan a data/final (schema.tabla de la base DuckDB).
# El orden es el que conviene seguir al importarlas en Power BI: dimensiones, hechos, agregados.
TABLAS_FINALES = [
    "modelo.dim_estacion",
    "modelo.dim_contaminante",
    "modelo.dim_calendario",
    "modelo.dim_periodo",
    "modelo.dim_evento",
    "modelo.ref_oms",
    "modelo.ref_oms_niveles",
    "modelo.fact_medicion_diaria",
    "indicadores.agg_cumplimiento_diario",
    "indicadores.agg_anual",
    "indicadores.agg_cumplimiento_niveles",
    "indicadores.agg_rachas",
    "calidad.agg_completitud_mensual",
    "calidad.agg_completitud_anual",
    "calidad.calidad_resumen",
    "calidad.calidad_violaciones",
    "calidad.calidad_outliers",
    "calidad.calidad_archivos",
]
