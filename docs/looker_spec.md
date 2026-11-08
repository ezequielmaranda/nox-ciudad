# Dashboard en Looker Studio: especificación

Guía para armar el dashboard a mano. El trabajo técnico ya está hecho: Looker Studio **comunica** los resultados
del ETL y el EDA, no recalcula reglas. Público: funcionarios, prensa y ciudadanía (no técnico).

## 0. Datos listos: `dashboard/looker/`

Looker Studio no tiene relaciones entre tablas como un modelo estrella: cada fuente de datos es **una tabla sola**.
Por eso `src/generar_looker.py` (lo corre el ETL, o `.venv\Scripts\python -m src.generar_looker` solo) une las
dimensiones y las guías de la OMS a cada hecho y deja 5 tablas planas, derivadas de `data/final/` sin recalcular
reglas. **No se probó en Looker Studio** (no hay cómo hacerlo desde el entorno donde se generó): si algún tipo o
fórmula no anda, Looker dice cuál es el campo.

| Archivo | Filas | Una fila por | Para qué |
|---|---|---|---|
| `looker_diaria.csv` | 9.036 | día × estación × contaminante (grilla completa, con y sin dato) | Todo lo diario: % de días sobre la guía, escalón de cada día, series, completitud mensual, mapa |
| `looker_horaria.csv` | 59.902 | hora válida de NO₂ × estación | Perfil horario por tipo de día |
| `looker_anual.csv` | 162 | estación × contaminante × período (2010-2026 y últimos 12 meses) | Promedio anual, veces la guía, nivel OMS, matriz de escalones, P99, racha máxima, contexto 2010-2025 |
| `looker_tipo_dia.csv` | 36 | estación × contaminante × tipo de día | Variación contra el día hábil (Looker no puede calcularla con una fórmula) |
| `looker_calidad.csv` | 17 | contaminante × categoría de calidad | Barras de la página de calidad |

Convenciones de las columnas: fechas `YYYYMMDD`, meses `YYYYMM`, banderas verdadero/falso como `1`/`0`, valores en
la unidad de la guía (`valor_masa`: µg/m³; mg/m³ para el CO), porcentajes como fracción (0,95 = 95%). Las guías
(`guia_24h`, `guia_anual`) vienen en cada fila para usarlas como línea de referencia. Los nombres de campo comunes
(`estacion`, `contaminante`, `tipo_dia_etiqueta`, `periodo`) son iguales en todas las tablas.

## 1. Cargar los datos

