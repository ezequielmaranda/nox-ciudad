# Documentación del proceso

De dónde salen los datos, cómo se procesan y qué problemas de calidad se encontraron y resolvieron.
Complementa a [`modelo_datos.md`](modelo_datos.md) (estructura y diccionario) y a los notebooks de `analysis/`
(análisis).

## 1. El flujo de punta a punta

```
1. Extraer      extract/*.py        fuentes públicas → data/raw (originales) y data/landing (CSV)
2. Cargar       dbt (bronze)        landing → DuckDB, todo como texto, con archivo de origen
3. Transformar  dbt (silver, gold)  tipar, normalizar, marcar calidad, unir → tablas de análisis
4. Probar       dbt test            44 tests (claves, valores válidos, coherencia física, eventos)
5. Exportar     run.py              gold → export/*.parquet (notebooks) y export/looker/*.csv (dashboard)
6. Analizar     analysis/*.ipynb    EDA, regresión y prueba placebo → resultados_evento / resultados_grupo
```

Técnicamente es un **ELT**: los datos se cargan casi crudos a la base y se transforman adentro, con SQL. dbt
ordena y prueba las transformaciones; `run.py` encadena todos los pasos.

**Para reproducirlo desde cero** (Windows, Linux o Mac, con [uv](https://docs.astral.sh/uv/) instalado):

```
git clone https://github.com/ezequielmaranda/nox-ciudad
cd nox-ciudad
uv sync
# paso manual: bajar los datos diarios del SMN (ficha 3) y descomprimirlos en data/raw/smn/
uv run python run.py --extraer --analisis
```

Tarda unos minutos: la mayor parte es la descarga de los PDF de la APrA y de los CSV de SUBE.

## 2. Fichas de los datasets

### Ficha 1 · Calidad del aire (APrA, Gobierno de la Ciudad)

| | |
|---|---|
| **Qué es** | Informes mensuales de las estaciones de monitoreo de la Agencia de Protección Ambiental |
| **Origen** | https://buenosaires.gob.ar/calidad-del-aire (páginas de las estaciones Parque Centenario, Córdoba y La Boca) |
| **Cómo se obtiene** | `extract/aire_publico.py` recorre las páginas, baja los PDF y los convierte a CSV |
| **Formato original** | Un PDF por mes, contaminante y estación: `co_*`, `nox_*` (NO, NO2 y NOx), `pm10_*` |
| **Período** | Enero 2024 a septiembre 2026 (279 PDF procesados, 2 descartados) |
| **Grano** | Estación × día × contaminante × estadístico: promedio de 24 h, promedios de 0-8, 8-16 y 16-24 h, máximo y mínimo horario |
| **Volumen** | 83.010 valores en landing / bronze |
| **Unidades** | NO, NO2, NOx en ppb (enteros); CO en ppm (un decimal); PM10 en µg/m³ (enteros) |
| **Limitaciones** | Solo datos diarios y por bloques de 8 h (no horarios); valores redondeados; meses sin publicar |

### Ficha 2 · Viajes en transporte público (SUBE, Secretaría de Transporte)

| | |
|---|---|
| **Qué es** | Cantidad de viajes pagados con SUBE por línea y día |
| **Origen** | datos.transporte.gob.ar, dataset de usos de SUBE (`dat-ab-usos-<año>.csv`) |
| **Cómo se obtiene** | `extract/sube_descarga.py` (API del portal de datos abiertos) |
| **Período** | 01/01/2024 a 25/10/2026, sin días faltantes |
| **Grano** | Línea × día (colectivo, tren, subte y lanchas) |
| **Volumen** | 1.536.620 filas; 2.311 nombres de línea distintos que corresponden a 134 líneas de colectivo que circulan por CABA |
| **Columnas** | día, empresa, línea, AMBA, tipo de transporte, jurisdicción, provincia, municipio, cantidad, dato preliminar |
| **Limitaciones** | Mide pasajeros, no colectivos en la calle ni kilómetros; no dice por dónde circula cada línea; datos preliminares desde 2026 |

### Ficha 3 · Meteorología (Servicio Meteorológico Nacional)

| | |
|---|---|
| **Qué es** | Registro diario de las estaciones Aeroparque y Observatorio Central (Villa Ortúzar) |
| **Origen** | https://www.smn.gob.ar/descarga-de-datos → datos diarios: https://ssl.smn.gob.ar/dpd/zipopendata.php?dato=datosdiarios20212026 |
| **Cómo se obtiene** | **Manual** (hay que aceptar términos y condiciones): se descomprime el zip en `data/raw/smn/` y `extract/smn_to_csv.py` lo pasa a CSV |
| **Período** | 01/01/2021 a 31/07/2026 (el SMN publica con algunos meses de atraso) |
| **Grano** | Estación × día |
| **Volumen** | 40.856 valores (formato largo) → 4.076 estación-día |
| **Variables** | Temperatura media, máxima y mínima; humedad; presión; viento medio y ráfaga máxima; nubosidad; heliofanía; precipitación |
| **Limitaciones** | Promedios de 24 h (no la ventana de 8 a 16 h); la precipitación falta en el 64% de los días |

### Ficha 4 · Feriados (seed `feriados`)

| | |
|---|---|
| **Origen** | API pública ArgentinaDatos: `https://api.argentinadatos.com/v1/feriados/<año>` |
| **Contenido** | 59 feriados nacionales 2024-2026 (inamovibles, trasladables y puentes) |
| **Uso** | Tipo de día en `dim_calendario`. Los días no laborables optativos (Jueves Santo) los detecta la SUBE |

### Ficha 5 · Paros (seed `eventos`)

| | |
|---|---|
| **Origen** | Armado por el equipo: notas de prensa, **confirmadas con los datos de SUBE** |
| **Contenido** | 7 paros: 4 de colectivos (`sin_colectivos`) y 3 de trenes o subte con colectivos funcionando (`trenes_subte`) |
| **Control** | El test `eventos_coherentes_con_sube` falla si un paro cargado no coincide con lo que muestra la SUBE |
| **Descartados** | 05/07/2024 y 28/03/2025 (no se ven en SUBE), 24/01/2024 (paro de medio día), paros parciales de trenes (30/05/2024 y 28/01/2025) |

## 3. Problemas de calidad encontrados y cómo se resolvieron

Ninguna fila se borra: los valores con problemas se **marcan** en silver y gold toma solo los válidos. El
recuento de cada marca está en `analysis/consultas.sql` (consulta 7).

### Calidad del aire

| Problema | Ejemplo | Solución | Control |
|---|---|---|---|
| Los enlaces de la web de la Ciudad dan error 404 | `buenosaires.gob.ar/sites/default/files/...` redirige a una página histórica | Se descarga la misma ruta desde `static.buenosaires.gob.ar` | Manifiesto de descarga (`bronze_aire_manifiesto`) |
| El lector de PDF devuelve el texto por columnas, no por filas | La tabla diaria sale desordenada | Se reconstruye la tabla con las coordenadas de cada celda | Tests de coherencia física sobre todos los valores (NOx = NO + NO2, promedio dentro del rango horario) |
| Columnas constantes al final de la tabla, no siempre presentes | `2,6` o `100` en CO y PM10; falta en PM10 de oct-2024 | El parser acepta 0 a 2 columnas finales y las descarta | Aviso en el manifiesto |
| Nombres de archivo inconsistentes | `la boca`, `la  boca`, `laboca`, `_0`, `corregido`, `centenaeio` | La estación se toma de la página y del encabezado del PDF, no del nombre | Manifiesto |
| Un archivo de otra estación enlazado | El PM10 de Córdoba de feb-2026 apunta al archivo de La Boca; Centenario enlaza un NOx de Córdoba | Se descarta si la estación del PDF no coincide con la de la página | Manifiesto: 2 descartados |
| Encabezado equivocado | El PM10 de La Boca de may-2025 dice "Córdoba" | Se conserva (sus valores difieren del archivo de Córdoba del mismo mes) | Aviso en el manifiesto |
| Texto en una celda numérica | "Lunes" en el PM10 de Córdoba de jul-2025 | `estado_valor = invalido` | Test de valores aceptados |
| Febrero de 2024 (bisiesto) con 28 filas | La tabla termina el día 28 | Se acepta una tabla que termina en el día 28 o después | Aviso en el manifiesto |
| Valores especiales en lugar de números | `s/d`, `DND`, `<4` | `estado_valor`: sin_dato, bajo_limite_deteccion (con `limite_deteccion`) o valido | Test de valores aceptados |
| NOx distinto de NO + NO2 | 196 combinaciones día-bloque con diferencia mayor a 2 ppb | Marca `nox_incoherente` (se marcan los tres: no se sabe cuál está mal) | Test `silver_aire_nox_coherente` (aviso) |
| Un promedio fuera del rango horario del día | NOx 8-16 = 0 con mínimo horario 15 (La Boca, 29/02/2024) | Marca `fuera_de_max_min` | Test `silver_aire_max_min_coherentes` (aviso) |
| Ceros sin respaldo | 29/02/2024: todo "s/d" salvo los bloques de NOx en 0; analizador caído en Centenario el 01/08/2026 | Marca `cero_sin_respaldo` (promedio 0 con máximo horario 0 o faltante) | Encontrado en el EDA; test `gold_aire_nox_co_positivo` (error) |
| Valores físicamente imposibles | Negativos o por encima de máximos urbanos | Marca `fuera_de_rango` (0 casos) | Test `silver_aire_fuera_de_rango` (aviso) |
| Meses sin publicar en la fuente | NOx de Centenario de marzo a noviembre de 2024; CO de Córdoba abr-may 2024 | No se imputa: los paros de 2024 se miden donde hay dato | Mapa de cobertura (notebook 01) |
| Unidades distintas a las de la OMS | NO2 en ppb, guía en µg/m³ | `valor_masa` (1,88 µg/m³ por ppb a 25 °C) | — |

### SUBE

| Problema | Ejemplo | Solución | Control |
|---|---|---|---|
| La misma línea con nombres distintos | `LINEA 12` → `CABA_LINEA_12`; `BSAS_LINEA_026`; `CABA_LINEA_ 42`; cambios de operador (`CABA_LINEA_25` → `CABA_LINEA_025`) | Clave = número de línea extraído con una expresión regular, sumando las variantes de cada día | 2.311 nombres → 134 líneas |
| Jurisdicción mal cargada | Línea 6 como MUNICIPAL, 23 como PROVINCIAL, 99 como NACIONAL | El universo se define por número de línea, no por fila | — |
| Filtrar por provincia excluye a la Ciudad | Las líneas nacionales figuran con provincia `JN` | Universo: AMBA, colectivo, jurisdicción nacional o de la Ciudad, número < 200 | Test de valores aceptados de `tipo_transporte` |
| Líneas de numeración especial | `8012` a `8188`, solo en mayo de 2024 y con pocos viajes | Quedan fuera por el número < 200 | — |
| Las líneas solo porteñas cambian de jurisdicción | Pasan de NACIONAL a C.A.B.A el 20/01/2025 | Marca `es_linea_solo_caba` estable para toda la serie | — |
| Datos preliminares | Desde febrero de 2026 | Marca `es_dato_preliminar` | — |
| La demanda baja con los años | 2026 un 8% por debajo de 2024 | La referencia de cada día son sus semanas vecinas (±3 o ±4 semanas), no un promedio fijo | Notebook 02 |
| "Día normal" sin calendario de vacaciones ni paros | Puentes, vacaciones de invierno, paros de cualquier modo | Día normal = colectivo, tren y subte > 90% de lo habitual | Test `not_null` en `es_dia_normal` |
| Dosis de paro inventada en fines de semana | Antes daba 0% un sábado | Vacío cuando no hay base de comparación | Test `eventos_coherentes_con_sube` |

### Meteorología

| Problema | Ejemplo | Solución | Control |
|---|---|---|---|
| Precipitación faltante | 64% de los días sin registro en las dos estaciones | Sin registro = sin lluvia (supuesto declarado). Chequeo: los totales anuales dan 1.450-1.700 mm, coherentes con el clima de la Ciudad | Notebook 03 |
| Dirección del viento en decenas de grado | `VTO_MDIR` = 18 significa 180° | Se multiplica por 10 | — |
| El SMN publica con atraso | Datos hasta el 31/07/2026 | Después de esa fecha la meteorología queda vacía (no cero) y esos días no entran al modelo | Tests `not_null` en viento y temperatura |
| Primera fuente descartada: Meteostat | Mezclaba observaciones con pronósticos y pesaba 3 GB | Se comparó con el SMN (mismos resultados) y se dejó solo el SMN, fuente oficial | `CLAUDE.md`, sección 5 |

### Herramientas

| Problema | Solución |
|---|---|
| DuckDB 2.0 cambió el formato de archivo y las herramientas 1.x no abren la base | Versión fijada en `duckdb>=1.5.4,<2` (`pyproject.toml`) |
| Looker Studio no lee Parquet y exige encabezados sin caracteres especiales | `run.py` exporta CSV UTF-8 con encabezados ASCII |

## 4. Tests de calidad (dbt)

44 tests que corren en cada `dbt build`. Si uno de tipo *error* falla, el pipeline se detiene.

| Tipo | Cantidad | Ejemplos |
|---|---|---|
| Claves únicas | 9 | `unique` de fecha en las tablas diarias; `silver_aire_clave_unica`, `gold_aire_clave_unica`, `gold_analitico_clave_unica` |
| Valores no nulos | 20 | fechas, estaciones, contaminantes, `es_dia_normal`, viento y temperatura en gold |
| Valores aceptados | 9 | estación, contaminante, estadístico, `estado_valor`, `tipo_dia`, `grupo_dia`, grupo de evento |
| Coherencia física | 4 | NOx = NO + NO2, promedio dentro del rango horario, rangos físicos, NOx/CO positivo en gold |
| Reglas del estudio | 2 | porcentajes entre 0 y 100; los paros cargados coinciden con la SUBE |

Los tests de coherencia física de silver son **avisos** (*warn*): describen la fuente, no frenan el pipeline,
porque los valores marcados ya no pasan a gold. Resultado actual: 58 pasan y 2 avisos (los 196 casos de
NOx ≠ NO + NO2 y el 29/02/2024 de La Boca).

## 5. Supuestos que hay que declarar

1. Un día sin registro de lluvia en el SMN es un día sin lluvia.
2. La meteorología de la Ciudad es el promedio de Aeroparque y Observatorio (viento y temperatura) y el máximo
   de los dos (lluvia).
3. Una línea "paró" si tuvo menos del 15% de sus viajes habituales.
4. Un día hábil es "normal" si colectivo, tren y subte superan el 90% de su uso habitual.
5. La ventana diurna es el bloque de 8 a 16 h que publica la APrA.

Las limitaciones del análisis (pocos eventos, colectivos o camiones, etc.) están en las conclusiones del
notebook `05_eventos`.
