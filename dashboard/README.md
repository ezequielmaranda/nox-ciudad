# Dashboard en Looker Studio — guía de armado

**Herramienta:** [Looker Studio](https://lookerstudio.google.com) (gratis, en el navegador, se edita entre
varios como un documento de Google).

**Principio:** el dashboard **no calcula el análisis, lo muestra.** La limpieza, el modelo y la prueba placebo
ya están hechos en el pipeline (dbt) y en los notebooks. Looker Studio solo lee tablas planas listas para
graficar. Así cualquiera del equipo puede explicar de dónde sale cada número.

## 1. Generar los datos

```
uv run python run.py --analisis
```

Deja en `export/looker/` siete CSV (fuera de git: se comparten por Drive):

| Archivo | Una fila por | Para qué página |
|---|---|---|
| `aire_diario.csv` | estación y día | 1. El problema |
| `transporte_diario.csv` | día | 2. Los paros |
| `meteo_diario.csv` | día | 5. Método (opcional) |
| `eventos.csv` | evento | 2. Los paros |
| `indice_tipo_dia.csv` | grupo de día y variable | 3. El gradiente |
| `resultados_evento.csv` | evento, estación y variable | 4. El resultado |
| `resultados_grupo.csv` | grupo y variable | 4. El resultado |

## 2. Crear el informe y las fuentes de datos

1. En Looker Studio: **Crear → Informe**. Nombre: "¿Qué le pasa al aire porteño cuando paran los colectivos?".
2. **Agregar datos → Carga de archivos** y subir **cada CSV como una fuente de datos aparte** (son 7 fuentes).
3. En cada fuente, revisar los tipos de campo antes de usarla:
   - `fecha` → **Fecha (AAAA-MM-DD)**.
   - Concentraciones, porcentajes, `indice`, `desvio_pct`, `percentil_placebo` → **Número**.
   - `anio`, `mes`, `dia_semana` → Número, con agregación **Ninguna** (son categorías, no se suman).
   - `estacion_nombre`, `grupo_dia`, `grupo_nombre`, `variable`, `evento` → Texto.
4. **Compartir** (arriba a la derecha) → agregar a los cuatro como **editores**.

**Actualizar los datos:** si se vuelve a correr el pipeline, en **Recursos → Administrar fuentes de datos →
Editar → Editar conexión** se borra el archivo viejo y se sube el nuevo (Looker Studio no reemplaza: si se
agrega un archivo sin borrar el anterior, duplica las filas).

## 3. Campos calculados

Se crean en la fuente de datos (**Agregar un campo**). Pocos y explicables en una frase:

| Fuente | Nombre | Fórmula | Qué es |
|---|---|---|---|
| aire_diario | `% días NO2 sobre guía OMS` | `AVG(no2_sobre_guia_oms)` (formato porcentaje) | % de días con dato que superaron 25 µg/m³ en 24 h |
| aire_diario | `% días PM10 sobre guía OMS` | `AVG(pm10_sobre_guia_oms)` (formato porcentaje) | Ídem PM10 con 45 µg/m³ |
| aire_diario | `NO2 percentil 99` | `PERCENTILE(no2_24h_ugm3, 99)` | El valor que usa la OMS para la guía de 24 h |
| aire_diario | `NOx/CO típico` | `MEDIAN(nox_co_816)` | La firma diésel de un día típico |
| transporte_diario | `Viajes (millones)` | `SUM(usos_colectivo_caba) / 1000000` | Viajes en colectivos que circulan por CABA |

`no2_sobre_guia_oms` ya viene en el CSV: vale 1 si el día superó la guía, 0 si no y vacío si no hay dato.
Por eso el promedio da directamente el porcentaje de días con dato.

**Chequeo obligatorio** (si no coincide, algo está mal configurado), con el filtro en La Boca y todo el período:
`% días NO2 sobre guía OMS` ≈ 94,7% · `NO2 percentil 99` ≈ 95 µg/m³ · `NOx/CO típico` ≈ 162.

## 4. Páginas (siguen el orden de la exposición)

**Pregunta:** ¿cambia la contaminación del aire en la Ciudad en los días de paro de colectivos, trenes o
subte, y cómo queda frente a las guías de la OMS? **H1:** con paro de colectivos el NOx es menor que en días
hábiles comparables. **H2:** con paro de trenes o subte (colectivos funcionando) el NOx no baja.

