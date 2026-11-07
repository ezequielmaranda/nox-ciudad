# Dashboard en Power BI: especificación

Guía para armar el dashboard a mano. El trabajo técnico ya está hecho: Power BI **comunica** los resultados del
ETL y el EDA, no recalcula reglas. Público: funcionarios, prensa y ciudadanía (no técnico).

## 0. Proyecto listo para abrir: `dashboard/AireOMS.pbip`

El repo trae un **proyecto de Power BI (.pbip)** con el modelo ya armado: las 15 tablas de `data/final` (más la
tabla `_Medidas`), las 24 relaciones de la sección 2, las 20 medidas DAX de la sección 3, el orden de las columnas de
texto, los formatos, las descripciones de cada tabla y columna (las mismas del diccionario de datos) y el tema de
colores de la sección 6. El informe trae las 3 páginas vacías: **los gráficos se arman a mano** con las secciones 4 y 5.

Lo genera `python -m src.generar_pbip` (o `make pbip`) a partir de `data/final` y de dbt. El modelo se validó con la
librería oficial de Microsoft para el formato TMDL y los JSON del informe con los esquemas oficiales, pero **no se
abrió en Power BI Desktop** (no corre en el entorno donde se generó): si al abrirlo aparece un error, Power BI dice en
qué archivo y línea.

