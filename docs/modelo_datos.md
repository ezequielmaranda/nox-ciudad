# Modelo de datos

Cómo están organizados los datos para poder consultarlos: una base **DuckDB** (`data/warehouse/aire.duckdb`)
construida con **dbt**, con un **esquema estrella** en el centro. El detalle de cada columna está en
[`diccionario_datos.md`](diccionario_datos.md).

## 1. Capas (schemas)

| Schema | Qué tiene | Modelos dbt |
|---|---|---|
| `referencia` | Tablas mantenidas a mano en `data/reference/` (seeds) | `oms_2021`, `contaminantes`, `estaciones`, `feriados`, `eventos` |
| `staging` | El crudo horario en formato largo, tipado y validado (una fila por celda del CSV), y el valor diario | `stg_aire_horario`, `stg_aire_horario_validado`, `stg_aire_diario` |
| `modelo` | **Esquema estrella**: dimensiones, referencias OMS y dos tablas de hechos (diaria y horaria) | `dim_*`, `ref_oms`, `ref_oms_niveles`, `fact_medicion_diaria`, `fact_medicion_horaria` |
| `calidad` | Completitud, violaciones a las reglas y outliers | `agg_completitud_*`, `calidad_*` |
| `indicadores` | Los indicadores contra la OMS y la serie larga de contexto | `agg_cumplimiento_diario`, `agg_anual`, `agg_cumplimiento_niveles`, `agg_rachas`, `agg_contexto_anual` |
| `analisis` | Vistas de `sql/99_consultas_analisis.sql` (para verificar el dashboard) | `v_resumen_estacion`, `v_cumplimiento_por_tipo_dia`, `v_indicadores_excluidos` |

## 2. Esquema estrella

```mermaid
erDiagram
    dim_calendario ||--o{ fact_medicion_diaria : "fecha"
    dim_estacion ||--o{ fact_medicion_diaria : "id_estacion"
    dim_contaminante ||--o{ fact_medicion_diaria : "id_contaminante"
    dim_calendario ||--o{ fact_medicion_horaria : "fecha"
    dim_estacion ||--o{ fact_medicion_horaria : "id_estacion"
    dim_contaminante ||--o{ ref_oms : "id_contaminante"
    dim_calendario ||--o{ agg_cumplimiento_diario : "fecha"
    dim_estacion ||--o{ agg_cumplimiento_diario : "id_estacion"
    dim_contaminante ||--o{ agg_cumplimiento_diario : "id_contaminante"
    dim_periodo ||--o{ agg_anual : "id_periodo"
    dim_estacion ||--o{ agg_anual : "id_estacion"
    dim_contaminante ||--o{ agg_anual : "id_contaminante"

    fact_medicion_diaria {
        date fecha PK
        varchar id_estacion PK
        varchar id_contaminante PK
        int n_horas_validas
        double valor "promedio 24 h, unidad original"
        double valor_masa "unidad OMS"
        boolean tiene_fila
        boolean tiene_dato
        varchar motivo_sin_dato
        boolean es_outlier
    }
    fact_medicion_horaria {
        date fecha PK
        int hora PK "1 a 24"
        varchar id_estacion PK
        varchar id_contaminante "no2"
        boolean es_valido
        double valor "ppb"
        double valor_masa "µg/m³"
    }
    dim_calendario {
        date fecha PK
        int anio
        int mes
        varchar estacion_del_anio
        varchar tipo_dia "habil | sabado | domingo | feriado"
        boolean es_feriado
        varchar evento
    }
    dim_estacion {
        varchar id_estacion PK
        varchar nombre
        varchar entorno
        varchar flujo_vehicular
    }
    dim_contaminante {
        varchar id_contaminante PK
        varchar nombre
        varchar unidad_medicion
        varchar unidad_masa
        double factor_masa
    }
    ref_oms {
        varchar id_contaminante PK
        varchar promedio PK "24h | anual"
        double guia_oms
        double it1
        double it2
        double it3
        double it4
    }
    dim_periodo {
        varchar id_periodo PK "2024 | 2025 | 2026 | movil_12m"
        date fecha_desde
        date fecha_hasta
        varchar tipo_periodo
    }
    agg_cumplimiento_diario {
        date fecha PK
        varchar id_estacion PK
        varchar id_contaminante PK
        double valor
        boolean supera_guia
        double veces_guia
        varchar nivel_oms
    }
    agg_anual {
        varchar id_estacion PK
        varchar id_contaminante PK
        varchar id_periodo PK
        double completitud
        boolean es_valido
        double promedio_anual
        double veces_guia_anual
        double p99_24h
        double pct_dias_supera_24h
    }
```

