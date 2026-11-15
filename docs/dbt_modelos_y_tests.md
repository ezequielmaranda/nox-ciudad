# Modelos y tests de dbt

Qué hace cada modelo y qué verifica cada test del proyecto `dbt/`. Complementa a
[`modelo_datos.md`](modelo_datos.md) (estrella, claves y relaciones) y a
[`calidad_datos.md`](calidad_datos.md) (reglas de limpieza y su justificación). Las columnas de cada
tabla están en [`diccionario_datos.md`](diccionario_datos.md), que se genera solo.

Los modelos y los tests se corren con `dbt build` (lo hace `python -m src.etl`). El principio: **dbt prueba los
datos; pytest, el código y el pipeline**.

## 1. Modelos

El flujo es bronze (la fuente tal como llega) → silver (limpio) → gold (lo que se analiza y se exporta a
`data/final/`). Cada carpeta de `dbt/models/` es un schema de `data/warehouse/aire.duckdb`.
Los umbrales y parámetros salen de las seeds y de las variables de `dbt_project.yml`, nunca del SQL.

### Bronze

| Modelo | Qué hace |
|---|---|
| `calidad_aire` | Lee `data/raw/calidad-aire.csv` con `read_csv(all_varchar)`. Todo queda como texto y no se corrige nada. Formato ancho: una fila por fecha y hora, una columna por estación × contaminante. |
| Seeds `oms_2021`, `contaminantes`, `estaciones`, `feriados` | Los CSV de `data/reference/`. Guías de la OMS, pesos moleculares y máximos plausibles, datos de las estaciones y feriados. |

### Silver

| Modelo | Grano | Qué hace |
|---|---|---|
| `medicion_horaria` | fecha × hora × estación × contaminante (1.327.230 filas = CSV × 9) | Pasa de ancho a largo con `UNPIVOT ... INCLUDE NULLS` (sin Palermo). Parsea la fecha (`12FEB2011:00:00:00`) y la hora (1-24 = hora que termina). Clasifica el texto en `estado_valor`: `s/d` o vacío → `sin_dato`; `<x` → `bajo_limite_deteccion` con valor = x/2; `#REF!` o `x/d` → `invalido`. Aplica las reglas y deja el primer motivo que corresponda en `motivo_invalido`: `hora_invalida`, `sin_dato_fuente`, `texto_invalido`, `fuera_de_rango`, `fila_en_cero`, `valor_trabado`. No borra filas: marca `es_valido`. |
| `medicion_diaria` | fecha × estación × contaminante (toda la serie, solo días presentes en la fuente) | Arma el valor diario según cómo publica la fuente cada contaminante. NO₂ (promedio horario): promedio de las horas válidas, solo si hay al menos 18 de 24 (`horas_minimas_dia`). PM10 (móvil de 24 h): el valor de la hora 24. CO (móvil de 8 h): promedio de las horas 8, 16 y 24 (hacen falta las tres). Si no alcanza, `valor_diario` es nulo y `motivo_sin_dato` es `sin_dato_fuente` o `incompleto`. |

Detalles de las reglas por hora:
- `fila_en_cero`: todas las mediciones de esa fecha y hora valen 0 (planilla vacía cargada con ceros).
- `valor_trabado`: NO₂ idéntico `horas_valor_trabado` (10) horas seguidas o más, detectado con gaps-and-islands. Solo
  NO₂, porque CO y PM10 son promedios móviles y repiten valores.

### Gold

| Modelo | Grano | Qué hace |
|---|---|---|
| `dim_calendario` | día del período de estudio (2024-01-01 a 2026-09-30) | Año, mes, estación del año del hemisferio sur, `tipo_dia` (el feriado tiene prioridad sobre sábado y domingo) y columnas `orden_*` para Power BI. |
| `dim_estacion` | estación | Viene de `estaciones.csv`: entorno, flujo vehicular, fuentes fijas y coordenadas. Es la base de H2. |
| `dim_contaminante` | contaminante | Unidades y `factor_masa` = peso molecular / 24,45 (25 °C, 1 atm), que pasa ppb o ppm a µg/m³ o mg/m³. NO₂ 1,88; CO 1,146; PM10 1. |
| `guia_oms` | contaminante × promedio × nivel | Pasa la seed ancha a largo con `UNPIVOT`: una fila por AQG, IT4, IT3, IT2 e IT1. |
| `fact_medicion_diaria` | fecha × estación × contaminante (9.036 filas) | Centro de la estrella. Grilla completa (calendario × estaciones × contaminantes) con `LEFT JOIN` a lo medido, así cada combinación existe. `motivo_sin_dato` distingue `sin_fila`, `sin_dato_fuente` e `incompleto`. Convierte a µg/m³ (`valor_masa`), marca `supera_guia`, el escalón `nivel_oms` y `es_outlier` (valor > Q3 + 3·IQR por estación × contaminante; se marca, no se borra). |
| `fact_medicion_horaria` | fecha × hora × estación (70.704 filas) | Solo NO₂, el único publicado como promedio de cada hora. Sirve para el perfil horario y el efecto domingo. Incluye las horas no válidas con su motivo, para poder contarlas. |
| `agg_anual` | estación × contaminante × período | Indicadores por año (2010-2026) y `movil_12m`. Regla del 75%: si el período tiene menos de 75% de días con dato, el promedio, el P99 y los porcentajes quedan nulos (el promedio igual va en `promedio_referencial`). Calcula el promedio anual contra la guía y su escalón, el próximo escalón y los µg/m³ que faltan, el P99, el % de días sobre la guía, el % de días que cumplen cada escalón y la racha máxima de días sobre la guía (huecos de hasta 7 días sin dato no la cortan). `es_periodo_estudio` separa el estudio del contexto. |
| `calidad_resumen` | contaminante × categoría | Por contaminante, cuántos valores horarios son válidos o fueron descartados por cada motivo, la proporción y entre qué fechas aparecen. |