**Cómo abrirlo:**
1. Power BI Desktop actualizado (versión de **agosto de 2026 o posterior**; el informe usa el tema base de esa versión).
2. Abrir `dashboard/AireOMS.pbip` (*Archivo → Abrir*). Abre el informe y el modelo, todavía sin datos.
3. *Transformar datos → Editar parámetros*: poner en **RutaDatos** la ruta completa a la carpeta `data/final` del
   repo, **con la barra final**. Por ejemplo `C:\Users\nombre\nox-ciudad\data\final\`.
4. *Inicio → Actualizar*. Carga los Parquet (sin problemas de separador decimal).
5. Armar los gráficos de cada página y guardar (*Archivo → Guardar*): se guarda en el mismo formato de proyecto, en
   archivos de texto que se pueden versionar en git. Para entregar un `.pbix`: *Archivo → Guardar como → .pbix*.

Si se vuelve a correr `make pbip`, el generador reescribe el modelo y las páginas vacías: **no correrlo después de
armar los gráficos** (se perderían). Los cambios posteriores del modelo se hacen directamente en Power BI.

Si se prefiere armar todo desde cero, las secciones siguientes describen el mismo modelo paso a paso.

## 1. Datos a importar

Desde `data/final/`. **Se recomienda Parquet** (*Obtener datos → Parquet*): conserva tipos de fecha, número y
booleano. Si se usan los CSV, en Power Query hay que cambiar los tipos **con configuración regional "Inglés
(Estados Unidos)"** (*Cambiar tipo → Usar configuración regional*), porque el separador decimal es el punto; con
la configuración en español, `0.229` se lee como 229.

| Tabla | Para qué | Obligatoria |
|---|---|---|
| `dim_estacion` | Segmentador de estación, mapa (coordenadas de BA Data) | sí |
| `dim_contaminante` | Segmentador de contaminante, unidades | sí |
| `dim_calendario` | Segmentadores de año, tipo de día y estación del año; eje de tiempo | sí |
| `dim_periodo` | Segmentador de período de los indicadores anuales | sí |
| `ref_oms` | Guías para las líneas de referencia y tarjetas | sí |
| `fact_medicion_diaria` | Completitud y días válidos | sí |
| `fact_medicion_horaria` | Perfil horario del NO2 por tipo de día | sí |
| `agg_cumplimiento_diario` | % de días sobre la guía, P99, series de 24 h | sí |
| `agg_anual` | Promedio anual, veces la guía, nivel OMS | sí |
| `agg_cumplimiento_niveles` | Matriz de escalones (% de días que cumplen cada nivel, por año) | sí |
| `agg_rachas` | Racha máxima | sí |
| `agg_completitud_mensual` | Heatmap de completitud | sí |
| `agg_contexto_anual` | Gráfico de contexto: NO2 anual 2010-2025 | recomendado |
| `calidad_resumen`, `calidad_violaciones`, `calidad_outliers` | Página de calidad | recomendado |
| `ref_oms_niveles` | Líneas de todos los niveles (IT1 a IT4) | opcional |

## 2. Modelo (vista de modelo)

Todas las relaciones son **uno a varios (1:*)**, con **dirección de filtro única** (de la dimensión a la tabla de
hechos o agregada). Ninguna bidireccional.

| Desde (1) | Hacia (*) | Columna |
|---|---|---|
| `dim_calendario` | `fact_medicion_diaria`, `fact_medicion_horaria`, `agg_cumplimiento_diario` | `fecha` |
| `dim_estacion` | `fact_medicion_diaria`, `fact_medicion_horaria`, `agg_cumplimiento_diario`, `agg_anual`, `agg_rachas`, `agg_contexto_anual`, `agg_completitud_mensual` | `id_estacion` |
| `dim_contaminante` | `fact_medicion_diaria`, `fact_medicion_horaria`, `agg_cumplimiento_diario`, `agg_anual`, `agg_rachas`, `agg_contexto_anual`, `agg_completitud_mensual`, `ref_oms`, `ref_oms_niveles`, `calidad_resumen` | `id_contaminante` |
| `dim_periodo` | `agg_anual`, `agg_cumplimiento_niveles` | `id_periodo` |
| `dim_estacion` / `dim_contaminante` | `agg_cumplimiento_niveles` | `id_estacion` / `id_contaminante` |

Notas:
- `agg_anual` **no** se relaciona con `dim_calendario`: sus períodos (años, 2026 parcial, últimos 12 meses) vienen
  de `dim_periodo`. En los visuales anuales usar el segmentador de **período**, no el de año.
- `agg_completitud_mensual` tiene su propio `anio_mes`: usarlo directamente en el heatmap.
- `agg_contexto_anual` tiene su propio `anio` (2010-2025, fuera del calendario del estudio): **no** se relaciona
  con `dim_calendario`.
- Ordenar columnas de texto por su columna de orden (*Herramientas de columna → Ordenar por columna*):
  `tipo_dia_etiqueta` por `orden_tipo_dia`, `estacion_del_anio` por `orden_estacion_del_anio`,
  `nombre_mes` por `mes`, `dim_periodo[etiqueta]` por `orden`, `dim_contaminante[nombre]` por `orden`,
  `nivel_oms` por `orden_nivel_oms` (en `agg_cumplimiento_diario` y en `agg_anual`).
- Ocultar las columnas de clave (`id_*`) en la vista de informe.

## 3. Medidas DAX

Crear una tabla vacía `_Medidas` y cargar ahí las medidas. Todas respetan los segmentadores.

```dax
-- Días con dato válido del promedio de 24 h (siempre mostrar el n junto a un porcentaje)
Días válidos =
CALCULATE ( COUNTROWS ( fact_medicion_diaria ), fact_medicion_diaria[tiene_dato] = TRUE () )

-- Completitud: días con dato / días del calendario (la fact es una grilla completa)
Completitud % =
DIVIDE ( [Días válidos], COUNTROWS ( fact_medicion_diaria ) )

-- % de días sobre la guía de 24 h (denominador: días CON DATO)
Días sobre guía =
CALCULATE ( COUNTROWS ( agg_cumplimiento_diario ), agg_cumplimiento_diario[supera_guia] = TRUE () )

% Días sobre guía =
DIVIDE ( [Días sobre guía], COUNTROWS ( agg_cumplimiento_diario ) )

-- Promedio de los valores diarios (unidad de la guía: µg/m³; mg/m³ para CO)
Promedio diario = AVERAGE ( agg_cumplimiento_diario[valor] )