1. [lookerstudio.google.com](https://lookerstudio.google.com) → *Crear → Informe* → *Añadir datos* → conector
   **Subir archivo** (o **Hojas de cálculo de Google**: importar el CSV a una hoja; entran de sobra en el límite).
   Repetir por cada uno de los 5 CSV: queda **una fuente de datos por archivo**.
2. En cada fuente (*Editar fuente de datos*), ajustar los tipos:

| Campo | Tipo en Looker Studio |
|---|---|
| `fecha`, `primera_fecha`, `ultima_fecha`, `racha_desde`, `racha_hasta` | Fecha → *Fecha (AAAAMMDD)* |
| `anio_mes` | Fecha → *Año y mes (AAAAMM)* |
| `ubicacion` (solo `looker_diaria`) | Geografía → *Latitud, longitud* |
| `anio`, `hora`, `orden_*` | Número (agregación: Ninguna) |
| `estacion`, `contaminante`, `periodo`, `nivel_oms`, `tipo_dia_etiqueta` | Texto |
| `tiene_dato`, `supera_guia`, `es_valido`, `es_periodo_estudio`, `es_outlier` | Número (agregación: Suma) |
| `completitud`, `pct_*`, `proporcion`, `variacion_vs_habil` | Número → *Porcentaje* |

3. Los datos son de un **archivo subido**: no se actualizan solos. Cuando el ETL sume meses nuevos, volver a subir
   los CSV (*Editar fuente de datos → Editar conexión*).

## 2. Campos calculados

Se crean en la fuente de datos (*Añadir un campo*). Equivalen a las consultas de la parte D de
`sql/99_consultas_analisis.sql`: sirven para controlar los números (sección 6).

**En `looker_diaria`:**

| Campo | Fórmula | Nota |
|---|---|---|
| Días válidos | `SUM(tiene_dato)` | Mostrar siempre junto a un porcentaje |
| Completitud % | `SUM(tiene_dato) / COUNT(fecha)` | Con `anio_mes` en columnas arma el heatmap de completitud |
| Días sobre guía | `SUM(supera_guia)` | `supera_guia` está vacío en los días sin dato |
| % Días sobre guía | `SUM(supera_guia) / SUM(tiene_dato)` | Un día sin dato no cuenta como día limpio |
| % Días que cumplen IT2 | `SUM(CASE WHEN tiene_dato = 1 AND orden_nivel_oms <= 4 THEN 1 ELSE 0 END) / SUM(tiene_dato)` | IT2 diario del NO₂: 50 µg/m³. No aplica al CO |
| Promedio diario | `AVG(valor_masa)` | |
| Guía OMS 24 h | `AVG(guia_24h)` | Línea de referencia; filtrar un contaminante |
| % Días sobre guía (texto) | `CONCAT(CAST(ROUND(SUM(supera_guia) / SUM(tiene_dato) * 100, 1) AS TEXT), "% de ", CAST(SUM(tiene_dato) AS TEXT), " días")` | Tarjetas: "95,0% de 900 días" |

**En `looker_anual`** (filtrar un contaminante, y `es_periodo_estudio = 1` salvo en el gráfico de contexto):

| Campo | Fórmula | Nota |
|---|---|---|
| Promedio anual | `AVG(promedio_anual)` | Vacío si el período tiene menos de 75% de días (regla del 75%). Usar con una estación y un período por celda |
| Veces sobre guía anual | `AVG(veces_guia_anual)` | |
| Percentil 99 | `MAX(p99_24h)` | Una fila por celda |
| Racha máxima | `MAX(racha_maxima_dias)` | Días con dato seguidos sobre la guía; huecos de hasta 7 días no la cortan |
| % Días que cumplen IT2 (anual) | `AVG(pct_cumple_it2_24h)` | La versión por año de la matriz de escalones |

**En `looker_horaria`:** `NO₂ horario promedio` = `AVG(valor_masa)`.
**En `looker_tipo_dia`:** `Variación vs. hábil` es la columna `variacion_vs_habil` (promedio del tipo de día contra el
hábil, ya calculado).

## 3. Páginas

Mensaje y orden iguales a la presentación. Los hallazgos están en el README (sección Hallazgos).

### Página 1 · Resumen ("¿Cuán lejos estamos de la OMS?")

Mensaje: **ninguna estación cumple la guía de NO₂ de la OMS; Parque Centenario y Córdoba están en escalones
intermedios y La Boca no alcanza ni el primero.**

- **Fila de 4 tarjetas** (filtro de página: contaminante = Dióxido de nitrógeno):
  1. Tabla de `looker_anual` con `estacion` y `nivel_oms`, período "últimos 12 meses" ("IT2 · IT1 · > IT1").
  2. `% Días que cumplen IT2` por estación ("98,5% · 87,6% · 50,0%").
  3. `Veces sobre guía anual` de La Boca, últimos 12 meses ("4,6 veces la guía anual").
  4. `Racha máxima` ("254 días con dato seguidos sobre la guía").
- **Barras 100% apiladas "en qué escalón cae cada día"** (`looker_diaria`): dimensión `estacion`, dimensión de
  desglose `nivel_oms` (ordenada por `orden_nivel_oms`), métrica `Días válidos`, *Apilado 100%*; filtro
  `tiene_dato = 1`. Colores por nivel (sección 5). Responde "¿en qué escalón está cada estación?" (figura
  `reports/figures/06_niveles_oms_diarios.png`).
- **Tabla por estación**: `estacion`, `nivel_oms`, `Promedio anual` (últimos 12 meses), `% Días sobre guía` y, en
  texto chico, `flujo_vehicular` y `fuentes_fijas` (base de H2: Córdoba tiene el flujo más alto y La Boca,
  fuentes fijas).
- **Mapa de burbujas** (`looker_diaria`): ubicación = `ubicacion`, tamaño = `% Días sobre guía`. Si no aporta,
  alcanza con la tabla.
- **Cuadro de texto** con 3 conclusiones en lenguaje simple.

### Página 2 · Detalle ("¿Cuándo y dónde es peor?")

- **Serie temporal** (`looker_diaria`): dimensión `fecha` (o `anio_mes` para promedios mensuales), métrica
  `Promedio diario`, desglose `estacion`. Línea de referencia: *Estilo → Líneas de referencia → Métrica* con
  `Guía OMS 24 h`; rotularla "Guía OMS".
- **Matriz de escalones** (`looker_anual`, tabla dinámica): filas `estacion` y `periodo`, métricas
  `pct_cumple_guia_24h`, `pct_cumple_it2_24h` y `pct_cumple_it1_24h`, con *mapa de calor* (escala de azules).
  Filtros `es_periodo_estudio = 1` y control de contaminante. Para la presentación alcanza con el NO₂ y los años
  (figura `06b_matriz_niveles_no2.png`). Celdas vacías = período con menos de 75% de días.
- **Barras agrupadas**: `% Días sobre guía` por `contaminante` y `estacion` (sin filtro de contaminante).
- **Barras horizontales** (`looker_anual`): `Promedio anual` por estación y período, con líneas de referencia en la
  guía anual (`guia_anual`) y los objetivos intermedios (valores de `guia_oms.csv`: constantes).
- **Tabla dinámica** (`looker_diaria`): filas `tipo_dia_etiqueta`, columnas `estacion_del_anio`, métrica
  `% Días sobre guía` con mapa de calor (escala de un solo tono) y `Días válidos`.
- **Barras** (`looker_tipo_dia`): `Variación vs. hábil` por `tipo_dia_etiqueta` y `estacion` (mensaje: "el domingo
  baja 17 a 26%, pero en La Boca el 90% de los domingos sigue sobre la guía").
- **Líneas, perfil horario** (`looker_horaria`): dimensión `hora`, métrica `NO₂ horario promedio`, desglose
  `tipo_dia_etiqueta` (filtrar Hábil y Domingo) y control de estación (figura `11_ritmo_semanal.png`).
  Mensaje: "en día hábil aparecen las horas pico; el domingo, no".
- **Líneas, contexto 2010-2025** (opcional, `looker_anual`): dimensión `anio`, métrica `Promedio anual`, desglose
  `estacion`, filtros contaminante = NO₂ y `tipo_periodo = anio_completo` (figura `14_contexto_no2_anual.png`).

### Página 3 · Calidad de datos ("¿Cuánto podemos confiar?")

- **Heatmap de completitud** (`looker_diaria`, tabla dinámica con mapa de calor): filas `estacion` +
  `codigo_fuente`, columnas `anio_mes`, métrica `Completitud %` (escala de azules: claro = sin datos, oscuro =
  completo). Es el gráfico central de esta página.
- **Tabla "qué quedó afuera"** (`looker_anual`): filtro `es_valido = 0` y `es_periodo_estudio = 1`: estación,
  contaminante, período, completitud + texto "menos de 75% de días con dato: no se calcula el promedio anual".
- **Barras** (`looker_calidad`): `n_valores` por `categoria`: 87,8% válidos, 11,9% sin dato en la fuente, 0,3%
  descartados por reglas (hora 0, `#REF!`, una hora en cero, valores fuera de rango).

## 4. Controles

En una fila arriba de cada página: **estación** (`estacion`), **contaminante** (`contaminante`), **año** (`anio`),
**tipo de día** (`tipo_dia_etiqueta`) y **estación del año** (`estacion_del_anio`). Cada control filtra los gráficos de
su misma fuente de datos; para que una página con gráficos de varias fuentes responda a un solo control, hay que
verificar que el filtro llegue a todas (si no, *combinar datos* por `estacion` y `contaminante`, o poner un control
por fuente). Para mantener los controles entre páginas: *Organizar → Establecer como de todo el informe*. En los
gráficos de `looker_anual`, un control de **período** (`periodo`).

## 5. Colores y accesibilidad

No usar rojo/verde como única codificación (daltonismo). Cada estación tiene **un color fijo en todo el TP** (igual
que en las figuras del EDA); los niveles OMS van en una escala de **un solo tono** (más oscuro = más lejos de la
guía) y siempre con la etiqueta del nivel escrita. En Looker Studio los colores se fijan a mano en cada gráfico
(*Estilo → Colores de la serie*) o una vez en *Tema y diseño → Personalizar*.

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

Los colores de estación están validados para las formas más comunes de daltonismo. El aqua tiene contraste bajo
sobre fondo claro: mostrar siempre las etiquetas de datos o el nombre de la estación junto a la marca.

## 6. Control de los números

Antes de presentar, comparar el dashboard con la consulta D1 de `sql/99_consultas_analisis.sql` o con el notebook:

| Indicador | La Boca | Córdoba | Parque Centenario |
|---|---|---|---|
| % de días con NO₂ sobre 25 µg/m³ (todo el período) | 95,0% (900 días) | 85,6% (864) | 54,9% (676) |
| % de días que cumplen el IT2 diario de NO₂ (50 µg/m³) | 50,0% | 87,6% | 98,5% |
| NO₂ promedio, últimos 12 meses | 45,9 µg/m³ (4,6×, > IT1) | 35,1 (3,5×, IT1) | 26,3 (2,6×, IT2) |
| % de días con PM10 sobre 45 µg/m³ | 4,1% | 3,2% | 2,4% |
| Racha máxima de NO₂ sobre la guía (días con dato) | 254 días | 111 días | 26 días |
| NO₂ del domingo vs. día hábil | −17% | −21% | −26% |

Todos los valores de la tabla se recalcularon desde las tablas de `dashboard/looker/` y coinciden. En
`looker_diaria`, las filas que cuentan como "días" son las de `tiene_dato = 1` (el denominador de los porcentajes).
