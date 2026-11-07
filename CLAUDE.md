# CLAUDE.md · nox-ciudad

Contexto para seguir el proyecto en Claude Code. Idioma de trabajo: español rioplatense. El usuario es data engineer
con experiencia en monitoreo atmosférico: comunicación directa, sin vueltas.

## Qué es

TP integrador de **Análisis de Datos** (Licenciatura en Ciencia de Datos). Equipo de 4. Pregunta: ¿cuán lejos está
el aire de la Ciudad de Buenos Aires de las guías de la OMS 2021, y cómo varía entre estaciones, contaminantes, tipo
de día y período? La referencia es la **consigna de la cátedra** (PDF "Trabajo Práctico Integrador", fuera del repo):
10 etapas (problema e hipótesis, dataset, modelado, SQL, limpieza y calidad, ETL, EDA en Python, visualizaciones e
indicadores, dashboard en **Power BI**, conclusiones), exposición grupal de 20 minutos y poder justificar cada
decisión técnica. El README tiene la tabla "Cómo cubre el TP la consigna". La guía `PROYECTO_TP_AIRE_OMS.md`, que
venía de otro chat, se sacó del repo: no es la consigna.

Hipótesis (reescritas por el equipo como expectativas previas al análisis, sin detalles que solo se saben después):
- **H1:** el NO₂ es el contaminante más crítico: el que más se aleja de las guías de la OMS. → Se sostiene (50-95% de días sobre la guía vs. 2-4% del PM10 y 0% del CO).
- **H2:** Córdoba, la estación ubicada sobre una avenida de tránsito intenso, es la más comprometida en NO₂. → **No se sostiene**: la peor es La Boca (flujo medio-bajo, fuentes fijas); Córdoba es segunda.
- **H3:** domingos y feriados la brecha se reduce de forma visible. → A medias.
La matriz de escalones (hasta qué IT cumple cada estación) ya no es una hipótesis: responde las subpreguntas 1 y 2.
Fundamentación (README, "De dónde salen las hipótesis", con fuentes): premisa común "el NO₂ de la Ciudad viene sobre
todo del tránsito" (Bogo et al. 1999) aplicada a cada corte. H1: la OMS 2021 endureció el NO₂ anual 4 veces (40→10)
y el PM10 poco (20→15, 50→45). H2: la APrA describe a Córdoba con flujo vehicular alto y a La Boca medio-bajo con
fuentes fijas; en Europa las superaciones de NO₂ son en estaciones de tránsito (EEA). H3: efecto fin de semana
(Beirle et al. 2003). El período no tiene hipótesis (sin meteorología no hay base). Resultado conjunto: el tránsito
explica buena parte del NO₂, pero no todo.

Versión anterior del repo (paros de transporte, SUBE, meteorología del SMN, Looker Studio): **descartada** en
noviembre 2026 para simplificar. Está en la historia de git (hasta el commit `82aec79`).

## Reglas

- **Explicable antes que sofisticado.** Cualquier integrante tiene que poder explicar todo. Nada de orquestadores,
  ML ni infraestructura extra.
- **No se borran filas:** se marcan (flags, `motivo_sin_dato`, `es_outlier`). La limpieza vive en SQL (dbt).
- **Umbrales en tablas** (`data/reference/`, variables de `dbt_project.yml`), nunca escritos en el SQL.
- Código, comentarios y documentación en español; identificadores en snake_case sin tildes.
- Rutas relativas a la raíz (`src/config.py`); dbt se corre siempre desde `dbt/` y llega a los archivos con `../`.
- Lenguaje de resultados: "es consistente con", "estimamos"; sin meteorología no se atribuyen causas.

## Stack y comandos

Todo el equipo usa Windows: no hay Makefile, los comandos van con `.venv\Scripts\python`.
Python 3.11+ con `requirements.txt`. DuckDB **fijado <2** (DuckDB 2 cambió el formato de archivo y
las herramientas 1.x no lo abren). dbt-duckdb. pandas, matplotlib, seaborn, sweetviz, pytest.
El EDA tiene un perfil automático con Sweetviz (`reports/sweetviz_*.html`; correrlo dentro de `plt.rc_context()`
porque cambia las fuentes de matplotlib) y gráficos con seaborn (boxplot, histograma, barras y líneas con IC 95%,
heatmap) y matplotlib.

- `python -m src.etl`: verifica el crudo → `dbt build` (en subproceso) → export a `data/final/`
  (solo CSV, `order by all` para que sea idempotente) → corre `sql/99` → genera `docs/diccionario_datos.md`.
- `python -m pytest -q`: 8 tests de pytest (~20 s). División: **dbt prueba los datos; pytest, el código y el pipeline**
  (idempotencia, vistas de `sql/99`, funciones del extractor). No duplicar tests de datos en pytest. El EDA se ejecuta con
  `python -m jupyter nbconvert --to notebook --execute --inplace notebooks/eda.ipynb`.
