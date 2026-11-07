# Calidad de datos

Qué problemas tiene el dato, cómo se detectan, qué se decidió y dónde está implementado. La regla general es
**no borrar filas**: cada problema queda **marcado** (columna booleana o motivo) y el análisis decide qué usar.
Todo está en SQL (`dbt/models/`) y se prueba en cada corrida (tests de dbt y de pytest).

## 1. Punto de partida

| | |
|---|---|
| **Fuente** | Dataset "Calidad del aire" de BA Data, el portal de datos abiertos del GCBA, publicado por la Agencia de Protección Ambiental (APrA) ([data.buenosaires.gob.ar/dataset/calidad-aire](https://data.buenosaires.gob.ar/dataset/calidad-aire)) |
| **Archivo** | `calidad-aire.csv`, que baja `src/extract.py` a `data/raw/calidad-aire.csv` tal como se publica (8,5 MB, UTF-8 con BOM). El portal también publica archivos por año (`calidad_aire_2025.csv`, ...): se verificó que son un subconjunto idéntico de este |
| **Formato** | **Ancho**: una fila por fecha y hora (147.470 filas, de octubre de 2009 a octubre de 2026) y una columna por estación × contaminante (CO, NO2 y PM10 de Centenario, Córdoba, La Boca y Palermo), todo texto |
| **Qué publica cada columna** | **NO2**: promedio de la hora (ppb). **CO**: promedio móvil de las 8 horas anteriores (ppm). **PM10**: promedio móvil de las 24 horas anteriores (µg/m³). Según `contaminantes.csv` del mismo dataset |
| **Período del estudio** | 2024-01-01 a 2026-09-30 (1.004 días; 2026 parcial). La serie 2010-2025 se usa solo como contexto (los años 2010-2025 de `gold.agg_anual`) |
| **Fuera del alcance** | Palermo: la estación está desactivada desde el 30/06/2010 (`estaciones-ambientales.csv` de BA Data) y sus columnas vienen vacías. NO y NOx: la fuente horaria no los publica |

Perfil del crudo (sobre el CSV completo; en el TP lo cubren las consultas A1 a A4 de `sql/99` y los tests de dbt sobre
silver): 0 duplicados por fecha + hora, 284 filas con hora fuera de 1-24; en las 12 columnas de mediciones,
1.010.455 números, 469.968 celdas vacías (casi todas de Palermo), 278.459 `s/d`, 10.459 `<límite de detección`,
288 `#REF!` y 11 `x/d`.

## 2. Problemas encontrados y cómo se resolvieron

### 2.1 En la descarga

| Problema | Solución | Dónde |
|---|---|---|
| La página del dataset a veces responde 502 | Se baja el archivo directo de la CDN del portal (`cdn.buenosaires.gob.ar`), con reintentos y espera creciente | `src/extract.py` |
| El formato podría cambiar sin aviso | Antes de guardar, se verifica que estén las 11 columnas que usa el modelo; si falta alguna, no se pisa el crudo | `src/extract.py`, tests `test_extractor_*` |

### 2.2 De bronze a silver (texto ancho → valores tipados en formato largo)

Bronze (`dbt/models/bronze/calidad_aire.sql`) carga el CSV tal cual, todo como texto. La limpieza está en
`dbt/models/silver/medicion_horaria.sql`.

| Problema | Ejemplo | Solución |
|---|---|---|
| Formato ancho | Una columna por estación × contaminante | `UNPIVOT` (SQL estándar) a una fila por fecha × hora × estación × contaminante, con `INCLUDE NULLS` para no perder las celdas vacías (el test `silver_conserva_celdas_del_crudo` verifica filas del CSV × 9) |
| Fecha en formato SAS | `12FEB2011:00:00:00` | `strptime(fecha, '%d%b%Y:%H:%M:%S')` → `DATE` |
| Sin dato | `s/d`, `S/d` o celda vacía (11,9% de los valores del período) | `estado_valor = 'sin_dato'`, valor nulo |
| Bajo el límite de detección | `<0.05`, `< 0.05` (solo en el CO de 2010 a 2017; ninguno en el período) | `estado_valor = 'bajo_limite_deteccion'`, valor **imputado = límite / 2** (la marca queda en `estado_valor`). Descartarlos sesgaría los promedios hacia arriba |
| Texto en una celda numérica | `#REF!` (error de fórmula de la planilla de origen, 17 y 18/05/2024 en todas las columnas), `x/d` (tipeo de `s/d`, NO2 de La Boca el 01/12/2025) | `estado_valor = 'invalido'`, valor nulo |
| Categorías en el nombre de la columna | `NO2_LA_BOCA` | Se separan en `id_contaminante = 'no2'` e `id_estacion = 'la_boca'` (snake_case sin tildes); etiquetas legibles en las dimensiones |
| Variables redundantes | La unidad depende del contaminante; el promedio móvil de 24 h de la hora 24 repite información de las horas anteriores | La unidad pasa a `dim_contaminante`. De cada promedio móvil se usa solo el valor que cierra el bloque (sección 2.4) |
| Codificación y formato | BOM de UTF-8 al inicio del archivo; tildes y símbolos (`µg/m³`, `Córdoba`) | DuckDB lee UTF-8 con BOM; identificadores sin tildes ni espacios y etiquetas legibles aparte. Exportación con separador `,` y decimal `.` (el modelo de Power BI los importa con configuración regional inglés) |

### 2.3 Reglas de validación sobre cada valor horario

También en `dbt/models/silver/medicion_horaria.sql`: cada regla es una columna booleana y la primera que se cumple
queda en `motivo_invalido`. Los máximos plausibles están en
`data/reference/contaminantes.csv` y los umbrales, en las variables de `dbt_project.yml` (no en el código).
Recuento del período: `gold.calidad_resumen` (y la consulta A6 de `sql/99`).

| Regla | Qué detecta | Casos en el período | Se descarta |
|---|---|---|---|
| `hora_invalida` | Hora fuera de 1-24. El CSV trae algunas filas con hora 0 (que no coinciden ni con la hora 24 del día anterior ni con la 1 del mismo día) y filas vacías con "horas" 26 a 96 | 36 filas con hora 0, todas vacías | la fila |
| `texto_invalido` | Texto que no es número ni código conocido | 227 (`#REF!` del 17 y 18/05/2024; `x/d` del 01/12/2025) | el valor |
| `fuera_de_rango` | Negativo o mayor al máximo plausible (NO2 500 ppb, PM10 1.000 µg/m³, CO 15 ppm) | 3: NO2 de −2 ppb en Centenario (13/08/2025); CO de 23 ppm en La Boca (01/06/2026, 6 y 7 h), con las horas vecinas en 0,8 ppm y un máximo válido del período de 2,9 ppm | el valor |
| `fila_en_cero` | Todas las mediciones de una fecha y hora valen 0: una planilla vacía cargada con ceros, no aire limpio | 1 hora (17/09/2025, 12 h; 9 valores) | el valor |
| `valor_trabado` | NO2 idéntico durante 10 horas seguidas o más (`horas_valor_trabado`): un analizador que no varía ni 1 ppb en medio día. Solo para el NO2: CO y PM10 son promedios móviles y es normal que repitan valores | 0 en el período (sí aparece en la serie histórica) | el valor |

Resultado en el período: **87,8% de los valores horarios válidos, 11,9% sin dato en la fuente y 0,3% descartados
por reglas** (`gold.calidad_resumen`).

### 2.4 De horas a días

`dbt/models/silver/medicion_diaria.sql`. La guía OMS de 24 h se compara con el promedio de 00 a 24 h. Cada
contaminante se publica con un promedio distinto, así que el valor diario se arma distinto:

| Contaminante | Qué publica la fuente | Valor diario | Cuándo no hay valor |
|---|---|---|---|
| NO2 | Promedio horario | Promedio de las horas válidas | Con menos de **18 de 24 horas** (`horas_minimas_dia`): 75%, el criterio de la Directiva 2008/50/CE para pasar de horas a día |
| PM10 | Promedio móvil de 24 h | El valor de la hora 24, que ya es el promedio de 00 a 24 | Si falta o no es válida la hora 24 |
| CO | Promedio móvil de 8 h | Promedio de los valores de las horas 8, 16 y 24 (los tres bloques de 8 h del día) | Si falta alguno de los tres |

Los días de NO2 por cantidad de horas válidas (período completo, 1.004 días por estación):

| Estación | 24 horas | 18 a 23 | 1 a 17 (no alcanza) | ninguna |
|---|---|---|---|---|
| Córdoba | 801 | 63 | 55 | 85 |
| La Boca | 814 | 86 | 61 | 43 |
| Parque Centenario | 605 | 71 | 26 | 302 (la estación no midió de marzo a noviembre de 2024) |

**Huecos de exportación.** La fuente trae pares de días cortados al mediodía (un día con las horas 1 a 12 y el
siguiente con las 13 a 24: por ejemplo, 12 y 13/05/2025 o 02 y 03/07/2025) y 6 días sin ninguna fila (20 y
21/09/2024, 19/10/2024 y 31/03 a 02/04/2025). Esos días sí tienen dato en los informes mensuales en PDF de la APrA:
son huecos de la exportación al portal, no de la medición. El TP no los rellena (no se mezclan fuentes) y los
trata como días sin dato; el único lugar donde se tienen en cuenta es en las rachas (sección 3.3).

### 2.5 Validación externa: contra los informes mensuales en PDF

La versión anterior del TP extraía los promedios diarios de los informes mensuales en PDF que la APrA publica en la
página de cada estación (está en la historia de git). Se compararon con el valor diario armado desde el CSV horario,
de 2024-01-01 a 2026-09-30:

| Contaminante | Pares estación-día | Iguales | Con diferencia de ±1 unidad o menos (redondeo) |
|---|---|---|---|
| NO2 (ppb) | 2.411 | 93,8% | 99,5% |
| CO (ppm, ±0,1) | 2.562 | 97,0% | 99,6% |
| PM10 (µg/m³) | 2.549 | 98,2% | 98,8% |

Las dos publicaciones de la APrA coinciden: el armado del valor diario es correcto y el cambio de fuente no mueve
los resultados (los escalones OMS de cada estación son los mismos). La comparación también mostró qué publica una
fuente y no la otra:
- **El CSV tiene datos que los PDF no:** NO2 de Centenario de julio de 2025 y PM10 de Córdoba de febrero de 2026
  (en la web, esos dos links apuntaban al PDF de otra estación) y PM10 de Córdoba de agosto de 2025 (PDF no
  publicado).
- **Los PDF tienen días que el CSV no:** los huecos de exportación de la sección 2.4.
- **Como la serie horaria tiene más resolución**, permite controles que los PDF no permitían (hora por hora) y el
  perfil horario del NO2 (`fact_medicion_horaria`). A cambio, se pierden el NO y el NOx, que la fuente horaria no
  publica.

## 3. Días faltantes, completitud y regla del 75%

### 3.1 Días faltantes

La fact se arma como **grilla completa** (`dim_calendario` × estaciones × contaminantes, con `CROSS JOIN` +
`LEFT JOIN`), así un día sin dato aparece con `tiene_dato = false` en lugar de desaparecer. Se distinguen tres
situaciones (`motivo_sin_dato`):

- `sin_fila`: la fuente no tiene ninguna hora de ese día (6 días).
- `sin_dato_fuente`: la fuente tiene el día, pero todas las horas dicen `s/d`.
- `incompleto`: hay horas, pero no alcanzan para el valor diario (sección 2.4).

| Estación | Contaminante | Días sin dato | sin fila | s/d | incompletos | Hueco principal |
|---|---|---|---|---|---|---|
| Parque Centenario | NO2 | 328 | 6 | 294 | 28 | marzo a noviembre de 2024 |
| La Boca | PM10 | 192 | 6 | 138 | 48 | septiembre y octubre de 2024, enero de 2025 |
| Córdoba | CO | 187 | 6 | 137 | 44 | enero, abril y mayo de 2024 |
| Córdoba | NO2 | 140 | 6 | 79 | 55 | enero y febrero de 2024 |
| La Boca | CO | 133 | 6 | 52 | 75 | repartido |
| Parque Centenario | CO | 130 | 6 | 68 | 56 | marzo de 2024 |
| Córdoba | PM10 | 116 | 6 | 61 | 49 | febrero y abril de 2025 |
| La Boca | NO2 | 104 | 6 | 37 | 61 | septiembre de 2026 |
| Parque Centenario | PM10 | 91 | 6 | 44 | 41 | repartido |

### 3.2 Completitud y regla del 75%

Implementada en `dbt/models/gold/agg_anual.sql` (una fila por período). La completitud mensual del heatmap se
calcula en el momento sobre la fact (`tiene_dato`), que tiene todos los días.

- **completitud** = días con promedio de 24 h válido / días del período.
- **Indicadores anuales** (promedio anual, percentil 99, matriz de escalones por año): solo si el período tiene
  **≥ 75%** de días con dato (variable `umbral_completitud` de `dbt_project.yml`). Si no, `es_valido = false` y el
  valor no se publica (el promedio queda en `promedio_referencial` solo por transparencia).
- **Indicadores diarios de todo el período** (% de días sobre la guía): usan todos los días con dato válido e
  informan siempre el `n`. El denominador son los **días con dato**, no todos los días.
- **2026 es parcial** (enero a septiembre). Para compararlo con un año completo se calcula también el período
  **`movil_12m`** (octubre 2025 a septiembre 2026).

#### ¿De dónde sale el 75%?

El 75% es una convención de las normas de calidad del aire, pero **no hay un único criterio** y **la OMS no fija
ninguno** (sus guías definen niveles y tiempos de promedio, no reglas de completitud):

| Referencia | De horas a día | Promedio anual |
|---|---|---|
| **Unión Europea**, Directiva 2008/50/CE, Anexo XI | 75%: al menos 18 valores horarios (y 45 minutos para un valor horario) | **90%** de los valores horarios (o, si no hay, de los de 24 h), sin contar las pérdidas por calibración o mantenimiento |
| **EPA de EE.UU.**, 40 CFR 50, Apéndice S (NO2) | 75% de las horas del día | **75%** de las horas del año; para la norma de 1 hora, además, 75% de los días en **cada trimestre** |
| **OMS 2021** | — | — |

Dos usos en el TP:

1. **De horas a día** (NO2): 18 de 24 horas, el criterio de la UE y de la EPA (sección 2.4). Para CO y PM10 la
   fuente ya publica promedios móviles: cuántas horas tuvo cada promedio lo resolvió la APrA y el TP no lo puede
   verificar (limitación declarada).
2. **Para los indicadores anuales**, el 75% al estilo EPA (con días en lugar de horas). Es más laxo que la UE (90%)
   y, solo, no mira cómo se reparten los datos en el año: eso se ve en el heatmap de completitud (figura 01) y en
   la verificación de sensibilidad de la sección 3.4.

### 3.3 Rachas y huecos

Una racha es una sucesión de días con dato sobre la guía de 24 h (la más larga de cada período está en
`gold.agg_anual`: `racha_maxima_dias`, `racha_desde`, `racha_hasta`). Un día **con dato** que
cumple la guía la corta. Los huecos sin dato de hasta 7 días seguidos (`dias_hueco_maximo_racha`) no la cortan ni la
alargan (los días sin dato son la diferencia entre los días de calendario de la racha y `racha_maxima_dias`). Un hueco más largo sí la corta. Motivo: los huecos cortos son casi siempre
de la exportación (sección 2.4); cortar la racha en cada uno la subestimaría. Ejemplo: La Boca, 14/02 a 28/11/2024,
**254 días con dato, todos sobre la guía**, en 289 días de calendario (35 sin dato, en huecos de 1 a 5 días).

### 3.4 Sensibilidad: ¿cambian las conclusiones con un criterio más estricto?

Verificación hecha una vez, al elegir el criterio (el modelo aplica solo el 75% anual). Validez del promedio anual
de NO2 según cada criterio:

| Estación | Período | Completitud | 75% anual (el usado) | 75% en cada trimestre (EPA) | 90% anual (UE) |
|---|---|---|---|---|---|
| Parque Centenario | 2024 | 18,9% | no | no | no |
| | 2025 | 93,7% | sí | sí | sí |
| | últimos 12 meses | 95,1% | sí | sí | sí |
| Córdoba | 2024 | 79,5% | sí | no (ene-mar: 44%) | no |
| | 2025 | 85,5% | sí | no (ene-mar: 70%) | no |
| | últimos 12 meses | 95,1% | sí | sí | sí |
| La Boca | 2024 | 89,9% | sí | sí | no |
| | 2025 | 93,4% | sí | sí | sí |
| | últimos 12 meses | 86,9% | sí | no (jul-sep 2026: 67%) | no |

**Las conclusiones no cambian:** con el criterio más estricto, cada estación tiene al menos un período válido y su
escalón es el mismo en todos los períodos: Parque Centenario **IT2** (2025 y últimos 12 meses), Córdoba **IT1**
(últimos 12 meses) y La Boca **por encima del IT1** (2025). El PM10 es más sensible: con el criterio más estricto
**La Boca no tiene ningún período válido** (le faltan meses casi enteros de PM10) y Córdoba pierde 2025. Donde hay
períodos que pasan (Parque Centenario siempre; Córdoba 2024, 2026 y últimos 12 meses), el resultado es el mismo:
IT3 anual y guía diaria cumplida el 95% a 99% de los días.

Cambiar el umbral es una línea: `umbral_completitud` en `dbt/dbt_project.yml` (por ejemplo, 0.90 para el criterio
de la UE) y volver a correr `python -m src.etl`.

**Qué queda afuera con el 75% anual:**

| Indicador | Completitud | Por qué |
|---|---|---|
| NO2 de Parque Centenario, 2024 | 18,9% | La estación no tiene NO2 de marzo a noviembre de 2024 (ni en el CSV ni en los PDF) |
| CO de Córdoba, 2024 | 61,5% | Faltan enero, abril y mayo |

El heatmap de completitud por estación × contaminante × mes está en `reports/figures/01_completitud_heatmap.png`
(notebook, sección 2) y es la página 3 del dashboard.

**Fuentes:** Directiva 2008/50/CE del Parlamento Europeo y del Consejo, Anexo XI
([EUR-Lex](https://eur-lex.europa.eu/legal-content/EN/ALL/?uri=CELEX:32008L0050)); 40 CFR Part 50, Appendix S,
sección 3 ([govinfo, edición 2022](https://www.govinfo.gov/content/pkg/CFR-2022-title40-vol2/pdf/CFR-2022-title40-vol2-part50-appS.pdf));
WHO global air quality guidelines (2021).

## 4. Valores atípicos (outliers)

**Criterio:** promedio diario > Q3 + 3·IQR de su estación × contaminante (variable `factor_iqr`). Se usa 3·IQR (y no
1,5) porque las concentraciones son asimétricas: con 1,5 se marcarían como atípicos muchos días de invierno normales.
**Se marcan (`es_outlier`), no se borran**: un pico real de contaminación es justo lo que la guía de 24 h quiere
detectar. Lista: `gold.fact_medicion_diaria` filtrada por `es_outlier` (31 valores: 16 de CO, 11 de PM10 y 4 de NO2; consulta
C5 de `sql/99` y sección 2 del notebook).

**Revisión manual de los casos extremos:**

| Fecha | Qué | Lectura | Decisión |
|---|---|---|---|
| 11 a 14/07/2024 | PM10 y CO altos en dos o tres estaciones (CO de La Boca 4,5 a 4,9 veces su mediana; PM10 de Centenario 82 µg/m³) | Episodio de invierno compartido | Se conserva |
| 19/11/2025 | PM10 alto en **las tres estaciones** (Córdoba 99 µg/m³, 4,3 veces la mediana) | Episodio regional de partículas (humo o polvo) | Se conserva |
| 31/05/2026 | CO alto en dos estaciones | Episodio compartido | Se conserva |

Del NO2 diario hay solo 4 outliers: no modifican ningún indicador anual.

## 5. Unidades

| Contaminante | Unidad publicada | Unidad OMS | Conversión (25 °C, 1 atm) |
|---|---|---|---|
| NO2 | ppb | µg/m³ | × 46,01 / 24,45 = **1,88** |
| CO | ppm | mg/m³ | × 28,01 / 24,45 = **1,146** |
| PM10 | µg/m³ | µg/m³ | sin conversión |

El factor sale del peso molecular (`data/reference/contaminantes.csv`) y del volumen molar (variable
`volumen_molar`); el test `factor_conversion_no2` verifica que dé 1,88 ± 0,01 y que la fact lo respete.

## 6. Controles automáticos

| Dónde | Qué | Cantidad |
|---|---|---|
| Tests de dbt (`dbt build`): **los datos** | Claves únicas (también en silver horario: sin duplicados por fecha + hora), no nulos, valores aceptados, relaciones entre tablas (claves foráneas), rangos, grilla completa, silver conserva todas las celdas del crudo, el NO2 diario sale de 18 horas o más, el promedio diario coincide con las horas de la fact horaria, factor NO2, outliers marcados y no borrados, cobertura de la tabla OMS, regla del 75%, casos conocidos y cumplimiento acumulativo por escalón | 87 tests + 4 seeds; 1 aviso esperado (`silver_valores_descartados`: describe los 239 valores descartados del período) |
| `tests/test_etl.py` (pytest): **el código y el pipeline** | Lo que dbt no puede probar: idempotencia (dos corridas dan archivos idénticos), que las consultas de `sql/99` corran en una conexión de solo lectura y que el extractor reconozca el formato del CSV y detecte un cambio de formato | 4 tests |