-- Promedio anual (de agg_anual, ya con la regla del 75%: los períodos no válidos vienen vacíos).
-- Usar con UNA estación, UN contaminante y UN período por celda (tarjeta o matriz).
Promedio anual =
CALCULATE ( AVERAGE ( agg_anual[promedio_anual] ), agg_anual[es_valido] = TRUE () )

Veces sobre guía anual =
DIVIDE ( [Promedio anual], AVERAGE ( agg_anual[guia_anual] ) )

Nivel OMS anual = SELECTEDVALUE ( agg_anual[nivel_oms], "—" )

-- Percentil 99 de los valores diarios (definición formal de la guía de 24 h).
-- PERCENTILE.INC = mismo método que quantile_cont de DuckDB. Solo si la completitud llega al 75%.
Percentil 99 =
IF (
    [Completitud %] >= 0.75,
    PERCENTILE.INC ( agg_cumplimiento_diario[valor], 0.99 )
)

Guía OMS 24 h = CALCULATE ( MAX ( ref_oms[guia_oms] ), ref_oms[promedio] = "24h" )
Guía OMS anual = CALCULATE ( MAX ( ref_oms[guia_oms] ), ref_oms[promedio] = "anual" )

P99 veces la guía = DIVIDE ( [Percentil 99], [Guía OMS 24 h] )

-- Racha más larga de días con dato seguidos sobre la guía (calculada en SQL con gaps and islands;
-- los huecos de hasta 7 días sin dato no la cortan)
Racha máxima = MAX ( agg_rachas[dias] )

-- % de días que cumplen el objetivo intermedio IT2 diario o uno más exigente (NO2: 50 µg/m³).
% Días que cumplen IT2 =
DIVIDE (
    CALCULATE ( COUNTROWS ( agg_cumplimiento_diario ), agg_cumplimiento_diario[orden_nivel_oms] <= 4 ),
    COUNTROWS ( agg_cumplimiento_diario )
)

-- Variación contra el día hábil (para la matriz por tipo de día)
Variación vs. hábil =
VAR habil = CALCULATE ( [Promedio diario], dim_calendario[tipo_dia] = "habil" )
RETURN DIVIDE ( [Promedio diario] - habil, habil )

-- Estación con mayor % de días sobre la guía (tarjeta de la página Resumen)
Estación más comprometida =
VAR t = ADDCOLUMNS ( VALUES ( dim_estacion[nombre] ), "@pct", [% Días sobre guía] )
RETURN MAXX ( TOPN ( 1, t, [@pct], DESC ), dim_estacion[nombre] )

-- Texto para tarjetas: "95,0% de 900 días" (en FORMAT el patrón usa punto decimal; la salida sale
-- con coma si el informe está en español)
% Días sobre guía (texto) =
FORMAT ( [% Días sobre guía], "0.0%" ) & " de " & FORMAT ( COUNTROWS ( agg_cumplimiento_diario ), "#,0" ) & " días"

-- Completitud promedio del heatmap de la página de calidad
Completitud mensual = AVERAGE ( agg_completitud_mensual[completitud] )

-- Perfil horario del NO2 (eje: fact_medicion_horaria[hora]; leyenda: tipo de día o estación)
NO₂ horario promedio =
CALCULATE ( AVERAGE ( fact_medicion_horaria[valor_masa] ), fact_medicion_horaria[es_valido] = TRUE () )

