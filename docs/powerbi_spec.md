# Dashboard en Power BI: especificación

Guía para armar el dashboard a mano. El trabajo técnico ya está hecho: Power BI **comunica** los resultados del
ETL y el EDA, no recalcula reglas. Público: funcionarios, prensa y ciudadanía (no técnico).

## 0. Proyecto listo para abrir: `dashboard/AireOMS.pbip`

El repo trae un **proyecto de Power BI (.pbip)** con el modelo ya armado: 15 tablas de `data/final` (más la tabla
`_Medidas`), 24 relaciones, 20 medidas DAX, el orden de las columnas de texto, los formatos, las descripciones de cada
tabla y columna (las mismas del diccionario de datos) y el tema de colores de la sección 4. El informe trae las 3
páginas vacías: **los gráficos se arman a mano** con las secciones 2 y 3.

Lo genera `.venv\Scripts\python -m src.generar_pbip` después del ETL (necesita la base DuckDB y el manifest de dbt).
El modelo y las medidas están definidos en [`src/generar_pbip.py`](../src/generar_pbip.py): ese archivo es la
referencia, esta guía no los repite. **No se abrió en Power BI Desktop** (no corre en el entorno donde se generó): si
al abrirlo aparece un error, Power BI dice en qué archivo y línea.

**Cómo abrirlo:**
1. Power BI Desktop actualizado (versión de **agosto de 2026 o posterior**; el informe usa el tema base de esa versión).
2. Abrir `dashboard/AireOMS.pbip` (*Archivo → Abrir*). Abre el informe y el modelo, todavía sin datos.
3. *Transformar datos → Editar parámetros*: poner en **RutaDatos** la ruta completa a la carpeta `data/final` del
   repo, **con la barra final**. Por ejemplo `C:\Users\nombre\nox-ciudad\data\final\`.
4. *Inicio → Actualizar*. Carga los CSV; el modelo ya les aplica los tipos con punto decimal.
5. Armar los gráficos de cada página y guardar (*Archivo → Guardar*): se guarda en el mismo formato de proyecto, en
   archivos de texto que se pueden versionar en git. Para entregar un `.pbix`: *Archivo → Guardar como → .pbix*.

Si se vuelve a correr el generador, reescribe el modelo y las páginas vacías: **no correrlo después de armar los
gráficos** (se perderían). Los cambios posteriores del modelo se hacen directamente en Power BI.

## 1. Qué trae el modelo

| Tabla | Para qué |
|---|---|
| `dim_estacion` | Segmentador de estación, mapa (coordenadas de BA Data, marcadas como latitud y longitud) |
| `dim_contaminante` | Segmentador de contaminante, unidades |
| `dim_calendario` | Segmentadores de año, tipo de día y estación del año; eje de tiempo |
| `dim_periodo` | Segmentador de período de los indicadores anuales |
| `ref_oms`, `ref_oms_niveles` | Guías y objetivos intermedios para líneas de referencia y tarjetas |
| `fact_medicion_diaria` | Completitud y días válidos |
| `fact_medicion_horaria` | Perfil horario del NO2 por tipo de día |
| `agg_cumplimiento_diario` | % de días sobre la guía, P99, series de 24 h |
| `agg_anual` | Promedio anual, veces la guía, nivel OMS |
| `agg_cumplimiento_niveles` | Matriz de escalones (% de días que cumplen cada nivel, por año) |
| `agg_rachas` | Racha máxima |
| `agg_contexto_anual` | Contexto: NO2 y PM10 anual 2010-2025 |
| `agg_completitud_mensual` | Heatmap de completitud |
| `calidad_resumen` | Página de calidad |

Para tener en cuenta al armar los gráficos:
- `agg_anual` **no** se relaciona con `dim_calendario`: sus períodos (años, 2026 parcial, últimos 12 meses) vienen
  de `dim_periodo`. En los visuales anuales usar el segmentador de **período**, no el de año.
- `agg_completitud_mensual` tiene su propio `anio_mes`: usarlo directamente en el heatmap.
- `agg_contexto_anual` tiene su propio `anio` (2010-2025, fuera del calendario del estudio): **no** se relaciona
  con `dim_calendario`.
- `Promedio anual` va con **una** estación, **un** contaminante y **un** período por celda (tarjeta o matriz).
- Las medidas están en la tabla `_Medidas`, cada una con su descripción. `Veces sobre guía anual` queda linda con el
  sufijo "×".

## 2. Páginas

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
  como % del total. Colores por nivel (sección 4). Responde "¿en qué escalón está cada estación?" (figura
  `reports/figures/06_niveles_oms_diarios.png` del EDA).
- **Una tarjeta por estación** (tarjeta de varias filas o pequeños múltiplos): nombre, `Nivel OMS anual`,
  `Promedio anual` (últimos 12 meses), `% Días sobre guía`.
- **Mapa** (visual Mapa o Azure Maps) con `latitud` / `longitud` de `dim_estacion`; tamaño de la burbuja
  = `% Días sobre guía`. Si el mapa no aporta, reemplazarlo por las tarjetas por estación.
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
  condicional: escala de un solo tono, ver sección 4) y, en información sobre herramientas, `Días válidos`.
- **Barras**: `Variación vs. hábil` por tipo de día y estación (mensaje: "el domingo baja 17 a 26%, pero en La Boca
  el 90% de los domingos sigue sobre la guía").
- **Líneas, perfil horario**: eje `fact_medicion_horaria[hora]`, valor `NO₂ horario promedio`, leyenda
  `dim_calendario[tipo_dia_etiqueta]` (filtrar Hábil y Domingo) y segmentador de estación (figura
  `11_ritmo_semanal.png`). Mensaje: "en día hábil aparecen las horas pico; el domingo, no".
- **Líneas, contexto 2010-2025** (opcional): eje `agg_contexto_anual[anio]`, valor `Promedio anual (contexto)`,
  leyenda `dim_estacion[nombre]`, filtro contaminante = NO2 (figura `14_contexto_no2_anual.png`).

### Página 3 · Calidad de datos ("¿Cuánto podemos confiar?")

- **Heatmap de completitud**: matriz con filas `dim_estacion[nombre]` + `dim_contaminante[codigo_fuente]`,
  columnas `agg_completitud_mensual[anio_mes]`, valores `completitud` (promedio), formato condicional de color de
  fondo (escala de azules: claro = sin datos, oscuro = completo). Es el gráfico central de esta página.
- **Tabla "qué quedó afuera"**: `agg_anual` filtrado por `es_valido = falso` (estación, contaminante, período,
  completitud) + texto "menos de 75% de días con dato: no se calcula el promedio anual".
- **Barras**: `calidad_resumen` (valores horarios por categoría): 87,8% válidos, 11,9% sin dato en la fuente, 0,3%
  descartados por reglas (hora 0, `#REF!`, una hora en cero, valores fuera de rango).

