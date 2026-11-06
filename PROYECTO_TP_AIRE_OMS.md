# TP Integrador — ¿Cuán lejos está el aire porteño de las guías de la OMS?

> Instrucciones para Claude Code. Este documento describe el proyecto completo a desarrollar en este repositorio.
> Leelo entero antes de empezar. Trabajá por etapas (ver "Plan de trabajo") y verificá cada etapa antes de pasar a la siguiente.

---

## 0. Contexto

Trabajo Práctico Integrador de la materia **Análisis de Datos** (Licenciatura en Ciencia de Datos). La consigna exige un flujo técnico completo:

1. Definición del problema / pregunta
2. Selección y comprensión del dataset
3. Almacenamiento / modelado
4. Consultas SQL
5. Limpieza, calidad y normalización
6. Flujo ETL
7. EDA en Python
8. Visualizaciones e indicadores
9. Dashboard en Power BI
10. Comunicación de hallazgos y limitaciones

**Criterio clave del docente:** no solo importa el resultado, sino poder **explicar y justificar cada decisión técnica**. Todo el código tiene que ser legible, comentado en español y reproducible con un solo comando.

**Rol del análisis:** equipo de datos de una agencia de calidad ambiental que informa a tomadores de decisión (público no técnico: funcionarios, prensa, ciudadanía).

---

## 1. Pregunta de análisis

**Pregunta principal:**
> ¿Cuán lejos está la calidad del aire de la Ciudad de Buenos Aires de las guías de calidad del aire de la OMS (2021), y cómo varía esa brecha entre estaciones, contaminantes, tipo de día y período?

**Subpreguntas:**
1. ¿Qué porcentaje de días se supera la guía diaria de la OMS, por estación y contaminante?
2. ¿Cuántas veces por encima de la guía anual están los promedios anuales?
3. ¿Qué estación tiene la peor situación y con qué contaminante? (hipótesis: el problema es el NO₂, no el PM10)
4. ¿Cambia el cumplimiento entre días hábiles, sábados, domingos y feriados?
5. ¿Hay estacionalidad (invierno vs verano)?
6. ¿Cuánto condiciona la calidad/completitud de los datos a las conclusiones?

**Hipótesis de trabajo:**
- H1: El NO₂ supera la guía diaria de la OMS la mayoría de los días; el PM10 casi nunca.
- H2: La Boca es la estación más comprometida en NO₂.
- H3: Los domingos y feriados la brecha se reduce de forma visible (menor actividad urbana).

---

## 2. Datos

### 2.1 Archivos de entrada

Ubicarlos en `data/raw/`:

| Archivo | Descripción |
|---|---|
| `gold_aire_diario.parquet` | Datos diarios de calidad del aire, 3 estaciones (dataset principal) |
| `gold_meteo_diario.parquet` | Datos meteorológicos diarios (**opcional**, solo para la extensión de la sección 9) |

> Si los nombres de archivo vienen con prefijos (ej. `22d34b30-gold_aire_diario.parquet`), renombrarlos.

### 2.2 `gold_aire_diario.parquet` (2.950 filas × 18 columnas)

- **Granularidad:** 1 fila = 1 estación × 1 día.
- **Estaciones:** `CENTENARIO`, `CORDOBA`, `LA BOCA`.
- **Período:** 2024-01-01 a 2026-09-30.

| Columna | Tipo | Descripción |
|---|---|---|
| `estacion` | str | Nombre de la estación |
| `fecha` | date | Fecha |
| `tipo_dia` | str | `hábil`, `sábado`, `domingo`, `feriado` |
| `nombre_dia` | str | lunes…domingo |
| `feriado` | str | Nombre del feriado (null si no es feriado) |
| `evento` | str | Evento especial, ej. paros (null en ~99%) |
| `grupo_evento` | str | `sin_colectivos`, `trenes_subte` |
| `no_816_ppb`, `no2_816_ppb`, `nox_816_ppb` | float | Promedio de 8 a 16 h (ppb) |
| `co_816_ppm` | float | Promedio de 8 a 16 h (ppm) |
| `pm10_816_ugm3` | float | Promedio de 8 a 16 h (µg/m³) |
| `nox_co_816` | float | Relación NOx/CO, 8 a 16 h |
| `no2_24h_ppb`, `nox_24h_ppb` | float | Promedio diario (ppb) |
| `no2_24h_ugm3` | float | NO₂ diario en µg/m³ (factor ≈ 1,88) |
| `co_24h_ppm` | float | CO diario (ppm) |
| `pm10_24h_ugm3` | float | PM10 diario (µg/m³) |

