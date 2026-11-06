# Calidad de datos

Qué problemas tiene el dato, cómo se detectan, qué se decidió y dónde está implementado. La regla general es
**no borrar filas**: cada problema queda **marcado** (columna booleana o motivo) y el análisis decide qué usar.
Todo está en SQL (`dbt/models/`) y se prueba en cada corrida (tests de dbt y de pytest).

## 1. Punto de partida

| | |
|---|---|
| **Fuente** | Informes mensuales públicos de la Agencia de Protección Ambiental (APrA) de la Ciudad, uno por mes, contaminante y estación ([buenosaires.gob.ar/calidad-del-aire](https://buenosaires.gob.ar/calidad-del-aire)) |
| **Formato original** | 281 PDF enlazados (CO; NO, NO2 y NOx; PM10) de las estaciones Parque Centenario, Córdoba y La Boca |
| **Extracción** | `src/extract.py` lee la tabla diaria de la página 1 de cada PDF y la escribe en `data/raw/aire_publico.csv` |
| **Crudo** | 83.010 valores × 7 columnas (`estacion, fecha, contaminante, estadistico, valor_crudo, unidad, archivo`), todo texto |
| **Grano** | estación × día × contaminante × estadístico (promedio 24 h; bloques 0-8, 8-16 y 16-24 h; máximo y mínimo horario) |
| **Período** | 2024-01-01 a 2026-09-30 (1.004 días; 2026 parcial) |
| **Origen aguas arriba** | La APrA mide en forma horaria y publica estos promedios. El TP **no tiene los datos horarios**: el ETL arranca desde los informes diarios. Los valores vienen redondeados (NO, NO2, NOx en ppb enteros; CO en ppm con un decimal; PM10 en µg/m³ enteros) |

Perfil del crudo (lo registra `python -m src.etl` en cada corrida): 0 duplicados por clave, 0 fechas inválidas,
0 nulos en columnas; 4.763 `s/d`, 448 valores `<límite`, 1 texto suelto (`Lunes`).

## 2. Problemas encontrados y cómo se resolvieron

### 2.1 En la extracción (PDF → CSV)

| Problema | Ejemplo | Solución | Dónde |
|---|---|---|---|
| Links de la web que dan 404 | `buenosaires.gob.ar/sites/default/files/...` redirige a una página histórica | Se baja la misma ruta desde `static.buenosaires.gob.ar` | `src/extract.py` |
| El lector de PDF devuelve el texto por columnas | La tabla sale desordenada | Se reconstruye la tabla con las coordenadas de cada celda | `src/extract.py` |
| Nombres de archivo inconsistentes | `la boca`, `la  boca`, `laboca`, `_0`, `centenaeio` | La estación se toma de la página y del encabezado, no del nombre | `src/extract.py`, test `test_extractor_reconoce_estacion` |
| Archivo de otra estación enlazado | La página de Centenario enlaza el NOx de **Córdoba** de julio 2025; la de Córdoba enlaza el PM10 de **La Boca** de febrero 2026 | Se **descartan** (2 PDF). Por eso faltan el NO2 de Centenario en julio 2025 y el PM10 de Córdoba en febrero 2026 | manifiesto → `calidad.calidad_archivos` |
| Encabezado equivocado | PM10 de La Boca de mayo 2025 dice "Córdoba" | Se conserva con aviso (los valores difieren del archivo de Córdoba) | `calidad.calidad_archivos` |
| Tabla incompleta | CO de Centenario de febrero 2024 termina el día 28 | Se acepta; el 29/02 queda como día sin fila | `calidad.calidad_archivos` |

### 2.2 En el staging (texto → valores tipados)

`dbt/models/01_staging/stg_aire.sql`

| Problema | Ejemplo | Solución |
|---|---|---|
| Coma decimal | `0,2` | `replace(',', '.')` y `CAST` a `double` |
| Sin dato | `s/d`, `DND` (4.763 valores, 5,7%) | `estado_valor = 'sin_dato'`, valor nulo |
| Bajo el límite de detección | `<4` (PM10), `<0,5` (NO), `<0,05` (CO): 448 valores | `estado_valor = 'bajo_limite_deteccion'`, valor **imputado = límite / 2**, `es_imputado = true`. Descartarlos sesgaría los promedios hacia arriba. Casi todos son mínimos horarios: en la fact solo hay 4 imputados |
| Texto en una celda numérica | `Lunes` en el PM10 8-16 de Córdoba del 04/07/2025 | `estado_valor = 'invalido'`, valor nulo |
| Categorías inconsistentes | `LA BOCA`, `NOx` | Identificadores en snake_case sin tildes (`la_boca`, `nox`); etiquetas legibles en las dimensiones |
| Tipos | Todo texto | `fecha` → `DATE` con `try_cast` (nula si no fuera fecha; 0 casos) |

### 2.3 Reglas de validación física

`dbt/models/01_staging/stg_aire_validado.sql`. Las tolerancias y los máximos físicos están en
`data/reference/contaminantes.csv` (no en el código). Recuento completo: `calidad.calidad_violaciones`.

| Regla | Qué detecta | Casos | Se descarta |
|---|---|---|---|
| `fuera_de_rango` | Valor negativo o por encima de un máximo físicamente posible | 0 | el valor |
| `valor_trabado` | Los 6 estadísticos del día son idénticos (máximo horario = mínimo = promedios) | 132 (22 días de NO, **todos un día 8**) | el contaminante ese día |
| `cero_sin_respaldo` | Promedio en 0 con máximo horario 0 o faltante | 7 (29/02/2024 y Centenario 01/08/2026) | el valor |
| `fuera_de_max_min` | Promedio fuera del rango horario del día (± tolerancia) | 3 (La Boca 29/02/2024: NOx 8-16 = 0 con mínimo 15) | el valor |
| `promedio_incoherente` | Promedio de 24 h ≠ promedio de los tres bloques de 8 h | 100 (NO y NOx) | el contaminante ese día |
| `no_mayor_que_nox` / `no2_mayor_que_nox` | NO > NOx o NO2 > NOx (imposible: NOx = NO + NO2) | 10 + 10 | el que supera al NOx |
| `nox_incoherente` | \|NOx − (NO + NO2)\| > 2 ppb | 196 días-estadístico | **NO y NOx, no el NO2** |

**El "día 8".** El 43% de las incoherencias NOx ≠ NO + NO2 cae el día 8 de cada mes, y los 22 días con NO
"trabado" son todos días 8. Es un patrón de la fuente: un analizador detenido o un error de carga en la planilla.
No se puede confirmar sin los datos horarios.

**Por qué la incoherencia de NOx no descarta el NO2.** En esos días el NO2 pasa sus propios controles (su promedio
de 24 h coincide con el de los bloques y está dentro del rango horario: 0 violaciones de NO2 en las reglas 4 y 5) y
la evidencia apunta a la columna de NO (NO trabado, NO > NOx). Descartar el NO2 haría perder días del contaminante
principal sin motivo. Cuando el NO2 supera al NOx (10 casos), sí se descarta.

Resultado: **93,1% de los valores válidos tal cual, 0,5% válidos imputados, 5,7% sin dato en la fuente y 0,7%
descartados por reglas** (`calidad.calidad_resumen`).

### 2.4 Días faltantes

La fact se arma como **grilla completa** (`dim_calendario` × estaciones × contaminantes × ventanas, con
`CROSS JOIN` + `LEFT JOIN`), así un día que la fuente no publicó aparece con `tiene_fila = false` en lugar de
desaparecer. Se distinguen tres situaciones (`motivo_sin_dato`):

- `sin_fila`: la fuente no publicó ese día (mes sin PDF o PDF descartado).
- `sin_dato_fuente`: hay fila, pero la planilla dice `s/d`.
- una regla de calidad: había número, pero se descartó.

**No faltan días-estación completos:** las tres estaciones tienen al menos un contaminante publicado los 1.004 días.
Los huecos son por contaminante:

| Estación | Contaminante | Días sin fila | Período |
|---|---|---|---|
| Parque Centenario | NO, NO2, NOx | 306 | marzo a noviembre 2024 (no publicado) y julio 2025 (link a otra estación) |
| Córdoba | CO | 92 | enero, abril y mayo 2024 |
| Córdoba | PM10 | 59 | agosto 2025 y febrero 2026 (link a otra estación) |
| Córdoba | NO, NO2, NOx | 31 | enero 2024 |
| La Boca | PM10 | 31 | enero 2025 (además, septiembre y octubre 2024 casi todo `s/d`) |
| Parque Centenario | CO | 32 | 29/02/2024 y marzo 2024 |

> **Diferencia con el enunciado.** El enunciado hablaba de 991 / 988 / 971 filas por estación en la tabla diaria
> "gold" del proyecto anterior. Esa tabla solo tenía fila cuando había algún valor válido, así que mezclaba
> "la fuente no publicó" con "la fuente publicó `s/d`". En la fuente cada estación tiene fila los 1.004 días.

## 3. Completitud y regla del 75%

Implementada en `dbt/models/04_calidad/agg_completitud_mensual.sql` y `agg_completitud_anual.sql`.

- **completitud** = días con dato válido del promedio de 24 h / días del período.
- **Indicadores anuales** (promedio anual, percentil 99): solo si el período tiene **≥ 75%** de días con dato
  (variable `umbral_completitud` de `dbt_project.yml`). Si no, `es_valido = false` y el valor no se publica
  (queda en `promedio_referencial` solo por transparencia).
- **Indicadores diarios** (% de días sobre la guía): usan todos los días con dato válido e informan siempre el `n`.
  El denominador son los **días con dato**, no todos los días: un día sin dato no es un día "limpio".
- **2026 es parcial** (enero a septiembre). Para compararlo con un año completo se calcula también el período
  **`movil_12m`** (octubre 2025 a septiembre 2026).

**Qué queda afuera:**

| Indicador | Completitud | Por qué |
|---|---|---|
| NO2 de Parque Centenario, 2024 | 18,9% | La APrA no publicó los informes de NOx de marzo a noviembre de 2024 |
| CO de Córdoba, 2024 | 66,1% | Faltan enero, abril y mayo |

El heatmap de completitud por estación × contaminante × mes está en `reports/figures/01_completitud_heatmap.png`
(notebook, sección 2) y es la página 3 del dashboard.

## 4. Valores atípicos (outliers)

**Criterio:** valor > Q3 + 3·IQR de su estación × contaminante × ventana (variable `factor_iqr`). Se usa 3·IQR
(y no 1,5) porque las concentraciones son asimétricas: con 1,5 se marcarían como atípicos muchos días de invierno
normales. **Se marcan (`es_outlier`), no se borran**: un pico real de contaminación es justo lo que la guía de 24 h
quiere detectar. Lista con contexto: `calidad.calidad_outliers` (185 valores, 85% en NO, NOx y PM10).

**Revisión manual de los casos extremos:**

| Fecha | Qué | Lectura | Decisión |
|---|---|---|---|
| 18 y 19/06/2025 | NO y NOx altos en **las tres estaciones** a la vez (NO hasta 14 veces la mediana) | Episodio atmosférico de invierno (típico de una inversión térmica), no una falla de un equipo | Se conserva |
| 18 y 19/11/2025 | PM10 de 104 a 134 µg/m³ en **las tres estaciones** (5 a 6 veces la mediana) | Episodio regional de partículas (humo o polvo); el valor de ~120 µg/m³ que mencionaba el enunciado | Se conserva |
| 11 y 12/07/2024 | PM10 y CO altos en dos o tres estaciones | Episodio de invierno compartido | Se conserva |
| 23/05/2026 (sábado), Córdoba | NO 8-16 = **424 ppb** (14 veces la mediana), NOx 492, NO2 70, CO normal (0,5 ppm) | Pico aislado de óxidos de nitrógeno sin CO: compatible con una fuente diésel muy cercana a la cabina (o con una falla). Pasa las reglas físicas | Se conserva marcado. Afecta a NO y NOx, que no se comparan con la OMS; el NO2 diario (58 µg/m³) no cambia ningún indicador |

Del NO2 diario hay solo 4 outliers (Córdoba): no modifican ningún indicador anual.

## 5. Unidades

| Contaminante | Unidad publicada | Unidad OMS | Conversión (25 °C, 1 atm) |
|---|---|---|---|
| NO2 | ppb | µg/m³ | × 46,01 / 24,45 = **1,88** |
| CO | ppm | mg/m³ | × 28,01 / 24,45 = **1,146** |
| NO / NOx | ppb | µg/m³ (contexto) | NO × 1,23; NOx se expresa como NO2 (× 1,88) |
| PM10 | µg/m³ | µg/m³ | sin conversión |

El factor sale del peso molecular (`data/reference/contaminantes.csv`) y del volumen molar (variable
`volumen_molar`); el test `factor_conversion_no2` verifica que dé 1,88 ± 0,01 y que la fact lo respete.

## 6. Controles automáticos

| Dónde | Qué | Cantidad |
|---|---|---|
| Tests de dbt (`dbt build`): **los datos** | Claves únicas, no nulos, valores aceptados, relaciones entre tablas (claves foráneas), rangos, grilla completa, el staging conserva todas las filas del crudo, NO/NO2 ≤ NOx, factor NO2, outliers marcados y no borrados, cobertura de la tabla OMS, regla del 75% y casos conocidos | 76 tests + 5 seeds; 1 aviso esperado (`stg_reglas_de_calidad`: describe las 851 violaciones de la fuente) |
| `tests/test_etl.py` (pytest): **el código y el pipeline** | Lo que dbt no puede probar: idempotencia (dos corridas dan archivos idénticos), que todas las consultas de `sql/99` corran y las funciones del extractor de PDF | 8 tests |
| `src/calidad.py` | Perfil del crudo antes de transformar y resumen de calidad al final de cada corrida | — |
