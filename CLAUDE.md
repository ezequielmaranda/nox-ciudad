# CLAUDE.md · nox-ciudad

Contexto para seguir el proyecto en Claude Code. Idioma de trabajo: español rioplatense. El usuario es data engineer
con experiencia en monitoreo atmosférico: comunicación directa, sin vueltas.

## Qué es

TP integrador de **Análisis de Datos** (Licenciatura en Ciencia de Datos). Equipo de 4. Pregunta: ¿cuán lejos está
el aire de la Ciudad de Buenos Aires de las guías de la OMS 2021, y cómo varía entre estaciones, contaminantes, tipo
de día y período? El enunciado completo está en `PROYECTO_TP_AIRE_OMS.md`; la consigna de la cátedra pide flujo
completo (SQL, limpieza, ETL, EDA en Python, dashboard en **Power BI**) y poder justificar cada decisión.

Versión anterior del repo (paros de transporte, SUBE, meteorología del SMN, Looker Studio): **descartada** en
noviembre 2026 para simplificar. Está en la historia de git (hasta el commit `82aec79`).

## Reglas

- **Explicable antes que sofisticado.** Cualquier integrante tiene que poder explicar todo. Nada de orquestadores,
  ML ni infraestructura extra.
- **No se borran filas:** se marcan (flags, `motivo_sin_dato`, `es_outlier`). La limpieza vive en SQL (dbt).
- **Umbrales en tablas** (`data/reference/`, variables de `dbt_project.yml`), nunca escritos en el SQL.
- Código, comentarios y documentación en español; identificadores en snake_case sin tildes.
- Rutas relativas a la raíz (`src/config.py`; dbt usa la variable de entorno `AIRE_RAIZ`).
- Lenguaje de resultados: "es consistente con", "estimamos"; sin meteorología no se atribuyen causas.

## Stack y comandos

Python 3.11+ con `requirements.txt` (`make install`). DuckDB **fijado <2** (DuckDB 2 cambió el formato de archivo y
las herramientas 1.x no lo abren). dbt-duckdb. pandas, matplotlib, seaborn, pytest.

- `make etl` (= `python -m src.etl`): perfil del crudo → `dbt build` (en subproceso) → export a `data/final/`
  (CSV + Parquet, `order by all` para que sea idempotente) → corre `sql/99` → genera `docs/diccionario_datos.md`.
- `make test`: 18 tests de pytest (idempotencia incluida, ~20 s). `make eda`: ejecuta `notebooks/eda.ipynb`.
- `make extract` (= `python -m src.extract`): baja los PDF de la APrA. **Desde la nube de Claude no funciona**:
  `static.buenosaires.gob.ar` corta la conexión TLS (probablemente bloqueo geográfico). El CSV crudo está en git.

## Datos

- `data/raw/aire_publico.csv`: 83.010 valores (estación × fecha × contaminante × estadístico), todo texto, de 279
  PDF. Estadísticos: `24h`, `0-8`, `8-16`, `16-24`, `max_1h`, `min_1h`. Especiales: `s/d`, `DND`, `<x`, un `Lunes`.
- `data/raw/aire_publico_manifiesto.csv`: 281 PDF; 2 descartados (link a otra estación: NOx de Córdoba de jul-2025
  enlazado desde Centenario; PM10 de La Boca de feb-2026 enlazado desde Córdoba).
- `data/reference/`: `oms_2021.csv` (Tabla 0.1 del resumen ejecutivo OMS 2021), `contaminantes.csv` (peso molecular,
  tolerancias, máximos físicos), `estaciones.csv` (coordenadas aproximadas), `feriados.csv` (ArgentinaDatos),
  `eventos.csv` (paros, solo contexto).
- En git: crudo, referencias y `data/final/`. Fuera de git: `data/warehouse/`, `data/raw/pdf/`.

## Modelo (dbt, `data/warehouse/aire.duckdb`)

Schemas: `referencia` (seeds) → `staging` (`stg_aire`, `stg_aire_validado`, `stg_manifiesto`) → `modelo`
(`dim_calendario`, `dim_estacion`, `dim_contaminante`, `dim_periodo`, `dim_evento`, `ref_oms`, `ref_oms_niveles`,
`fact_medicion_diaria`) → `calidad` (`agg_completitud_mensual/anual`, `calidad_*`) → `indicadores`
(`agg_cumplimiento_diario`, `agg_anual`, `agg_rachas`). `sql/99` crea vistas en `analisis`.

- Fact: formato largo, grilla completa (1.004 × 3 × 5 × 2 = 30.120 filas), ventanas `24h` y `8-16`.
  `valor` en unidad original, `valor_masa` en unidad OMS (factor = peso molecular / 24,45).
- `<x` → x/2 (`es_imputado`). Reglas: fuera_de_rango, valor_trabado, cero_sin_respaldo, fuera_de_max_min,
  promedio_incoherente, mayor_que_nox, nox_incoherente (descarta NO y NOx, **no NO2**).
- Outliers: Q3 + 3·IQR por estación × contaminante × ventana, marcados.
- Regla del 75% sobre el promedio de 24 h por período (`dim_periodo`: 2024, 2025, 2026 parcial, `movil_12m`).
- Último build: 20 modelos, 74 tests + 5 seeds, PASS 98, WARN 1 (`stg_reglas_de_calidad`, esperado: 851 violaciones).

## Resultados verificados

- % días NO₂ > 25 µg/m³: La Boca 94,7% (944 d), Córdoba 84,4% (910), Centenario 50,3% (662). PM10 > 45: 2,3-4,1%.
  CO: 0%. El enunciado decía ~91/75/33%: dividía por todas las filas.
- NO₂ últimos 12 meses: La Boca 45,9 (4,6×, > IT1), Córdoba 35,0 (3,5×, IT1), Centenario 26,2 (2,6×, IT2).
  La Boca 2024: 56,5. PM10: 21,9-26,6 (1,5-1,8×, IT3); P99 de PM10 > 45 en todas las estaciones y años.
- No válidos por el 75%: NO₂ Centenario 2024 (18,9%), CO Córdoba 2024 (66,1%).
- Racha máxima NO₂: La Boca 216 días (25/03 a 26/10/2025), Córdoba 111, Centenario 22.
- Domingo vs. hábil (NO₂): −27% Centenario, −21% Córdoba, −17% La Boca; 90% de los domingos de La Boca sobre la guía.
- Invierno/verano NO₂ La Boca: 62,6 vs. 34,6 µg/m³.
- Ene-sep NO₂: 26,1 → 20,9 → 18,9 ppb juntando estaciones, inflado por falta de Centenario en 2024 (40 días). Por
  estación: La Boca −20%, Córdoba −14%, Centenario plano.
- Día 8: 43% de las incoherencias NOx y los 22 días de NO trabado.

## Pendiente

- Armar el `.pbix` siguiendo `docs/powerbi_spec.md` (lo hace el equipo; Claude Code no puede).
- Verificar las coordenadas aproximadas de `data/reference/estaciones.csv` si se usa el mapa.
- Preparar la presentación (guion en el README).