> Verificar en el EDA la interpretación de los sufijos `_816` (ventana 8–16 h) y `_24h` (promedio diario), y el factor de conversión de NO₂ (`no2_24h_ugm3 / no2_24h_ppb`).

### 2.3 Problemas de calidad ya detectados (hay que documentarlos y tratarlos)

- **Nulos:** el NO₂ tiene ~16% de nulos en total. En **Centenario el NO₂ cubre solo el 18% de 2024**: falta por completo de marzo a noviembre de 2024 y también julio de 2025.
- **Otros huecos mensuales relevantes:**
  - Córdoba: sin NO₂/CO en enero de 2024, sin CO de abril a mayo de 2024, sin PM10 en agosto de 2025 y febrero de 2026.
  - La Boca: PM10 casi nulo en septiembre y octubre de 2024, y nulo en enero de 2025.
- **Filas faltantes:** el período tiene 1.004 días, pero hay 991 / 988 / 971 filas por estación. Hay días sin fila, que hay que distinguir de días con fila y valores nulos.
- **Outliers a revisar:** `no_816_ppb` máximo de 424 ppb (mediana 22); PM10 de ~120 µg/m³ el 2025-11-18 (media ~23). No eliminarlos automáticamente: marcarlos, investigarlos y justificar la decisión.
- **Columnas casi vacías:** `feriado` (95% nulos) y `evento`/`grupo_evento` (99% nulos). Esos nulos son estructurales ("no aplica"), no faltantes.
- **Año 2026 parcial:** llega hasta septiembre y no es comparable directamente con los años completos.

---

## 3. Valores de referencia (OMS 2021)

Crear `data/reference/oms_2021.csv` con esta tabla y usarla vía JOIN. **No hardcodear umbrales en el código.**

| contaminante | promedio | guia_oms | it1 | it2 | it3 | it4 | unidad |
|---|---|---|---|---|---|---|---|
| NO2 | 24h | 25 | 120 | 50 | — | — | µg/m³ |
| NO2 | anual | 10 | 40 | 30 | 20 | — | µg/m³ |
| PM10 | 24h | 45 | 150 | 100 | 75 | 50 | µg/m³ |
| PM10 | anual | 15 | 70 | 50 | 30 | 20 | µg/m³ |
| CO | 24h | 4 | 7 | — | — | — | mg/m³ |

Notas:
- `it1…it4` son los **objetivos intermedios** (interim targets) de la OMS. Permiten mostrar "en qué escalón" está cada estación, no solo si cumple o no.
- Valores **verificados** contra la Tabla 0.1 ("Recommended AQG levels and interim targets") del resumen ejecutivo de *WHO global air quality guidelines* (2021). Citar esa fuente en el README.
- **Lectura de los niveles:** se cumple el nivel más exigente cuyo umbral el valor no supera. Por ejemplo, NO₂ anual de 35 µg/m³ → cumple IT1 (40), no cumple IT2 (30) → categoría "IT1". Si supera IT1 → categoría "> IT1" (no cumple ni el objetivo menos exigente).
- Agregar en `agg_anual` la columna `nivel_oms` (`AQG`, `IT4`…`IT1`, `> IT1`) y `ug_para_proximo_nivel` (cuánto hay que bajar para subir un escalón).
- Conversión de CO: 1 ppm ≈ 1,145 mg/m³ (25 °C, 1 atm). Documentar la conversión.
- La OMS define la guía de 24 h como el **percentil 99** de la distribución anual (equivale a unas 3–4 superaciones por año). Reportar las dos métricas: **% de días que superan** (más comunicable) y **percentil 99 anual vs guía** (lo formalmente correcto).

---

## 4. Criterios de calidad y completitud

Implementar estas reglas en SQL y documentarlas en `docs/calidad_datos.md`.

1. **Calendario completo:** generar una dimensión de fechas de 2024-01-01 a 2026-09-30 y hacer un cross join con las estaciones, para detectar días sin fila.
2. **Completitud por estación × contaminante × mes y × año:** `n_dias_con_dato / n_dias_calendario`.
3. **Regla del 75%:**
   - **Indicadores anuales** (promedio anual, percentil 99): solo se calculan si estación × contaminante × año tiene **≥ 75%** de días con dato. Si no, se marca `no_valido`. Con esta regla quedan afuera el NO₂ de Centenario en 2024 y el CO de Córdoba en 2024; verificarlo.
   - **Indicadores diarios** (% de días que superan): se usan todos los días con dato válido de todo el período, informando siempre el `n`.
   - **2026:** se presenta como **parcial (enero a septiembre)**. Para comparar con un año completo, calcular además un **promedio móvil de 12 meses** (octubre 2025 a septiembre 2026).