El macro `generate_schema_name` hace que los schemas se llamen exactamente `bronze`, `silver` y `gold` (por defecto dbt
los llamaría `main_silver`, etc.).

## 2. Tests

### 2.1 Tests singulares (`dbt/tests/*.sql`)

Cada uno es una consulta que devuelve las filas que violan la regla: pasa si devuelve 0 filas.

| Test | Qué verifica |
|---|---|
| `silver_conserva_celdas_del_crudo` | Silver tiene exactamente filas de bronze × 9. Falla si el `UNPIVOT` o un `JOIN` pierde o duplica filas. Es la garantía de "no se borra ninguna fila". |
| `silver_valores_descartados` | **Aviso (`warn`), no frena el build.** Cuenta los valores del período de estudio que descartó una regla de calidad (239 en el último build). Describe la fuente, no es un error. |
| `diario_no2_minimo_horas` | Todo promedio diario de NO₂ con dato sale de al menos 18 horas válidas. |
| `diario_coincide_con_horario` | El valor diario de NO₂ de la fact diaria es igual (±0,01) al promedio de sus horas en la fact horaria. Las dos facts no pueden contradecirse. |
| `fact_grilla_completa` | La fact diaria tiene exactamente días × estaciones × contaminantes filas. |
| `fact_outliers_marcados_no_borrados` | Un outlier conserva su `valor`, `valor_masa` y `tiene_dato`. |
| `factor_conversion_no2` | El factor es ≈1,88 para NO₂ y ≈1,145 para CO en la dimensión, y en la fact `valor_masa / valor` da ese factor. |
| `guia_oms_cubre_indicadores` | Existen las guías AQG que usan los indicadores (24 h para NO₂, PM10 y CO; anual para NO₂ y PM10). Si alguien borra una fila del CSV de referencia, falla en vez de dejar indicadores vacíos. |
| `anual_regla_75` | Con completitud < 75%, `es_valido` es falso y no hay promedio ni P99. Con 75% o más, es válido. |
| `anual_escalones_acumulativos` | Los porcentajes cumplen guía ≤ IT4 ≤ IT3 ≤ IT2 ≤ IT1: un día que cumple un nivel más exigente cumple los menos exigentes. |
| `anual_casos_conocidos` | Regresión sobre casos documentados: NO₂ de Centenario 2024 (la estación no midió de marzo a noviembre) y CO de Córdoba 2024 (61,5% de días con dato) tienen que quedar **no** válidos. |

### 2.2 Tests genéricos (`dbt/tests/generic/`)

Plantillas que se reusan desde los `.yml`.

| Test | Qué verifica |
|---|---|
| `clave_unica(columnas)` | La combinación de columnas no se repite (clave primaria compuesta). |
| `entre(minimo, maximo)` | Los valores están en el rango (inclusive). Ignora los nulos: para eso está `not_null`. |

### 2.3 Tests declarados en los `.yml`

| Tipo | Dónde se usa |
|---|---|
| `not_null` y `unique` | Claves y columnas críticas de seeds y dimensiones, `tiene_dato`, `es_valido`, `es_outlier`, `factor_masa`, `umbral`. |
| `accepted_values` | `id_estacion`, `id_contaminante`, `estado_valor`, `motivo_invalido`, `motivo_sin_dato`, `nivel_oms`, `tipo_dia`, `estacion_del_anio`, `tipo_periodo`, `promedio` ('24h' o 'anual'). Un valor nuevo e inesperado frena el build. |
| `relationships` | Claves foráneas de la estrella: las facts y `agg_anual` hacia `dim_calendario`, `dim_estacion` y `dim_contaminante`; `guia_oms` y `calidad_resumen` hacia `dim_contaminante`; `oms_2021` hacia `contaminantes`. |
| `clave_unica` | Define el grano de cada tabla: `medicion_horaria` (fecha, hora, estación, contaminante); `medicion_diaria` y `fact_medicion_diaria` (fecha, estación, contaminante); `fact_medicion_horaria` (fecha, hora, estación); `agg_anual` (estación, contaminante, período); `guia_oms` (contaminante, promedio, nivel); `calidad_resumen` (contaminante, categoría); `oms_2021` (contaminante, promedio). |
| `entre` | `n_horas_validas` 0-24; `hora` 1-24; `valor` 0-1000; `valor_masa` 0-2000; `completitud` y todos los `pct_*` de `agg_anual` entre 0 y 1; `proporcion` entre 0 y 1. |

Último build: 11 modelos, 4 seeds, 87 tests: PASS 101, WARN 1 (`silver_valores_descartados`, esperado).