-- Contexto 2010-2025 (solo años con 75% de días o más)
Promedio anual (contexto) = AVERAGE ( agg_contexto_anual[promedio_anual] )
```

Formato: `% Días sobre guía`, `Completitud %` y `Variación vs. hábil` como porcentaje con 1 decimal; promedios con
1 decimal; `Veces sobre guía anual` con 1 decimal y sufijo "×".

## 4. Páginas

### Página 1 · Resumen ("¿Cuán lejos estamos de la OMS?")

Mensaje: **ninguna estación cumple la guía de NO₂ de la OMS; Parque Centenario y Córdoba están en escalones
intermedios y La Boca no alcanza ni el primero.**

- **Fila de 4 tarjetas** (filtro de página: contaminante = NO2):
  1. `Nivel OMS anual` por estación, últimos 12 meses ("IT2 · IT1 · > IT1"), con el color del nivel.
  2. `% Días que cumplen IT2` por estación ("98,5% · 87,6% · 50,0%").
  3. `Veces sobre guía anual` de La Boca, últimos 12 meses ("4,6 veces la guía anual").
  4. `Racha máxima` ("254 días con dato seguidos sobre la guía").
- **Barras 100% apiladas "en qué escalón cae cada día"**: eje `dim_estacion[nombre]`, leyenda
  `agg_cumplimiento_diario[nivel_oms]` (ordenada por `orden_nivel_oms`), valores = recuento de filas, mostrado
  como % del total. Colores por nivel (sección 6). Responde "¿en qué escalón está cada estación?" (figura
  `reports/figures/06_niveles_oms_diarios.png` del EDA).
- **Una tarjeta por estación** (tarjeta de varias filas o pequeños múltiplos): nombre, `Nivel OMS anual`,
  `Promedio anual` (últimos 12 meses), `% Días sobre guía`.
- **Mapa** (visual Mapa o Azure Maps) con `latitud` / `longitud` de `dim_estacion` (coordenadas de BA Data, ya
  marcadas como latitud y longitud en el modelo); tamaño de la burbuja = `% Días sobre guía`. Si el mapa no aporta,
  reemplazarlo por las tarjetas por estación.
- **Cuadro de texto** con 3 conclusiones en lenguaje simple (ver README, sección Hallazgos).

### Página 2 · Detalle ("¿Cuándo y dónde es peor?")

- **Serie temporal**: gráfico de líneas, eje `dim_calendario[fecha]` (o `anio_mes` para promedios mensuales), valor
  `Promedio diario`, leyenda `dim_estacion[nombre]`. Línea de referencia: panel *Análisis → Línea constante* con el
  valor de `Guía OMS 24 h` (o una medida en línea). Rotular la línea "Guía OMS".
- **Matriz de escalones** (visual Matriz): filas `dim_estacion[nombre]` y `dim_periodo[etiqueta]`, columnas
  `agg_cumplimiento_niveles[nivel_etiqueta]` (ordenada por `orden_exigencia`), valores `pct_dias_cumple`
  (promedio; formato %) con formato condicional de fondo (escala de azules). Segmentadores de contaminante y
  período para que no quede gigante. Para la presentación alcanza con el NO2 y los años (figura
  `06b_matriz_niveles_no2.png`). Celdas vacías = período con menos de 75% de días.
- **Barras agrupadas**: `% Días sobre guía` por contaminante y estación (sin filtro de contaminante).
- **Barras horizontales**: `Promedio anual` por estación y período, con líneas constantes en la guía anual y los
  objetivos intermedios (tomar los valores de `ref_oms`).
- **Matriz**: filas `tipo_dia_etiqueta`, columnas `estacion_del_anio`, valores `% Días sobre guía` (formato
  condicional: escala de un solo tono, ver sección 6) y, en información sobre herramientas, `Días válidos`.
- **Barras**: `Variación vs. hábil` por tipo de día y estación (mensaje: "el domingo baja 17 a 26%, pero en La Boca
  el 90% de los domingos sigue sobre la guía").
- **Líneas, perfil horario**: eje `fact_medicion_horaria[hora]`, valor `NO₂ horario promedio`, leyenda
  `dim_calendario[tipo_dia_etiqueta]` (filtrar Hábil y Domingo) y segmentador de estación (figura
  `11_ritmo_semanal.png`). Mensaje: "en día hábil aparecen las horas pico; el domingo, no".
- **Líneas, contexto 2010-2025** (opcional): eje `agg_contexto_anual[anio]`, valor `Promedio anual (contexto)`, leyenda
  `dim_estacion[nombre]`, filtro contaminante = NO2 (figura `14_contexto_no2_anual.png`).

### Página 3 · Calidad de datos ("¿Cuánto podemos confiar?")

- **Heatmap de completitud**: matriz con filas `dim_estacion[nombre]` + `dim_contaminante[codigo_fuente]`,
  columnas `agg_completitud_mensual[anio_mes]`, valores `completitud` (promedio), formato condicional de color de
  fondo (escala de azules: claro = sin datos, oscuro = completo). Es el gráfico central de esta página.
- **Tabla "qué quedó afuera"**: `agg_anual` filtrado por `es_valido = falso` (estación, contaminante, período,
  completitud) + texto "menos de 75% de días con dato: no se calcula el promedio anual".
- **Tabla de valores descartados**: `calidad_violaciones` agrupada por regla y fecha (`#REF!` de mayo de 2024, la
  hora en cero del 17/09/2025, el CO de 23 ppm del 01/06/2026, etc.).