4. **Outliers:** marcarlos con un flag (`es_outlier`) usando IQR por estación y contaminante (Q3 + 3·IQR). No borrarlos. Revisar a mano los casos extremos y documentarlos.
5. **Rangos físicos:** validar que no haya valores negativos y que NO ≤ NOx y NO₂ ≤ NOx. Reportar las violaciones.

**Entregable de esta etapa:** una tabla/heatmap de completitud por estación × contaminante × mes, con lo que queda afuera y por qué. Es central para la exposición.

---

## 5. Arquitectura y stack

- **Python 3.11+** con `uv` o `venv` + `requirements.txt`.
- **DuckDB** como base analítica: lee parquet nativamente, usa SQL estándar, está en un solo archivo y es fácil de explicar. Si la cátedra exige otro motor (SQLite/PostgreSQL), el SQL tiene que ser fácilmente portable: evitar funciones exóticas y comentar las específicas de DuckDB.
- **pandas**, **matplotlib/seaborn** (EDA), **statsmodels** (opcional) y **pytest**.
- **Jupyter** para el notebook de EDA.
- **Power BI:** Claude Code no puede construir el `.pbix`. Su trabajo es dejar listos los datos finales, el modelo, las medidas DAX y un spec del dashboard (ver sección 8).

### Estructura del repositorio

```
.
├── README.md                    # Cómo correr todo + resumen del proyecto
├── PROYECTO_TP_AIRE_OMS.md      # Este archivo
├── requirements.txt
├── Makefile                     # make all / make etl / make test / make eda
├── data/
│   ├── raw/                     # Parquets originales (NO modificar)
│   ├── reference/oms_2021.csv
│   ├── warehouse/aire.duckdb    # Base generada
│   └── final/                   # CSV/Parquet para Power BI
├── sql/
│   ├── 01_staging.sql
│   ├── 02_dimensiones.sql
│   ├── 03_fact.sql
│   ├── 04_calidad.sql
│   ├── 05_indicadores.sql
│   └── 99_consultas_analisis.sql   # Consultas comentadas que responden cada subpregunta
├── src/
│   ├── etl.py                   # Orquesta extract → transform → load
│   ├── calidad.py
│   └── config.py
├── notebooks/
│   └── eda.ipynb
├── tests/
│   └── test_etl.py
├── docs/
│   ├── diagrama_etl.md          # Diagrama Mermaid del flujo
│   ├── modelo_datos.md          # Diagrama Mermaid del esquema estrella
│   ├── calidad_datos.md
│   ├── diccionario_datos.md
│   └── powerbi_spec.md
└── reports/figures/             # PNGs exportados del EDA
```

---

## 6. Modelo de datos (esquema estrella)

La consigna valora "más de una tabla relacionada". Con un solo dataset fuente, se resuelve modelando:

- `dim_estacion` (id_estacion, nombre, descripción/zona si se conoce)
- `dim_calendario` (fecha, año, mes, nombre_mes, estación_del_año, día_semana, tipo_dia, es_feriado, nombre_feriado, es_fin_de_semana)
- `dim_contaminante` (id_contaminante, codigo, nombre, unidad, descripción)
- `dim_evento` (fecha, evento, grupo_evento), para contexto
- `ref_oms` (contaminante, promedio, guía, objetivos intermedios)
- `fact_medicion_diaria` en **formato largo**: (fecha, id_estacion, id_contaminante, ventana [`24h`/`8-16`], valor, valor_ugm3, es_outlier, tiene_dato)

**Por qué formato largo:** simplifica el JOIN con `ref_oms`, permite filtrar por contaminante en Power BI con un segmentador y es la forma estándar de un modelo estrella. Documentar en `docs/modelo_datos.md` la decisión y su alternativa (formato ancho).

Tablas derivadas para análisis/Power BI:
- `agg_cumplimiento_diario`: por día × estación × contaminante, valor vs guía, `supera_guia` (bool), `veces_guia` (valor/guía) y `nivel_it` (en qué objetivo intermedio cae).
- `agg_anual`: por año × estación × contaminante, promedio anual, percentil 99, n_dias, completitud, `es_valido`, veces_guia_anual y % de días que superan.
- `agg_completitud_mensual`.