- `python -m src.generar_pbip`: genera `dashboard/AireOMS.pbip` (modelo TMDL con 14 tablas + `_Medidas`,
  20 relaciones, 18 medidas DAX, orden de columnas, descripciones de dbt, tema; informe PBIR con 3 páginas vacías).
  Validado con TmdlSerializer (paquete NuGet Microsoft.AnalysisServices.NetCore.retail.amd64; la salida es idéntica a
  su reserialización) y con los esquemas de microsoft/json-schemas; no se abrió en Power BI Desktop. Después pasó de Parquet a CSV (`Csv.Document` + tipos en-US): ese cambio no se revalidó. El tema base
  `src/recursos/Fluent2-CY26SU08.json` viene de microsoft/fabric-toolbox (MIT). No regenera si ya hay gráficos.
- `python -m src.extract`: baja los PDF de la APrA. **Desde la nube de Claude no funciona**:
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
(`dim_calendario`, `dim_estacion`, `dim_contaminante`, `dim_periodo`, `ref_oms`, `ref_oms_niveles`,
`fact_medicion_diaria`) → `calidad` (`agg_completitud_mensual/anual`, `calidad_*`) → `indicadores`
(`agg_cumplimiento_diario`, `agg_anual`, `agg_rachas`). `sql/99` crea vistas en `analisis`.

- Fact: formato largo, grilla completa (1.004 × 3 × 5 × 2 = 30.120 filas), ventanas `24h` y `8-16`.
  `valor` en unidad original, `valor_masa` en unidad OMS (factor = peso molecular / 24,45).
- `<x` → x/2 (`es_imputado`). Reglas: fuera_de_rango, valor_trabado, cero_sin_respaldo, fuera_de_max_min,
  promedio_incoherente, mayor_que_nox, nox_incoherente (descarta NO y NOx, **no NO2**).
- Outliers: Q3 + 3·IQR por estación × contaminante × ventana, marcados.
- Regla del 75% sobre el promedio de 24 h por período (`dim_periodo`: 2024, 2025, 2026 parcial, `movil_12m`).
- Último build: 20 modelos, 76 tests + 5 seeds, PASS 100, WARN 1 (`stg_reglas_de_calidad`, esperado: 851 violaciones).

## Resultados verificados

- % días NO₂ > 25 µg/m³: La Boca 94,7% (944 d), Córdoba 84,4% (910), Centenario 50,3% (662). PM10 > 45: 2,3-4,1%.
  CO: 0%. Denominador = días con dato (dividir por todas las filas daría ~91/75/33%, que subestima).
- NO₂ últimos 12 meses: La Boca 45,9 (4,6×, > IT1), Córdoba 35,0 (3,5×, IT1), Centenario 26,2 (2,6×, IT2).
- Matriz de escalones (`agg_cumplimiento_niveles`, figura 06b): La Boca cumple el IT2 diario 40% → 54% → 58% de los
  días (2024 → 2025 → 2026 ene-sep); Córdoba 84-92%; Centenario 98-100%.
- Regla del 75%: es el criterio anual de la EPA (40 CFR 50 Ap. S); la UE pide 90% (Dir. 2008/50 Anexo XI); la OMS no
  fija ninguno. Se agregó `cumple_criterio_trimestral` (EPA: 75% en cada trimestre) como advertencia. Sensibilidad
  en `docs/calidad_datos.md` §3.2: los escalones de cada estación no cambian con el criterio más estricto.
- Días que cumplen el IT2 diario de NO₂ (50): Centenario 98,6%, Córdoba 87,7%, La Boca 49,7%. IT1 diario (120):
  todos los días salvo uno en La Boca (124). PM10 cumple la guía diaria el 95,9-97,7% de los días.
  La Boca 2024: 56,5. PM10: 21,9-26,6 (1,5-1,8×, IT3); P99 de PM10 > 45 en todas las estaciones y años.
- No válidos por el 75%: NO₂ Centenario 2024 (18,9%), CO Córdoba 2024 (66,1%).
- Racha máxima NO₂: La Boca 216 días (25/03 a 26/10/2025), Córdoba 111, Centenario 22.
- Domingo vs. hábil (NO₂): −27% Centenario, −21% Córdoba, −17% La Boca; 90% de los domingos de La Boca sobre la guía.
- Invierno/verano NO₂ La Boca: 62,6 vs. 34,6 µg/m³.
- Ene-sep NO₂: 26,1 → 20,9 → 18,9 ppb juntando estaciones, inflado por falta de Centenario en 2024 (40 días). Por
  estación: La Boca −20%, Córdoba −14%, Centenario plano.
- Día 8: 43% de las incoherencias NOx y los 22 días de NO trabado.

## Pendiente

- Abrir `dashboard/AireOMS.pbip` en Power BI Desktop (parámetro `RutaDatos` con la ruta local de `data/final\`,
  Actualizar) y armar los gráficos de las 3 páginas siguiendo `docs/powerbi_spec.md` (lo hace el equipo). Después
  de armar gráficos, el modelo se toca desde Power BI, no con `src.generar_pbip`.
- Verificar las coordenadas aproximadas de `data/reference/estaciones.csv` si se usa el mapa.
- Preparar la presentación (guion en el README).