- **Barras**: `calidad_resumen` (valores horarios por categoría): 87,8% válidos, 11,9% sin dato en la fuente, 0,3%
  descartados por reglas.

## 5. Segmentadores

En una fila arriba de cada página, sincronizados entre páginas (*Ver → Sincronizar segmentaciones*):
**estación** (`dim_estacion[nombre]`), **contaminante** (`dim_contaminante[nombre]`), **año**
(`dim_calendario[anio]`), **tipo de día** (`dim_calendario[tipo_dia_etiqueta]`) y **estación del año**
(`dim_calendario[estacion_del_anio]`). En la página 2, para los visuales anuales, un segmentador de **período**
(`dim_periodo[etiqueta]`).

## 6. Colores y accesibilidad

No usar rojo/verde como única codificación (daltonismo). Cada estación tiene **un color fijo en todo el TP** (igual
que en las figuras del EDA); los niveles OMS van en una escala de **un solo tono** (más oscuro = más lejos de la
guía) y siempre con la etiqueta del nivel escrita.

| Uso | Color |
|---|---|
| Parque Centenario | `#2A78D6` (azul) |
| Córdoba | `#EB6834` (naranja) |
| La Boca | `#1BAF7A` (aqua) |
| Nivel AQG (cumple la guía) | `#C3C2B7` (gris) |
| Nivel IT4 | `#86B6EF` |
| Nivel IT3 | `#5598E7` |
| Nivel IT2 | `#2A78D6` |
| Nivel IT1 | `#1C5CAB` |
| Nivel > IT1 (no cumple ni el menos exigente) | `#0D366B` |
| Línea de la guía OMS | `#52514E`, guiones |
| Fondo / texto | `#FCFCFB` / `#0B0B0B` |

El tema está en [`powerbi_tema.json`](powerbi_tema.json) (*Vista → Temas → Buscar temas*). Los colores de
estación están validados para las formas más comunes de daltonismo. El aqua tiene contraste bajo sobre fondo
claro: mostrar siempre las etiquetas de datos o el nombre de la estación junto a la marca.

## 7. Control de los números

Antes de presentar, comparar el dashboard con las vistas SQL (`analisis.v_resumen_estacion`) o con el notebook:

| Indicador | La Boca | Córdoba | Parque Centenario |
|---|---|---|---|
| % de días con NO₂ sobre 25 µg/m³ (todo el período) | 95,0% (900 días) | 85,6% (864) | 54,9% (676) |
| % de días que cumplen el IT2 diario de NO₂ (50 µg/m³) | 50,0% | 87,6% | 98,5% |
| NO₂ promedio, últimos 12 meses | 45,9 µg/m³ (4,6×, > IT1) | 35,1 (3,5×, IT1) | 26,3 (2,6×, IT2) |
| % de días con PM10 sobre 45 µg/m³ | 4,1% | 3,2% | 2,4% |
| Racha máxima de NO₂ sobre la guía (días con dato) | 254 días | 111 días | 26 días |
| NO₂ del domingo vs. día hábil | −17% | −21% | −26% |