---

## 7. ETL

`src/etl.py` debe:

1. **Extract:** leer los parquet de `data/raw/` (con DuckDB `read_parquet`) y registrar en un log filas, columnas y rango de fechas.
2. **Transform:**
   - Normalizar nombres (snake_case, sin tildes en los identificadores) y tipos (`fecha` → DATE).
   - Normalizar `tipo_dia` (por ejemplo, `hábil` → `habil` en los códigos, dejando etiquetas legibles para la visualización).
   - Pasar de ancho a largo (UNPIVOT).
   - Convertir unidades (CO ppm → mg/m³; NO₂ ya viene en µg/m³ en `no2_24h_ugm3`; verificar que el factor sea consistente).
   - Construir las dimensiones y el calendario completo.
   - Calcular los flags de outlier y de completitud.
3. **Load:** escribir en `data/warehouse/aire.duckdb` y exportar a `data/final/` las tablas para Power BI, en **CSV (UTF-8, separador `,`, decimal `.`) y Parquet**.
4. Ejecutar los SQL de `sql/` en orden. Cada archivo SQL debe estar **comentado en español** explicando qué hace y por qué.
5. Ser **idempotente**: correrlo dos veces da el mismo resultado.

Generar `docs/diagrama_etl.md` con un diagrama Mermaid del flujo: raw → staging → dims/fact → agregados → final → Power BI.

### Consultas SQL de análisis (`sql/99_consultas_analisis.sql`)

Cada consulta precedida por un comentario con: **qué subpregunta responde**, por qué es necesaria y qué técnica SQL muestra. Incluir como mínimo:

- Perfilado: conteo de filas, nulos por columna, duplicados (estación + fecha).
- Días faltantes con calendario + LEFT JOIN.
- Completitud por estación × contaminante × año (GROUP BY, CASE, COUNT con condición).
- % de días que superan la guía diaria (JOIN con `ref_oms`).
- Promedio anual vs guía anual y "veces por encima".
- Percentil 99 anual (`quantile_cont` / `percentile_cont`).
- Cumplimiento por `tipo_dia` y por estación del año.
- Ranking de estaciones (window function `RANK()`).
- Racha más larga de días consecutivos superando la guía de NO₂ por estación (gaps & islands con `ROW_NUMBER()`).
- Comparación enero–septiembre por año (mismos meses, para no mezclar estacionalidad).
- Vistas (`CREATE VIEW`) para las consultas que consume Power BI.

---

## 8. EDA y salidas

### 8.1 `notebooks/eda.ipynb`

Ordenado según las subpreguntas, **no como una colección de gráficos sueltos**. Cada sección con una celda markdown que explique qué se busca y qué se concluye. Secciones:

1. Estructura y tipos.
2. Calidad: heatmap de completitud por estación × contaminante × mes, y outliers identificados y su tratamiento.
3. Distribuciones por contaminante y estación (histogramas, boxplots), con la línea de la guía OMS marcada.
4. Serie temporal diaria por estación con la línea de la guía OMS y medias móviles de 30 días.
5. % de días que superan la guía, por estación × contaminante (barras).
6. Promedio anual vs guía anual y objetivos intermedios (barras horizontales con líneas de referencia).
7. Cumplimiento por `tipo_dia` y por estación del año.
8. Ritmo semanal (NO₂ por día de la semana).
9. Correlación entre contaminantes por estación.
10. Conclusiones exploratorias.

Exportar las figuras clave a `reports/figures/`, con títulos y ejes en español, unidades en los ejes y la guía OMS siempre visible como referencia.

### 8.2 Hallazgos preliminares (verificar, no asumir)

Del análisis exploratorio previo:
- % de días con NO₂ diario > 25 µg/m³: La Boca ~91%, Córdoba ~75%, Centenario ~33%. PM10 > 45: ~2–4% en todas.
- Promedio anual de NO₂ en La Boca: ~47–56 µg/m³ (guía: 10).
- NO₂ por tipo de día respecto del día hábil: domingo entre −17% y −27% según la estación.
- NO₂ enero–septiembre por año: 26,1 → 20,8 → 18,9 ppb (2024 → 2026). Ojo: sin controlar la meteorología no se puede atribuir a una mejora real.

Si los resultados del pipeline difieren de estos números, investigar por qué antes de seguir.

### 8.3 Power BI (`docs/powerbi_spec.md`)

