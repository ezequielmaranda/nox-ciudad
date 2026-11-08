# Diccionario de datos

> Archivo generado por `python -m src.etl` a partir de las descripciones de los `.yml` de dbt.
> No editar a mano: cambiar la descripción en `dbt/models/` y volver a correr el ETL.

Capa gold de la base: las tablas que se exportan a `data/final/` (CSV) y alimentan el EDA y las tablas de Looker Studio.

| Tabla | Schema | Filas | Descripción |
|---|---|---|---|
| [`dim_estacion`](#dim_estacion) | gold | 3 | Una fila por estación de monitoreo de la APrA. |
| [`dim_contaminante`](#dim_contaminante) | gold | 3 | Una fila por contaminante, con unidades y factor de conversión a masa. |
| [`dim_calendario`](#dim_calendario) | gold | 1.004 | Un registro por día del período de estudio (2024-01-01 a 2026-09-30), haya o no datos. |
| [`guia_oms`](#guia_oms) | gold | 19 | Guías de la OMS 2021 en formato largo: una fila por contaminante × período de promedio (24h o anual) × nivel (guía AQG y objetivos intermedios IT4 a IT1). Sale de data/reference/oms_2021.csv. |
| [`fact_medicion_diaria`](#fact_medicion_diaria) | gold | 9.036 | Tabla de hechos en formato largo. Grano: fecha × estación × contaminante, con el promedio de 24 h comparado con la guía OMS de 24 h. Grilla completa del período de estudio: incluye los días sin dato, marcados con tiene_dato = falso y el motivo en motivo_sin_dato. |
| [`fact_medicion_horaria`](#fact_medicion_horaria) | gold | 70.704 | Valores horarios de NO2 del período de estudio (el único contaminante publicado como promedio de cada hora). Grano: fecha × hora × estación. Comparte dimensiones con la fact diaria; sirve para el perfil horario por tipo de día. |
| [`agg_anual`](#agg_anual) | gold | 162 | Indicadores anuales por estación × contaminante × período: años 2010 a 2026 (2026 parcial) y últimos 12 meses. Los del estudio (2024, 2025, 2026 y últimos 12 meses) tienen es_periodo_estudio = verdadero; 2010-2023 son contexto. Regla del 75%: si el período tiene menos de 75% de días con dato, los indicadores quedan vacíos (solo promedio_referencial). |
| [`calidad_resumen`](#calidad_resumen) | gold | 17 | Qué pasó con cada valor horario del período de estudio, por contaminante: válido o el motivo por el que se descartó, con en cuántos días y entre qué fechas aparece. |

## dim_estacion

Una fila por estación de monitoreo de la APrA.

| Columna | Tipo | Descripción |
|---|---|---|
| `id_estacion` | VARCHAR | Clave de la estación ('centenario', 'cordoba', 'la_boca'). |
| `nombre` | VARCHAR | Nombre legible para mostrar. |
| `entorno` | VARCHAR | Tipo de zona según la APrA (residencial-comercial, mixta). |
| `flujo_vehicular` | VARCHAR | Flujo vehicular de la zona según la APrA (alto, medio, medio-bajo). |
| `fuentes_fijas` | VARCHAR | Incidencia de fuentes fijas (industrias, puerto) según la APrA. |
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
| `factor_masa` | DOUBLE | Multiplicador de unidad_medicion a unidad_masa: peso_molecular / 24,45 (25 °C, 1 atm). |
| `orden` | INTEGER | Orden para gráficos (NO2 primero). |
| `descripcion` | VARCHAR | Qué es, de dónde sale y por qué importa. |

## dim_calendario

Un registro por día del período de estudio (2024-01-01 a 2026-09-30), haya o no datos.

| Columna | Tipo | Descripción |
|---|---|---|
| `fecha` | DATE | Fecha (clave). |
| `anio` | BIGINT | Año. |
| `mes` | BIGINT | Mes (1-12). |
| `anio_mes` | DATE | Primer día del mes (para ejes y agrupaciones mensuales). |
| `estacion_del_anio` | VARCHAR | Estación del año (hemisferio sur, meteorológica). Verano = dic, ene y feb. |
| `orden_estacion_del_anio` | INTEGER | 1 = verano … 4 = primavera (para ordenar en los gráficos). |
| `dia_semana` | BIGINT | Día de la semana ISO (1 = lunes … 7 = domingo). |
| `nombre_dia` | VARCHAR | Nombre del día en castellano. |
| `tipo_dia` | VARCHAR | Código del tipo de día. Un feriado tiene prioridad sobre sábado o domingo. |
| `tipo_dia_etiqueta` | VARCHAR | Etiqueta legible del tipo de día (Hábil, Sábado, Domingo, Feriado). |
| `orden_tipo_dia` | INTEGER | 1 = hábil, 2 = sábado, 3 = domingo, 4 = feriado. |

## guia_oms

Guías de la OMS 2021 en formato largo: una fila por contaminante × período de promedio (24h o anual) × nivel (guía AQG y objetivos intermedios IT4 a IT1). Sale de data/reference/oms_2021.csv.

| Columna | Tipo | Descripción |
|---|---|---|
| `id_contaminante` | VARCHAR | Contaminante (clave hacia dim_contaminante). |
| `promedio` | VARCHAR | Período de promedio de la guía ('24h' o 'anual'). |
| `nivel` | VARCHAR | AQG (guía), IT4, IT3, IT2 o IT1. |
| `orden_exigencia` | INTEGER | 1 = guía (más exigente) … 5 = IT1 (menos exigente). Para ordenar. |
| `umbral` | DOUBLE | Valor del nivel (µg/m³; mg/m³ para el CO). |
| `unidad` | VARCHAR | Unidad del umbral. |

## fact_medicion_diaria

Tabla de hechos en formato largo. Grano: fecha × estación × contaminante, con el promedio de 24 h comparado con la guía OMS de 24 h. Grilla completa del período de estudio: incluye los días sin dato, marcados con tiene_dato = falso y el motivo en motivo_sin_dato.

| Columna | Tipo | Descripción |
|---|---|---|
| `fecha` | DATE | Fecha (clave hacia dim_calendario). |
| `id_estacion` | VARCHAR | Estación (clave hacia dim_estacion). |
| `id_contaminante` | VARCHAR | Contaminante (clave hacia dim_contaminante). |
| `n_horas_validas` | BIGINT | Horas con valor válido ese día (0 a 24). Para el NO2 hacen falta 18 para el promedio diario. |
| `tiene_dato` | BOOLEAN | Verdadero si hay promedio de 24 h válido. |
| `motivo_sin_dato` | VARCHAR | Por qué no hay dato (vacío si tiene_dato): 'sin_fila', 'sin_dato_fuente' o 'incompleto'. |
| `valor` | DOUBLE | Promedio de 24 h en la unidad original, la de dim_contaminante.unidad_medicion (solo si tiene_dato). |
| `valor_masa` | DOUBLE | Promedio de 24 h en la unidad de la guía OMS, la de dim_contaminante.unidad_masa (µg/m³; mg/m³ para CO). Solo si tiene_dato. |
| `supera_guia` | BOOLEAN | Verdadero si valor_masa supera la guía de 24 h (vacío si no hay dato). |
| `nivel_oms` | VARCHAR | Escalón OMS de 24 h del día: AQG (cumple la guía), IT4 … IT1 o '> IT1'. Vacío si no hay dato. |
| `orden_nivel_oms` | INTEGER | 1 = cumple la guía … 6 = no cumple ni el IT1 (para ordenar). |
| `es_outlier` | BOOLEAN | Verdadero si valor > Q3 + 3·IQR de su estación × contaminante. Se marca, no se borra. |

## fact_medicion_horaria

Valores horarios de NO2 del período de estudio (el único contaminante publicado como promedio de cada hora). Grano: fecha × hora × estación. Comparte dimensiones con la fact diaria; sirve para el perfil horario por tipo de día.

| Columna | Tipo | Descripción |
|---|---|---|
| `fecha` | DATE | Fecha (clave hacia dim_calendario). |
| `hora` | INTEGER | Hora que termina (1 a 24; la 8 es de 07:00 a 08:00). |
| `id_estacion` | VARCHAR | Estación (clave hacia dim_estacion). |
| `id_contaminante` | VARCHAR | Siempre 'no2' (clave hacia dim_contaminante). |
| `es_valido` | BOOLEAN | Verdadero si el valor horario pasa las reglas de calidad. |
| `valor` | DOUBLE | NO2 horario en ppb (solo si es válido). |
| `valor_masa` | DOUBLE | NO2 horario en µg/m³ (solo si es válido). |

## agg_anual

Indicadores anuales por estación × contaminante × período: años 2010 a 2026 (2026 parcial) y últimos 12 meses. Los del estudio (2024, 2025, 2026 y últimos 12 meses) tienen es_periodo_estudio = verdadero; 2010-2023 son contexto. Regla del 75%: si el período tiene menos de 75% de días con dato, los indicadores quedan vacíos (solo promedio_referencial).

| Columna | Tipo | Descripción |
|---|---|---|
| `id_estacion` | VARCHAR | Estación. |
| `id_contaminante` | VARCHAR | Contaminante. |
| `id_periodo` | VARCHAR | Código del período: el año ('2024') o 'movil_12m'. |
| `periodo` | VARCHAR | Etiqueta legible del período. |
| `tipo_periodo` | VARCHAR | anio_completo, anio_parcial o movil_12m. |
| `anio` | BIGINT | Año (vacío para los últimos 12 meses). |
| `orden_periodo` | BIGINT | Para ordenar los períodos (los últimos 12 meses van al final). |
| `es_periodo_estudio` | BOOLEAN | Verdadero para 2024, 2025, 2026 y los últimos 12 meses; falso para el contexto 2010-2023. |
| `n_dias_periodo` | BIGINT | Días del período. |
| `n_dias_con_dato` | BIGINT | Días con promedio de 24 h válido. |
| `completitud` | DOUBLE | n_dias_con_dato / n_dias_periodo (0 a 1). |
| `es_valido` | BOOLEAN | Verdadero si el período tiene >= 75% de días con dato. |
| `promedio_anual` | DOUBLE | Promedio de los valores diarios. Vacío si el período no es válido. |
| `promedio_referencial` | DOUBLE | El mismo promedio aunque el período no sea válido (solo para transparencia). |
| `guia_anual` | DOUBLE | Guía anual de la OMS (vacía para el CO). |
| `veces_guia_anual` | DOUBLE | promedio_anual / guia_anual. |
| `nivel_oms` | VARCHAR | Escalón OMS del promedio anual (AQG, IT4 … IT1, '> IT1'). |
| `orden_nivel_oms` | INTEGER | 1 = cumple la guía … 6 = no cumple ni el IT1 (para ordenar). |
| `proximo_nivel` | VARCHAR | Próximo escalón a alcanzar. |
| `ug_para_proximo_nivel` | DOUBLE | Cuánto tendría que bajar el promedio para subir un escalón. |
| `p99_24h` | DOUBLE | Percentil 99 de los valores diarios (definición formal de la guía de 24 h). Vacío si no es válido. |
| `p99_veces_guia_24h` | DOUBLE | p99_24h / guía OMS de 24 h (más de 1 = no se cumple la guía en sentido formal). |
| `pct_dias_supera_24h` | DOUBLE | n_dias_supera_24h / n_dias_con_dato (0 a 1). |
| `pct_cumple_guia_24h` | DOUBLE | % de días que cumplen la guía de 24 h (0 a 1). Vacío si el período no es válido. |
| `pct_cumple_it4_24h` | DOUBLE | % de días que cumplen el IT4 de 24 h o algo más exigente. Vacío si el nivel no existe. |
| `pct_cumple_it3_24h` | DOUBLE | Ídem IT3. |
| `pct_cumple_it2_24h` | DOUBLE | Ídem IT2. |
| `pct_cumple_it1_24h` | DOUBLE | Ídem IT1. |
| `racha_maxima_dias` | BIGINT | Racha más larga de días con dato seguidos sobre la guía de 24 h en el período (huecos de hasta 7 días sin dato no la cortan). |
| `racha_desde` | DATE | Primer día de esa racha. |
| `racha_hasta` | DATE | Último día de esa racha. |

## calidad_resumen

Qué pasó con cada valor horario del período de estudio, por contaminante: válido o el motivo por el que se descartó, con en cuántos días y entre qué fechas aparece.

| Columna | Tipo | Descripción |
|---|---|---|
| `id_contaminante` | VARCHAR | Contaminante. |
| `categoria` | VARCHAR | valido o el motivo por el que se descartó (silver.medicion_horaria.motivo_invalido). |
| `n_valores` | BIGINT | Cantidad de valores horarios (celdas del CSV). |
| `proporcion` | DOUBLE | Proporción dentro del contaminante (0 a 1). |
| `n_dias` | BIGINT | Días en los que aparece la categoría. |
| `primera_fecha` | DATE | Primer día en que aparece. |
| `ultima_fecha` | DATE | Último día en que aparece. |