Arriba de cada página, un **título con el mensaje** (no "Gráfico de NOx", sino "El NO2 supera la guía de la
OMS casi todos los días"). Abajo, la fuente: "Fuente: APrA (GCBA), SUBE (Secretaría de Transporte), SMN".

### Página 1 · El problema: el aire de la Ciudad
- **Controles:** lista desplegable `estacion_nombre`; control de período sobre `fecha`.
- **Tarjetas de resultados:** `% días NO2 sobre guía OMS`, `NO2 percentil 99`, mediana de `no2_24h_ugm3`.
- **Serie temporal:** dimensión `fecha` con granularidad **Año y mes**, desglose `estacion_nombre`,
  métrica `MEDIAN(nox_816_ppb)`. Mensaje: el NOx casi se duplica en invierno.
- **Barras:** dimensión `estacion_nombre`, métrica `% días NO2 sobre guía OMS`.

### Página 2 · El experimento natural: los paros
- **Serie temporal** (fuente `transporte_diario`): `fecha` por día, métrica `Viajes (millones)`.
- **Tabla** (fuente `transporte_diario`, filtro `evento` no es nulo): `fecha`, `evento`,
  `pct_lineas_paradas_ponderado`, `ratio_tren`, `ratio_subte`.
- **Barras horizontales:** `evento` por `pct_lineas_paradas_ponderado`. Mensaje: en cuatro días pararon
  2 de cada 3 colectivos.

### Página 3 · El gradiente
- **Barras** (fuente `indice_tipo_dia`, filtro `variable` en NOx y CO): dimensión `grupo`, desglose `variable`,
  métrica `MAX(indice)`. Orden: `MAX(actividad)` descendente (de más a menos colectivos). **Línea de referencia**
  en 100.
- Mensaje: en los paros de colectivos baja el NOx y sube el CO; en el resto de los días bajan los dos.

### Página 4 · El resultado: las hipótesis
- **Tarjetas** (fuente `resultados_grupo`, filtro `variable = NOx`): una con filtro `grupo = sin_colectivos`
  (H1: −28%, `valor_p_texto` ≈ 0,002) y otra con `grupo = trenes_subte` (H2: −19%, p ≈ 0,05).
- **Barras horizontales** (fuente `resultados_evento`, filtro `variable = NOx`): dimensión `etiqueta`, métrica
  `MAX(desvio_pct)`, desglose `grupo_nombre`. Mensaje: con paro de colectivos el NOx cae más de lo esperable.
- **Tabla** (misma fuente, `variable` en NOx, NO2 y CO): `etiqueta`, `variable`, `desvio_pct`,
  `percentil_placebo`, con **mapa de calor** en `percentil_placebo` (valores bajos = caída rara para un día normal).

### Página 5 · ¿Y frente a la OMS?
- **Gráfico combinado** (fuente `resultados_evento`, filtro `variable = NO2 24 h (µg/m³)`): dimensión `etiqueta`,
  métricas `MAX(observado)` (barras) y `MAX(esperado)` (línea), **línea de referencia** en 25 (guía OMS de 24 h).
- **Tarjeta:** casos de paro por debajo de la guía (2 de 10 en paros de colectivos).
- Mensaje: aun sin colectivos, el NO2 casi siempre queda por encima de la guía de la OMS.

### Página 6 · Cómo lo hicimos y qué no sabemos
- Texto con el esquema: fuentes públicas → Python (extract) → DuckDB + dbt (bronze/silver/gold, tests de
  calidad) → notebooks (EDA, regresión, placebo) → Looker Studio.
- Las limitaciones del notebook `05_eventos` (pocos eventos, colectivos o camiones, los paros bajan la actividad
  en general, SUBE mide pasajeros, meteorología diaria, datos redondeados, sin PM2,5).

## 5. Colores

En cada gráfico: **Estilo → Color por → Valores de la dimensión**. El color que se le asigna a un valor
queda fijo en todo el informe, así que alcanza con hacerlo una vez:

| Valor | Color |
|---|---|
| Centenario | `#2a78d6` (azul) |
| Córdoba | `#eb6834` (naranja) |
| La Boca | `#1baf7a` (verde agua) |
| Paro de colectivos | `#6250d6` (violeta) |
| Paro de trenes o subte | `#eda100` (amarillo) |
| Resto de grupos de días | `#b9b8b2` (gris) |
| NOx / CO (página 3) | `#0b0b0b` / `#b9b8b2` |

Fondo `#fcfcfb`, texto `#0b0b0b`. Son los mismos colores de los notebooks: la estación o el grupo se
reconocen igual en el informe y en la exposición.