| Tabla | Qué representa | Clave | Filas |
|---|---|---|---|
| `fact_medicion_diaria` | El promedio de 24 h de un contaminante, en una estación, un día | `fecha, id_estacion, id_contaminante` | 9.036 |
| `fact_medicion_horaria` | Una hora de NO2 en una estación (segunda tabla de hechos, otro grano) | `fecha, hora, id_estacion` | 70.704 |
| `dim_calendario` | Un día del período, haya o no datos (tipo de día, feriado, estación del año, evento) | `fecha` | 1.004 |
| `dim_estacion` | Una estación de monitoreo (ubicación, entorno, flujo vehicular) | `id_estacion` | 3 |
| `dim_contaminante` | Un contaminante (unidades, factor de conversión, cómo lo publica la red, máximo plausible) | `id_contaminante` | 3 |
| `ref_oms` | Una guía OMS: contaminante × período de promedio, con objetivos intermedios | `id_contaminante, promedio` | 5 |
| `ref_oms_niveles` | La misma guía en formato largo, una fila por nivel (para líneas de referencia) | `id_contaminante, promedio, nivel` | 19 |
| `dim_periodo` | Un período de indicadores anuales | `id_periodo` | 4 |
| `agg_cumplimiento_diario` | Un día con dato de NO2, PM10 o CO comparado con su guía de 24 h | `fecha, id_estacion, id_contaminante` | 7.615 |
| `agg_anual` | Indicadores de un período por estación y contaminante | `id_estacion, id_contaminante, id_periodo` | 36 |

**Relaciones:** todas son uno a muchos desde la dimensión hacia la tabla de hechos o el agregado. Los tests de dbt
`relationships` verifican que toda clave de la fact exista en su dimensión (integridad referencial).

## 3. Decisiones de modelado

### Formato largo y no ancho

El crudo de BA Data viene en formato **ancho**: una columna por estación y contaminante (`NO2_LA_BOCA`,
`PM10_CORDOBA`, etc.). El staging lo pasa a formato **largo** con `UNPIVOT` (una fila por contaminante) porque:

- **El JOIN con la OMS es por contaminante:** `fact JOIN ref_oms USING (id_contaminante)` resuelve todos los
  contaminantes con la misma consulta. En formato ancho habría que escribir una comparación por columna.
- **En Power BI** un solo segmentador elige el contaminante y todas las medidas DAX sirven para todos.
- **Agregar un contaminante** (por ejemplo, O3) no cambia la estructura de ninguna tabla.
- Es la forma estándar de una tabla de hechos en un esquema estrella.

**Alternativa (formato ancho):** es más cómoda para correlaciones y gráficos de dispersión entre contaminantes (una
fila por estación y día). Cuando hace falta, se pivotea en el momento (el notebook lo hace en la sección 9).

### Grilla completa

La fact tiene todas las combinaciones calendario × estación × contaminante, aunque no haya dato. Así:
los días faltantes se cuentan con un `COUNT` (no hay que "buscar lo que no está"), la completitud es un promedio
de `tiene_dato` y Power BI puede mostrar huecos en las series. El costo es tener filas con valor nulo (16% de la
fact), marcadas con `tiene_dato = false` y su motivo.

### Dos tablas de hechos: diaria y horaria

La OMS define sus guías de corto plazo sobre el **promedio de 24 h**: todos los indicadores usan la fact diaria. El
valor diario se arma en `stg_aire_diario` según cómo publica la red cada contaminante (NO2 horario con 18 horas o
más; PM10 con el móvil de 24 h de la hora 24; CO con los bloques de 8 h). La **fact horaria** guarda solo el NO2,
el único publicado como promedio de cada hora, para el perfil horario por tipo de día. Las dos comparten
dimensiones (calendario, estación, contaminante): es un esquema estrella con dos tablas de hechos de distinto grano
(a veces llamado "constelación"). Un test de dbt verifica que el promedio diario de la fact diaria coincida con el
de las horas de la fact horaria.

### Umbrales en tablas, no en el código

Las guías OMS (`ref_oms`), los máximos plausibles de las reglas de calidad y los factores de conversión
(`dim_contaminante`) y los parámetros del estudio (período, regla del 75%, horas mínimas por día, factor del IQR,
en `dbt_project.yml`)
están en tablas o variables. El SQL los trae con un JOIN o con `var()`: cambiar un umbral no obliga a tocar
consultas.

### Valores en dos unidades

`valor` (unidad publicada: ppb, ppm, µg/m³) sirve para las reglas de calidad y para comparar con la fuente;
`valor_masa` (unidad de la OMS: µg/m³; mg/m³ para el CO) sirve para los indicadores.

### Por qué DuckDB y dbt

- **DuckDB:** base analítica en un solo archivo, sin servidor, que lee CSV directamente y usa SQL
  estándar. Si la cátedra pide otro motor, el SQL se porta casi entero; las funciones propias de DuckDB están
  comentadas donde aparecen (`FILTER`, `quantile_cont`, `UNPIVOT`, `generate_series`, fecha − entero).
- **dbt:** cada tabla es un `SELECT` en un archivo `.sql`. dbt las ejecuta en orden de dependencias (`ref()`),
  corre los tests de calidad en cada build y genera la documentación con el linaje de las tablas (`dbt docs`).
  No agrega infraestructura: es una librería de Python que corre contra el mismo archivo DuckDB.

## 4. Vistas para Power BI

Power BI importa los CSV de `data/final/` (no se conecta a la base). Las vistas del schema `analisis`
(`sql/99_consultas_analisis.sql`, parte D) calculan en SQL lo mismo que las medidas DAX del
modelo de Power BI y sirven para verificar que el dashboard muestre los números correctos.
