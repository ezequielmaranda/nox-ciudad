# Flujo ETL

Un solo comando (`python -m src.etl`) recorre el flujo de punta a punta en unos 10 segundos. La descarga del CSV
de BA Data es un paso aparte y opcional (`python -m src.extract`): el CSV crudo ya está en el repo.

```mermaid
flowchart LR
    subgraph FUENTE["Fuente pública"]
        BAD["BA Data · APrA<br/>calidad-aire.csv<br/>horario desde 2009<br/>CO · NO2 · PM10"]
    end

    subgraph ARCH["Archivos del repo"]
        CSV["data/raw/calidad-aire.csv<br/>147.470 filas fecha × hora<br/>ancho · todo texto"]
        REF["data/reference/<br/>oms_2021 · contaminantes<br/>estaciones · feriados"]
    end

    subgraph DB["data/warehouse/aire.duckdb (dbt build)"]
        BR["bronze<br/>el CSV tal cual<br/>+ referencias"]
        SI["silver<br/>UNPIVOT · tipos<br/>reglas por hora<br/>horas → día"]
        GO["gold<br/>estrella · guia_oms<br/>agg_anual<br/>calidad_resumen"]
    end

    subgraph FINAL["data/final"]
        OUT["8 tablas<br/>CSV"]
    end

    LK["dashboard/looker<br/>5 tablas planas"]
    LS["Looker Studio<br/>dashboard"]
    NB["notebooks/eda.ipynb<br/>EDA + figuras"]
    SQL["sql/99<br/>consultas de análisis"]

    BAD -- "src/extract.py<br/>(opcional)" --> CSV
    CSV --> BR
    REF --> BR
    BR --> SI --> GO
    BR --> GO
    GO --> OUT
    GO --> SQL
    OUT --> LK
    LK --> LS
    OUT --> NB
```

## Pasos

| # | Paso | Herramienta | Entrada → salida | Qué hace |
|---|---|---|---|---|
| 0 | **Descarga de la fuente** (opcional) | `src/extract.py` | BA Data → `data/raw/calidad-aire.csv` | Baja el CSV horario con reintentos, verifica que tenga las columnas esperadas y lo guarda tal como viene, sin convertir valores |
| 1 | **Extract** | `src/etl.py` | `data/raw/calidad-aire.csv` | Verifica que esté el crudo; los controles sobre su contenido los hacen los tests de dbt y las consultas A1 a A4 de `sql/99` |
| 2 | **Transform + Load** | dbt (`dbt build`) | raw + reference → DuckDB | **bronze:** carga el CSV como texto y las referencias (seeds). **silver:** UNPIVOT a formato largo, tipos, reglas de calidad por hora, valor diario según el promedio de cada contaminante. **gold:** dimensiones, guías OMS, grilla completa diaria con conversión de unidades y outliers, NO2 horario, indicadores por año (2010-2026) y últimos 12 meses con la regla del 75%, resumen de calidad. Corre los 87 tests de datos; si uno de tipo error falla, el ETL se detiene |
| 3 | **Export** | `src/etl.py` | gold → `data/final/` | Las 8 tablas de gold en CSV (UTF-8, separador `,`, decimal `.`), ordenadas para que dos corridas den archivos idénticos |
| 3b | **Tablas para Looker Studio** | `src/generar_looker.py` | `data/final/` → `dashboard/looker/` | Une dimensiones y guías a cada hecho y arma 5 tablas planas (Looker Studio no tiene relaciones entre tablas). No recalcula reglas |
| 4 | **Análisis SQL** | `src/etl.py` | `sql/99_consultas_analisis.sql` | Ejecuta las consultas de análisis (son de solo lectura) para verificar que todas corran |
| 5 | **Documentar** | `src/diccionario.py` | descripciones de dbt → `docs/diccionario_datos.md` | Genera el diccionario de datos desde los `.yml` de dbt |

Después: `python -m pytest -q` y el notebook (`python -m jupyter nbconvert --to notebook --execute --inplace notebooks/eda.ipynb`, que regenera `reports/figures/`).

## Propiedades

- **Idempotente:** cada corrida reconstruye las tablas desde cero (`materialized: table`) y sobrescribe las
  salidas. Dos corridas seguidas dan exactamente los mismos archivos (lo verifica `test_etl_es_idempotente`).
- **ELT, técnicamente:** el crudo se carga sin tocar a la base (bronze) y se transforma adentro con SQL. Es la
  forma habitual con DuckDB y dbt.
- **Nada se borra:** los valores con problemas se marcan en silver y en la fact; el análisis decide qué usar.
- **Rutas relativas:** todo cuelga de la raíz del repo (`src/config.py`); dbt se corre desde `dbt/` y llega a los archivos con `../`.