Generar un spec que el equipo pueda seguir a mano:
- Qué archivos de `data/final/` importar y las relaciones del modelo (claves, cardinalidad, dirección del filtro).
- **Medidas DAX** listas para copiar, como mínimo: `% Días sobre guía`, `Promedio anual`, `Veces sobre guía anual`, `Percentil 99`, `Completitud %`, `Días válidos`, `Racha máxima`.
- Layout sugerido de 3 páginas:
  1. **Resumen:** KPIs (% de días sobre la guía de NO₂, veces sobre la guía anual, estación más comprometida) y un mapa o tarjetas por estación.
  2. **Detalle:** serie temporal con la línea de la guía, barras por estación/contaminante y matriz por tipo de día y estación del año.
  3. **Calidad de datos:** heatmap de completitud y qué quedó afuera y por qué.
- Segmentadores: estación, contaminante, año, tipo de día, estación del año.
- Paleta: evitar el rojo/verde como única codificación (accesibilidad). Sugerir colores por nivel OMS (guía / IT).

---

## 9. Extensión opcional: meteorología

**Solo si sobra tiempo y el equipo lo aprueba.** `gold_meteo_diario.parquet` (943 filas, 1 fila por día, de 2024-01-01 a 2026-07-31): `viento_kmh`, `viento_max_kmh`, `temp_c`, `humedad_pct`, `precipitacion_mm`, `precipitacion_sin_registro` (bool), `hubo_lluvia` (bool).

Uso propuesto: mostrar cómo cambia el % de días sobre la guía según los rangos de viento (exploratorio: ~81% con menos de 7 km/h contra ~48% con más de 16 km/h para el NO₂). Precauciones:
- Termina el 2026-07-31, dos meses antes que el de aire.
- Hay que decidir y documentar cómo se trata `precipitacion_sin_registro`.

No convertir esto en la pregunta principal.

---

## 10. Tests (`tests/test_etl.py`)

- La fact no tiene duplicados por (fecha, estación, contaminante, ventana).
- Todas las fechas de la fact existen en `dim_calendario`.
- No hay valores negativos.
- El factor NO₂ µg/m³ / ppb es consistente (≈ 1,88 ± tolerancia).
- `ref_oms` tiene todas las combinaciones contaminante × promedio que se usan.
- Los indicadores anuales con completitud < 75% están marcados como no válidos.
- El ETL es idempotente (dos corridas dan el mismo conteo de filas).

---

## 11. Documentación y exposición

- **README.md:** objetivo, pregunta, cómo instalar y correr (`make all`), estructura, fuentes (incluida la cita del documento OMS 2021), decisiones técnicas clave y limitaciones.
- **docs/diccionario_datos.md:** todas las columnas de las tablas finales.
- **Sección de limitaciones** (en el README y en el notebook), como mínimo:
  - Solo 3 estaciones, lo que limita la representatividad espacial de la ciudad.
  - Huecos de datos (especialmente el NO₂ de Centenario en 2024).
  - 2026 parcial.
  - Sin control meteorológico (salvo la extensión opcional): las diferencias entre períodos pueden deberse al clima.
  - La guía de 24 h de la OMS es estadísticamente un P99; el "% de días" es una simplificación comunicacional.
  - Los datos de entrada ya vienen agregados a nivel diario ("gold"). Documentar su origen aguas arriba (mediciones horarias → promedio diario) y aclarar que el ETL del TP arranca desde esa capa.

---

## 12. Plan de trabajo (en este orden)

1. Setup del repo: estructura, `requirements.txt`, `Makefile`, `.gitignore` (ignorar `data/warehouse/` y `.ipynb_checkpoints`).
2. Perfilado inicial de los parquet, para confirmar lo de la sección 2.
3. `oms_2021.csv` con los valores verificados.
4. SQL de staging, dimensiones y fact.
5. SQL de calidad y completitud, más `docs/calidad_datos.md`.
6. SQL de indicadores y exportación a `data/final/`.
7. Tests.
8. Notebook de EDA.
9. Consultas de análisis comentadas.
10. Documentación: diagramas, diccionario y spec de Power BI.
11. README final con hallazgos y limitaciones.

En cada paso: correr, verificar el resultado y recién después avanzar. Si algo de este documento no coincide con lo que muestran los datos, **priorizar los datos y avisar** en lugar de forzar lo que dice el documento.

### Convenciones

- Código, comentarios y documentación en **español**; identificadores en snake_case sin tildes.
- Commits chicos y descriptivos, uno por etapa.
- Nada de rutas absolutas; todo relativo a la raíz del repo vía `src/config.py`.
