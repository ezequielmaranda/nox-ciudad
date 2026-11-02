# nox-ciudad

TP integrador de Análisis de Datos 1: ¿qué le pasa al aire porteño cuando paran los colectivos?

Cruza calidad del aire (informes públicos de la APrA: Centenario, Córdoba y La Boca), transacciones SUBE por línea,
meteorología (registro diario del SMN) y un calendario de paros 2024-2026.

## Estructura

```
data/            fuera de git (tamaño)
  raw/           archivos originales, no se modifican: aire_publico/, smn/, sube/
  landing/       CSV en formato largo generados por extract/
  nox.duckdb     base con schemas bronze, silver y gold
extract/         crudo -> landing (un script por fuente)
dbt/             landing -> bronze -> silver -> gold
  seeds/         tablas chicas versionadas (eventos.csv, feriados.csv)
  tests/         tests de coherencia física y de negocio
analysis/        notebooks de EDA y consultas sueltas; leen gold
export/          gold exportado a Parquet para Power BI y Colab
```

## Arquitectura medallón

- **bronze**: los CSV de landing cargados tal cual (texto), con archivo de origen y fecha de carga.
- **silver**: tipado, normalizado y con flags de calidad (no se borran filas).
- **gold**: tablas analíticas para el EDA y el dashboard.

| Capa | Modelo | Grano | Para qué |
|---|---|---|---|
| bronze | bronze_aire, bronze_aire_manifiesto, bronze_sube, bronze_smn | igual que la fuente | carga cruda, todo texto |
| silver | silver_aire | estación × día × contaminante × estadístico | tipado + flags (estado_valor, fuera_de_rango, nox_incoherente, fuera_de_max_min) |
| silver | silver_sube, silver_colectivos_caba_linea_dia | línea × día | universo de colectivos que circulan por CABA |
| silver | silver_sube_actividad_diaria | día | usos por modo y `es_dia_normal` |
| silver | silver_smn_diario | estación × día | registro diario del SMN, una columna por variable |
| silver | dim_calendario | día | tipo de día, feriado, día normal, evento |
| gold | gold_aire_diario | estación × día | bloque 8-16 h, NOx/CO, promedios 24 h |
| gold | gold_sube_diario | día | dosis de paro y actividad vs. día hábil típico |
| gold | gold_meteo_diario | día | viento, temperatura, humedad y lluvia (SMN, promedio de 2 estaciones) |
| gold | **gold_analitico** | estación × día | **la tabla del análisis**: todo lo anterior unido |

## Cómo correrlo

```
uv sync
uv add requests pdfminer.six
uv run python extract/aire_publico.py
uv run python extract/sube_descarga.py
uv run python extract/smn_to_csv.py
uv add "duckdb>=1.5.4,<2" dbt-duckdb   # DuckDB 2.0 cambia el formato de archivo
cd dbt
uv run dbt build --profiles-dir .   # seeds + modelos + tests -> data/nox.duckdb
uv run dbt docs generate --profiles-dir . && uv run dbt docs serve --profiles-dir .   # documentación y linaje
```

## Notas de datos

- Calidad del aire: PDF mensuales públicos de la APrA, valores diarios y por bloques de 8 h.
  Los links originales dan 404: se descargan desde static.buenosaires.gob.ar.
- Meteorología: solo el registro diario del SMN (Aeroparque y Observatorio). Se probó Meteostat horario
  (ventana 8-16 h) y los resultados no cambian, así que se descartó.
- SMN diario: PRECIP falta en muchos días; VTO_MDIR está en decenas de grado.