## 3. Segmentadores

En una fila arriba de cada página, sincronizados entre páginas (*Ver → Sincronizar segmentaciones*):
**estación** (`dim_estacion[nombre]`), **contaminante** (`dim_contaminante[nombre]`), **año**
(`dim_calendario[anio]`), **tipo de día** (`dim_calendario[tipo_dia_etiqueta]`) y **estación del año**
(`dim_calendario[estacion_del_anio]`). En la página 2, para los visuales anuales, un segmentador de **período**
(`dim_periodo[etiqueta]`).

## 4. Colores y accesibilidad

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

## 5. Control de los números

Antes de presentar, comparar el dashboard con las vistas SQL (`analisis.v_resumen_estacion`) o con el notebook:

| Indicador | La Boca | Córdoba | Parque Centenario |
|---|---|---|---|
| % de días con NO₂ sobre 25 µg/m³ (todo el período) | 95,0% (900 días) | 85,6% (864) | 54,9% (676) |
| % de días que cumplen el IT2 diario de NO₂ (50 µg/m³) | 50,0% | 87,6% | 98,5% |
| NO₂ promedio, últimos 12 meses | 45,9 µg/m³ (4,6×, > IT1) | 35,1 (3,5×, IT1) | 26,3 (2,6×, IT2) |
| % de días con PM10 sobre 45 µg/m³ | 4,1% | 3,2% | 2,4% |
| Racha máxima de NO₂ sobre la guía (días con dato) | 254 días | 111 días | 26 días |
| NO₂ del domingo vs. día hábil | −17% | −21% | −26% |
