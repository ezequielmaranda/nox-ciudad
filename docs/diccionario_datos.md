# Diccionario de datos

> Archivo generado por `python -m src.etl` a partir de las descripciones de los `.yml` de dbt.
> No editar a mano: cambiar la descripción en `dbt/models/` y volver a correr el ETL.

Tablas finales que se exportan a `data/final/` (CSV) y se cargan en Power BI.

| Tabla | Schema | Filas | Descripción |
|---|---|---|---|
| [`dim_estacion`](#dim_estacion) | modelo | 3 | Una fila por estación de monitoreo de la APrA. |
| [`dim_contaminante`](#dim_contaminante) | modelo | 3 | Una fila por contaminante, con unidades y factor de conversión a masa. |
| [`dim_calendario`](#dim_calendario) | modelo | 1.004 | Un registro por día del período (2024-01-01 a 2026-09-30), haya o no datos. |
| [`dim_periodo`](#dim_periodo) | modelo | 4 | Períodos de los indicadores anuales: un año calendario por fila (el último, parcial) más 'movil_12m', los últimos 12 meses con datos (comparable con un año completo). |
| [`ref_oms`](#ref_oms) | modelo | 5 | Guías OMS 2021 en formato ancho (una fila por contaminante × promedio). Se usa vía JOIN. |
| [`ref_oms_niveles`](#ref_oms_niveles) | modelo | 19 | Guías OMS en formato largo (UNPIVOT de ref_oms), una fila por nivel. Para líneas de referencia. |
| [`fact_medicion_diaria`](#fact_medicion_diaria) | modelo | 9.036 | Tabla de hechos en formato largo. Grano: fecha × estación × contaminante, con el promedio de 24 h. Grilla completa: incluye los días sin dato, marcados con tiene_dato = falso y el motivo en motivo_sin_dato. |
| [`fact_medicion_horaria`](#fact_medicion_horaria) | modelo | 70.704 | Valores horarios de NO2 del período de estudio (el único contaminante publicado como promedio de cada hora). Grano: fecha × hora × estación. Comparte dimensiones con la fact diaria; sirve para el perfil horario por tipo de día. |
| [`agg_cumplimiento_diario`](#agg_cumplimiento_diario) | indicadores | 7.615 | Cumplimiento diario de la guía OMS de 24 h. Grano: fecha × estación × contaminante, solo días con dato válido y contaminantes con guía de 24 h (NO2, PM10, CO). |
| [`agg_anual`](#agg_anual) | indicadores | 36 | Indicadores anuales por estación × contaminante × período (2024, 2025, 2026 parcial y últimos 12 meses), con la regla del 75% aplicada. |
| [`agg_cumplimiento_niveles`](#agg_cumplimiento_niveles) | indicadores | 120 | Matriz de escalones: % de días que cumplen la guía OMS de 24 h y cada objetivo intermedio, por estación × contaminante × período × nivel. Acumulativo (quien cumple la guía cumple todos los IT). |
| [`agg_rachas`](#agg_rachas) | indicadores | 263 | Rachas de días seguidos sobre la guía de 24 h (gaps and islands sobre los días con dato). Un día con dato que cumple la guía corta la racha; los huecos sin dato de hasta 7 días no la cortan ni la alargan (se informan en dias_sin_dato) y uno más largo sí la corta. |
| [`agg_contexto_anual`](#agg_contexto_anual) | indicadores | 96 | Serie larga de contexto (2010-2025): promedio anual de NO2 y PM10 por estación y año, con la misma regla del 75% de días con dato. Ubica el período de estudio en la historia de la red. |
| [`agg_completitud_mensual`](#agg_completitud_mensual) | calidad | 297 | Completitud del promedio de 24 h por estación × contaminante × mes (heatmap de calidad). |
| [`calidad_resumen`](#calidad_resumen) | calidad | 17 | Cantidad de valores horarios del período de estudio por contaminante y categoría de calidad. |
| [`calidad_violaciones`](#calidad_violaciones) | calidad | 239 | Una fila por cada valor horario del período de estudio que viola una regla de validación (un valor puede violar varias). Todos quedan fuera del análisis. |
| [`calidad_outliers`](#calidad_outliers) | calidad | 31 | Valores diarios atípicos (Q3 + 3·IQR) con contexto para la revisión manual. No se borran. |

## dim_estacion

Una fila por estación de monitoreo de la APrA.

| Columna | Tipo | Descripción |
|---|---|---|
| `id_estacion` | VARCHAR | Clave de la estación ('centenario', 'cordoba', 'la_boca'). |
| `codigo_fuente` | VARCHAR | Nombre de la estación como figura en la fuente ('LA BOCA'). |
| `nombre` | VARCHAR | Nombre legible para mostrar. |
| `direccion` | VARCHAR | Ubicación de la cabina según la APrA. |
| `entorno` | VARCHAR | Tipo de zona según la APrA (residencial-comercial, mixta). |
| `flujo_vehicular` | VARCHAR | Flujo vehicular de la zona según la APrA (alto, medio, medio-bajo). |
| `fuentes_fijas` | VARCHAR | Incidencia de fuentes fijas (industrias, puerto) según la APrA. |
| `inicio_operacion` | INTEGER | Año de inicio de actividad según BA Data (estaciones-ambientales.csv). |
| `latitud` | DOUBLE | Latitud de la estación (BA Data, estaciones-ambientales.csv). |
| `longitud` | DOUBLE | Longitud de la estación (BA Data, estaciones-ambientales.csv). |
| `descripcion` | VARCHAR | Para qué zona es representativa la estación. |
| `orden` | BIGINT | Orden alfabético para gráficos. |

## dim_contaminante

Una fila por contaminante, con unidades y factor de conversión a masa.

| Columna | Tipo | Descripción |
|---|---|---|
| `id_contaminante` | VARCHAR | Clave del contaminante ('no2', 'pm10', 'co'). |
| `codigo_fuente` | VARCHAR | Nombre como figura en la fuente ('NO2', 'PM10'). |
| `nombre` | VARCHAR | Nombre completo. |
| `unidad_medicion` | VARCHAR | Unidad en que se mide y publica (ppb, ppm o µg/m³). |
| `unidad_masa` | VARCHAR | Unidad de la guía OMS (µg/m³ o mg/m³). |
| `peso_molecular` | DOUBLE | Peso molecular en g/mol (vacío para PM10). |
| `factor_masa` | DOUBLE | Multiplicador de unidad_medicion a unidad_masa: peso_molecular / 24,45 (25 °C, 1 atm). |
| `promedio_fuente` | VARCHAR | Cómo publica la red el contaminante: 'horario' (NO2), 'movil_8h' (CO) o 'movil_24h' (PM10). |
| `horas_promedio_fuente` | INTEGER | Horas que abarca cada valor publicado (1, 8 o 24). |
| `maximo_plausible` | DOUBLE | Máximo plausible para un valor horario en la Ciudad (regla fuera_de_rango). |
| `tiene_guia_24h` | BOOLEAN | Verdadero si la OMS tiene guía de 24 h para el contaminante. |
| `tiene_guia_anual` | BOOLEAN | Verdadero si la OMS tiene guía anual para el contaminante. |
| `orden` | INTEGER | Orden para gráficos (NO2 primero). |
| `descripcion` | VARCHAR | Qué es, de dónde sale y por qué importa. |

## dim_calendario

Un registro por día del período (2024-01-01 a 2026-09-30), haya o no datos.

| Columna | Tipo | Descripción |
|---|---|---|
| `fecha` | DATE | Fecha (clave). |
| `anio` | BIGINT | Año. |
| `mes` | BIGINT | Mes (1-12). |
| `nombre_mes` | VARCHAR | Nombre del mes en castellano. |
| `anio_mes` | DATE | Primer día del mes (para ejes y agrupaciones mensuales). |
| `estacion_del_anio` | VARCHAR | Estación del año (hemisferio sur, meteorológica). Verano = dic, ene y feb. |
| `orden_estacion_del_anio` | INTEGER | 1 = verano … 4 = primavera (para ordenar en Power BI). |
| `dia_semana` | BIGINT | Día de la semana ISO (1 = lunes … 7 = domingo). |
| `nombre_dia` | VARCHAR | Nombre del día en castellano. |
| `tipo_dia` | VARCHAR | Código del tipo de día. Un feriado tiene prioridad sobre sábado o domingo. |
| `tipo_dia_etiqueta` | VARCHAR | Etiqueta legible del tipo de día (Hábil, Sábado, Domingo, Feriado). |
| `orden_tipo_dia` | INTEGER | 1 = hábil, 2 = sábado, 3 = domingo, 4 = feriado. |
| `es_feriado` | BOOLEAN | Verdadero si es feriado nacional o puente. |
| `nombre_feriado` | VARCHAR | Nombre del feriado (vacío si no es feriado; nulo estructural, no faltante). |
| `tipo_feriado` | VARCHAR | inamovible, trasladable o puente. |
| `es_fin_de_semana` | BOOLEAN | Verdadero si es sábado o domingo. |
| `es_anio_parcial` | BOOLEAN | Verdadero para los días del último año, que no está completo (2026). |
| `es_dia_evento` | BOOLEAN | Verdadero si hubo un paro de transporte ese día. |
| `evento` | VARCHAR | Descripción del paro (vacío en el 99% de los días; nulo estructural). |
| `grupo_evento` | VARCHAR | sin_colectivos o trenes_subte. |

## dim_periodo

Períodos de los indicadores anuales: un año calendario por fila (el último, parcial) más 'movil_12m', los últimos 12 meses con datos (comparable con un año completo).

| Columna | Tipo | Descripción |
|---|---|---|
| `id_periodo` | VARCHAR | '2024', '2025', '2026' o 'movil_12m'. |
| `etiqueta` | VARCHAR | Texto para mostrar. |
| `tipo_periodo` | VARCHAR | anio_completo, anio_parcial o movil_12m. |
| `anio` | BIGINT | Año (vacío para movil_12m). |
| `fecha_desde` | DATE | Primer día del período. |
| `fecha_hasta` | DATE | Último día del período. |
| `n_dias` | BIGINT | Cantidad de días del período. |
| `orden` | BIGINT | Orden para gráficos. |

## ref_oms

Guías OMS 2021 en formato ancho (una fila por contaminante × promedio). Se usa vía JOIN.

| Columna | Tipo | Descripción |
|---|---|---|
| `id_contaminante` | VARCHAR | Clave del contaminante. |
| `contaminante` | VARCHAR | Nombre corto. |
| `promedio` | VARCHAR | '24h' o 'anual'. |
| `guia_oms` | DOUBLE | Nivel guía (AQG). |
| `it1` | DOUBLE | Objetivo intermedio 1 (el menos exigente). |
| `it2` | DOUBLE | Objetivo intermedio 2. |
| `it3` | DOUBLE | Objetivo intermedio 3. |
| `it4` | DOUBLE | Objetivo intermedio 4. |
| `unidad` | VARCHAR | Unidad de la guía. |

## ref_oms_niveles

Guías OMS en formato largo (UNPIVOT de ref_oms), una fila por nivel. Para líneas de referencia.

| Columna | Tipo | Descripción |
|---|---|---|
| `id_contaminante` | VARCHAR | Clave del contaminante. |
| `contaminante` | VARCHAR | Nombre corto. |
| `promedio` | VARCHAR | '24h' o 'anual'. |
| `nivel` | VARCHAR | AQG, IT4, IT3, IT2 o IT1. |
| `nivel_etiqueta` | VARCHAR | Etiqueta legible del nivel. |
| `orden_exigencia` | INTEGER | 1 = más exigente (guía) … 5 = menos exigente (IT1). |
| `umbral` | DOUBLE | Valor del umbral. |
| `unidad` | VARCHAR | Unidad del umbral. |

## fact_medicion_diaria

Tabla de hechos en formato largo. Grano: fecha × estación × contaminante, con el promedio de 24 h. Grilla completa: incluye los días sin dato, marcados con tiene_dato = falso y el motivo en motivo_sin_dato.

| Columna | Tipo | Descripción |
|---|---|---|
| `fecha` | DATE | Fecha (clave hacia dim_calendario). |
| `id_estacion` | VARCHAR | Estación (clave hacia dim_estacion). |
| `id_contaminante` | VARCHAR | Contaminante (clave hacia dim_contaminante). |
| `n_horas_validas` | BIGINT | Horas con valor válido ese día (0 a 24). Para el NO2 hacen falta 18 para el promedio diario. |
| `tiene_fila` | BOOLEAN | Verdadero si la fuente tiene al menos una hora de ese día. |
| `tiene_dato` | BOOLEAN | Verdadero si hay promedio de 24 h válido. |
| `motivo_sin_dato` | VARCHAR | Por qué no hay dato (vacío si tiene_dato): 'sin_fila', 'sin_dato_fuente' o 'incompleto'. |
| `valor` | DOUBLE | Promedio de 24 h en la unidad original (solo si tiene_dato). |
| `unidad` | VARCHAR | Unidad original (ppb, ppm, µg/m³). |
| `valor_masa` | DOUBLE | Promedio de 24 h en la unidad de la guía OMS (µg/m³; mg/m³ para CO). Solo si tiene_dato. |
| `unidad_masa` | VARCHAR | Unidad de valor_masa. |
| `es_imputado` | BOOLEAN | Verdadero si el valor usa alguna hora '<límite' imputada como límite / 2. |
| `es_outlier` | BOOLEAN | Verdadero si valor > Q3 + 3·IQR de su estación × contaminante. Se marca, no se borra. |
| `umbral_outlier` | DOUBLE | Umbral Q3 + 3·IQR de esa estación × contaminante. |

## fact_medicion_horaria

Valores horarios de NO2 del período de estudio (el único contaminante publicado como promedio de cada hora). Grano: fecha × hora × estación. Comparte dimensiones con la fact diaria; sirve para el perfil horario por tipo de día.

| Columna | Tipo | Descripción |
|---|---|---|
| `fecha` | DATE | Fecha (clave hacia dim_calendario). |
| `hora` | INTEGER | Hora que termina (1 a 24; la 8 es de 07:00 a 08:00). |
| `id_estacion` | VARCHAR | Estación (clave hacia dim_estacion). |
| `id_contaminante` | VARCHAR | Siempre 'no2' (clave hacia dim_contaminante). |
| `es_valido` | BOOLEAN | Verdadero si el valor horario pasa las reglas de calidad. |
| `motivo_invalido` | VARCHAR | Motivo por el que la hora no se usa (vacío si es válida). |
| `valor` | DOUBLE | NO2 horario en ppb (solo si es válido). |
| `unidad` | VARCHAR | ppb. |
| `valor_masa` | DOUBLE | NO2 horario en µg/m³ (solo si es válido). |
| `unidad_masa` | VARCHAR | µg/m³. |

## agg_cumplimiento_diario

Cumplimiento diario de la guía OMS de 24 h. Grano: fecha × estación × contaminante, solo días con dato válido y contaminantes con guía de 24 h (NO2, PM10, CO).

| Columna | Tipo | Descripción |
|---|---|---|
| `fecha` | DATE | Fecha. |
| `id_estacion` | VARCHAR | Estación. |
| `id_contaminante` | VARCHAR | Contaminante. |
| `valor` | DOUBLE | Promedio de 24 h en la unidad de la guía (µg/m³; mg/m³ para CO). |
| `unidad` | VARCHAR | Unidad. |
| `guia_oms_24h` | DOUBLE | Guía OMS de 24 h del contaminante. |
| `supera_guia` | BOOLEAN | Verdadero si valor > guía. |
| `veces_guia` | DOUBLE | valor / guía (1 = justo en la guía). |
| `nivel_oms` | VARCHAR | Escalón OMS del día (AQG, IT4 … IT1, '> IT1'). |
| `orden_nivel_oms` | INTEGER | Orden del nivel para ordenar gráficos (1 = AQG … 6 = '> IT1'). |
| `es_outlier` | BOOLEAN | Marca de valor atípico heredada de la fact. |

## agg_anual

Indicadores anuales por estación × contaminante × período (2024, 2025, 2026 parcial y últimos 12 meses), con la regla del 75% aplicada.

| Columna | Tipo | Descripción |
|---|---|---|
| `id_estacion` | VARCHAR | Estación. |
| `id_contaminante` | VARCHAR | Contaminante (NO2, PM10, CO). |
| `id_periodo` | VARCHAR | Período (clave hacia dim_periodo). |
| `periodo` | VARCHAR | Etiqueta del período. |
| `tipo_periodo` | VARCHAR | anio_completo, anio_parcial o movil_12m. |
| `anio` | BIGINT | Año (vacío para movil_12m). |
| `n_dias_periodo` | BIGINT | Días del período. |
| `n_dias_con_dato` | BIGINT | Días con dato válido de 24 h. |
| `completitud` | DOUBLE | n_dias_con_dato / n_dias_periodo. |
| `es_valido` | BOOLEAN | Verdadero si completitud >= 75%. |
| `completitud_peor_trimestre` | DOUBLE | Completitud del trimestre con menos datos dentro del período. |
| `cumple_criterio_trimestral` | BOOLEAN | Verdadero si todos los trimestres tienen >= 75% de días con dato (advertencia, no excluye). |
| `unidad` | VARCHAR | Unidad de la guía. |
| `promedio_anual` | DOUBLE | Promedio de los valores diarios (vacío si no es válido). |
| `promedio_referencial` | DOUBLE | El mismo promedio calculado aunque no sea válido. Solo para transparencia. |
| `guia_anual` | DOUBLE | Guía anual OMS (vacía para CO, que no tiene). |
| `veces_guia_anual` | DOUBLE | promedio_anual / guia_anual. |
| `nivel_oms` | VARCHAR | Escalón OMS del promedio anual (AQG, IT4 … IT1, '> IT1'). |
| `orden_nivel_oms` | INTEGER | Orden del nivel para ordenar gráficos (1 = AQG … 6 = '> IT1'). |
| `proximo_nivel` | VARCHAR | Escalón al que se llega bajando ug_para_proximo_nivel. |
| `ug_para_proximo_nivel` | DOUBLE | Cuánto tendría que bajar el promedio anual para subir un escalón. |
| `p99_24h` | DOUBLE | Percentil 99 de los valores diarios (definición formal de la guía de 24 h). Vacío si no es válido. |
| `guia_24h` | DOUBLE | Guía OMS de 24 h. |
| `p99_veces_guia_24h` | DOUBLE | p99_24h / guia_24h. |
| `p99_supera_guia_24h` | BOOLEAN | Verdadero si el P99 supera la guía de 24 h (no se cumple la guía en sentido formal). |
| `maximo_diario` | DOUBLE | Máximo valor diario del período. |
| `n_dias_supera_24h` | BIGINT | Días por encima de la guía de 24 h. |
| `pct_dias_supera_24h` | DOUBLE | n_dias_supera_24h / n_dias_con_dato (0 a 1). |

## agg_cumplimiento_niveles

Matriz de escalones: % de días que cumplen la guía OMS de 24 h y cada objetivo intermedio, por estación × contaminante × período × nivel. Acumulativo (quien cumple la guía cumple todos los IT).

| Columna | Tipo | Descripción |
|---|---|---|
| `id_estacion` | VARCHAR | Estación. |
| `id_contaminante` | VARCHAR | Contaminante (NO2, PM10, CO). |
| `id_periodo` | VARCHAR | Período (clave hacia dim_periodo). |
| `nivel` | VARCHAR | AQG, IT4, IT3, IT2 o IT1. |
| `nivel_etiqueta` | VARCHAR | Etiqueta legible del nivel. |
| `orden_exigencia` | INTEGER | 1 = guía (más exigente) … 5 = IT1 (menos exigente). Para ordenar columnas. |
| `umbral` | DOUBLE | Umbral de 24 h del nivel. |
| `unidad` | VARCHAR | Unidad del umbral. |
| `n_dias_con_dato` | BIGINT | Días con dato válido en el período. |
| `n_dias_cumple` | BIGINT | Días cuyo promedio de 24 h no supera el umbral. |
| `completitud` | DOUBLE | Completitud del período (de agg_completitud_anual). |
| `es_valido` | BOOLEAN | Verdadero si el período tiene >= 75% de días con dato. |
| `cumple_criterio_trimestral` | BOOLEAN | Verdadero si todos los trimestres tienen >= 75% (advertencia, no excluye). |
| `pct_dias_cumple` | DOUBLE | n_dias_cumple / n_dias_con_dato (0 a 1). Vacío si el período no es válido. |
| `pct_referencial` | DOUBLE | El mismo cociente aunque el período no sea válido (solo para transparencia). |

## agg_rachas

Rachas de días seguidos sobre la guía de 24 h (gaps and islands sobre los días con dato). Un día con dato que cumple la guía corta la racha; los huecos sin dato de hasta 7 días no la cortan ni la alargan (se informan en dias_sin_dato) y uno más largo sí la corta.

| Columna | Tipo | Descripción |
|---|---|---|
| `id_estacion` | VARCHAR | Estación. |
| `id_contaminante` | VARCHAR | Contaminante. |
| `fecha_inicio` | DATE | Primer día de la racha. |
| `fecha_fin` | DATE | Último día de la racha. |
| `dias` | BIGINT | Días con dato sobre la guía en la racha. |
| `dias_calendario` | BIGINT | Días de calendario entre el primero y el último de la racha. |
| `dias_sin_dato` | BIGINT | Días sin dato dentro de la racha (dias_calendario − dias). |
| `es_racha_maxima` | BOOLEAN | Verdadero si es la racha más larga de su estación × contaminante. |

## agg_contexto_anual

Serie larga de contexto (2010-2025): promedio anual de NO2 y PM10 por estación y año, con la misma regla del 75% de días con dato. Ubica el período de estudio en la historia de la red.

| Columna | Tipo | Descripción |
|---|---|---|
| `anio` | BIGINT | Año calendario. |
| `id_estacion` | VARCHAR | Estación. |
| `id_contaminante` | VARCHAR | Contaminante con guía OMS anual (no2 o pm10). |
| `n_dias_anio` | BIGINT | Días del año (365 o 366). |
| `n_dias_con_dato` | BIGINT | Días con promedio de 24 h válido. |
| `completitud` | DOUBLE | n_dias_con_dato / n_dias_anio (0 a 1). |
| `es_valido` | BOOLEAN | Verdadero si el año tiene >= 75% de días con dato. |
| `unidad` | VARCHAR | Unidad de la guía anual (µg/m³). |
| `promedio_anual` | DOUBLE | Promedio anual (µg/m³). Vacío si el año no es válido. |
| `promedio_referencial` | DOUBLE | El mismo promedio aunque el año no sea válido (solo para transparencia). |
| `guia_anual` | DOUBLE | Guía anual de la OMS 2021. |
| `veces_guia_anual` | DOUBLE | promedio_anual / guia_anual. |
| `nivel_oms` | VARCHAR | Escalón OMS del promedio anual (AQG, IT4 … IT1, '> IT1'). Vacío si no es válido. |

## agg_completitud_mensual

Completitud del promedio de 24 h por estación × contaminante × mes (heatmap de calidad).

| Columna | Tipo | Descripción |
|---|---|---|
| `id_estacion` | VARCHAR | Estación. |
| `id_contaminante` | VARCHAR | Contaminante. |
| `anio` | BIGINT | Año. |
| `mes` | BIGINT | Mes (1-12). |
| `anio_mes` | DATE | Primer día del mes. |
| `n_dias_calendario` | BIGINT | Días del mes dentro del período. |
| `n_dias_con_fila` | BIGINT | Días con al menos una hora en la fuente. |
| `n_dias_con_dato` | BIGINT | Días con valor válido. |
| `n_dias_sin_fila` | BIGINT | Días sin ninguna hora en la fuente. |
| `n_dias_sin_dato_fuente` | BIGINT | Días con todas las horas en 's/d'. |
| `n_dias_incompletos` | BIGINT | Días con horas pero sin las suficientes para el promedio de 24 h (o descartadas por una regla). |
| `completitud` | DOUBLE | n_dias_con_dato / n_dias_calendario (0 a 1). |
| `cumple_umbral` | BOOLEAN | Verdadero si la completitud del mes es >= 75%. |

## calidad_resumen

Cantidad de valores horarios del período de estudio por contaminante y categoría de calidad.

| Columna | Tipo | Descripción |
|---|---|---|
| `id_contaminante` | VARCHAR | Contaminante. |
| `categoria` | VARCHAR | valido, valido_imputado o el motivo por el que se descartó. |
| `n_valores` | BIGINT | Cantidad de valores horarios (celdas del CSV). |
| `proporcion` | DOUBLE | Proporción dentro del contaminante (0 a 1). |

## calidad_violaciones

Una fila por cada valor horario del período de estudio que viola una regla de validación (un valor puede violar varias). Todos quedan fuera del análisis.

| Columna | Tipo | Descripción |
|---|---|---|
| `fecha` | DATE | Fecha. |
| `hora` | INTEGER | Hora que termina (1 a 24; puede venir fuera de rango si la regla es hora_invalida). |
| `id_estacion` | VARCHAR | Estación. |
| `id_contaminante` | VARCHAR | Contaminante. |
| `valor_crudo` | VARCHAR | Texto original de la celda. |
| `regla` | VARCHAR | Regla violada (hora_invalida, texto_invalido, fuera_de_rango, fila_en_cero, valor_trabado). |
| `motivo_invalido` | VARCHAR | Motivo principal por el que se descartó el valor. |

## calidad_outliers

Valores diarios atípicos (Q3 + 3·IQR) con contexto para la revisión manual. No se borran.

| Columna | Tipo | Descripción |
|---|---|---|
| `fecha` | DATE | Fecha. |
| `id_estacion` | VARCHAR | Estación. |
| `id_contaminante` | VARCHAR | Contaminante. |
| `valor` | DOUBLE | Promedio de 24 h en unidad original. |
| `unidad` | VARCHAR | Unidad original. |
| `umbral_outlier` | DOUBLE | Umbral Q3 + 3·IQR. |
| `mediana` | DOUBLE | Mediana de la serie (estación × contaminante). |
| `veces_mediana` | DOUBLE | valor / mediana. |
| `nombre_dia` | VARCHAR | Día de la semana. |
| `tipo_dia` | VARCHAR | Tipo de día. |
| `evento` | VARCHAR | Paro de transporte, si hubo. |
