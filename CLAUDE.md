# CLAUDE.md — nox-ciudad

Contexto para continuar el proyecto en Claude Code. Idioma de trabajo: español rioplatense.
El usuario es data engineer con experiencia en monitoreo atmosférico: comunicación directa, sin vueltas.

## 1. Qué es

TP integrador de **Análisis de Datos 1** (licenciatura en ciencia de datos, UdelaCiudad). Equipo de 4.
Entrega: pipeline + EDA en Python + dashboard en **Power BI** + exposición con storytelling de 20 minutos.

**Pregunta:** ¿qué le pasa al aire porteño cuando paran los colectivos (flota casi toda diésel)?
**Hipótesis:** en días sin colectivos cae el NOx, y su proporción respecto del CO (la "firma diésel"),
más que en días hábiles comparables y más que en paros donde los colectivos funcionan.

Criterios de la consigna que guían las decisiones: uso de SQL, limpieza y calidad de datos visible,
flujo ETL básico, EDA en Python conectado a la hipótesis, coherencia problema-análisis-conclusiones,
**justificar decisiones técnicas**, **participación equilibrada** (cualquier integrante tiene que poder
explicar todo) e identificación de limitaciones. No se piden modelos de ML.

## 2. Reglas del proyecto

- **Explicable antes que sofisticado.** Nada de Prefect, ML ni infraestructura que el equipo no pueda defender.
- **Solo datos públicos.** Todas las fuentes del TP son publicadas (APrA, SUBE, SMN, feriados).
- **Los datos nunca van a git** (tamaño). `data/` está en `.gitignore`. En git: código y seeds.
- **No se borran filas en silver:** se marcan con flags de calidad. La limpieza vive en SQL/dbt, visible y testeada.
- **Hora:** local `-03:00` (Argentina no tiene horario de verano). La hora indica el **inicio** del promedio
  (`07:00-03:00` = promedio de 07 a 08).
- **Lenguaje de resultados:** "estimamos", "es consistente con". Con 6 eventos no se "demuestra" nada.

## 3. Stack y arquitectura

- Python 3.13 con **uv** (`uv sync`, `uv run ...`). Dependencias: pandas, pyarrow, python-calamine,
  requests, pdfminer.six, duckdb (fijado <2), dbt-duckdb, matplotlib, statsmodels; dev: ipykernel, nbconvert.
- **DuckDB**, un solo archivo `data/nox.duckdb` con schemas `bronze`, `silver`, `gold`.
  **Fijado en `duckdb>=1.5.4,<2`:** DuckDB 2.0 cambió el formato de archivo y las herramientas 1.x
  (CLI 1.5.4, drivers de DataGrip/DBeaver) no pueden abrir una base creada con 2.0.
- **dbt-duckdb** para bronze → silver → gold. Los tests de dbt son el capítulo de calidad de datos.
- Gold se exporta a **Parquet** en `export/` para Power BI y para que el equipo haga EDA en Colab.

Medallón:
- **raw** (`data/raw/`): archivos originales, inmutables.
- **landing** (`data/landing/`): CSV en formato largo que generan los scripts de `extract/`.
- **bronze**: landing cargado tal cual (idealmente todo texto) + `archivo_origen` + `fecha_carga`.
- **silver**: tipado, normalizado, con flags de calidad, más dimensiones.
- **gold**: tablas analíticas para EDA y dashboard.

## 4. Estructura del repo

```
data/            (fuera de git)
  raw/aire_publico/<ESTACION>/  PDF mensuales públicos (los baja extract/aire_publico.py)
  raw/smn/       smn_datos_meteorologicos_desde_2021.lst (TSV) + xlsx de metadatos
  raw/sube/      dat-ab-usos-<año>.csv (los baja extract/sube_descarga.py)
  landing/       aire_publico.csv (+ manifiesto), smn.csv
extract/         aire_publico.py, sube_descarga.py, smn_to_csv.py
dbt/             models/{bronze,silver,gold}, seeds/{eventos,feriados}.csv, tests/, macros/
analysis/        consultas SQL sueltas; acá van los notebooks de EDA
export/          Parquet de gold
_to_delete/      el usuario lo borra a mano (venv viejo, etc.)
```

## 5. Fuentes y particularidades (importante)

### Calidad del aire — informes públicos de la APrA (`landing/aire_publico.csv`)
Origen: páginas de las estaciones en buenosaires.gob.ar/calidad-del-aire (Parque Centenario, Córdoba,
La Boca). Un PDF mensual por contaminante y estación: `co_*`, `nox_*` (NO, NO2, NOx), `pm10_*`.
- Los links de las páginas apuntan a `buenosaires.gob.ar/sites/default/files/...`, que redirige a
  `gcaba_historico` y da 404. **Con el dominio `static.buenosaires.gob.ar` y la misma ruta descargan.**
- Página 1 = tabla diaria. Por día: promedio 24 h, promedios 0-8, 8-16 y 16-24 h, máximo y mínimo horario
  (en NOx, cada uno para NO, NO2 y NOx). CO y PM10 suelen traer una columna constante final ("2,6" o "100")
  que se descarta; algunos meses no la traen (PM10 de octubre 2024).
- pdfminer lee las planillas por columnas: el parser reconstruye la tabla por coordenadas.
- Columnas de landing: `estacion, fecha, contaminante, estadistico, valor_crudo, unidad, archivo`.
  `estadistico` ∈ {24h, 0-8, 8-16, 16-24, max_1h, min_1h}. `valor_crudo` es texto con coma decimal y valores
  especiales `s/d`, `DND`, `<4` (bajo límite de detección): se convierte en silver.
- Precisión publicada: NO/NO2/NOx en ppb enteros, CO en ppm con un decimal, PM10 en µg/m³ enteros.
- Calidad de datos encontrada: nombres inconsistentes (`la boca`, `la  boca`, `laboca`, `_0`, `corregido`,
  `centenaeio`); el PM10 de Córdoba de feb-2026 enlaza al archivo de La Boca (se descarta); el PM10 de
  La Boca de may-2025 tiene encabezado "Córdoba" pero datos de La Boca (se conserva con aviso: sus valores
  difieren del archivo de Córdoba del mismo mes).
- Faltan (igual que en la fuente): NOx de Centenario abr/may/oct-2024 y CO de Córdoba abr/may-2024.
- Unidades para OMS: NO2 ≈ 1,88 µg/m³ por ppb a 25 °C (convertir en SQL).

### SUBE (`raw/sube/dat-ab-usos-<año>.csv`, datos.transporte.gob.ar)
Una fila por línea y día: `DIA_TRANSPORTE, NOMBRE_EMPRESA, LINEA, AMBA, TIPO_TRANSPORTE, JURISDICCION,
PROVINCIA, MUNICIPIO, CANTIDAD, DATO_PRELIMINAR`. Cubre 2024-01-01 a 2026-10-25 sin días faltantes.
- **Universo "colectivos que circulan por CABA"** (134 líneas): `AMBA='SI'`, `TIPO_TRANSPORTE='COLECTIVO'`,
  `JURISDICCION IN ('NACIONAL','C.A.B.A')` (más etiquetas que empiezan con `CABA_`) y número de línea < 200.
  **No** filtrar `PROVINCIA='BUENOS AIRES'`: eso excluye justamente CABA.
- `NACIONAL` → `PROVINCIA='JN'`, `MUNICIPIO='SD'`: líneas interjurisdiccionales y, hasta el traspaso, las solo-CABA.
  Las 31 líneas solo-CABA pasan a `JURISDICCION='C.A.B.A'` desde **2025-01-20**.
- **La clave de línea es el número**, extraído con regex `(\d+)\s*$` sobre `LINEA`, sumando variantes por día.
  Variantes reales: `LINEA 12` → `CABA_LINEA_12`; `BSAS_LINEA_026` → `CABA_LINEA_26`; espacios (`CABA_LINEA_ 42`);
  cambio de operador (25: `CABA_LINEA_25` → `CABA_LINEA_025` en ene-2026; 4: `CABA_LINEA_4` → `CABA_LINEA_04` en may-2025);
  superposición de etiquetas fines de ene/principios de feb 2025.
- Jurisdicción mal cargada: `CABA_LINEA_6` como MUNICIPAL (1-7 may 2025), `CABA_LINEA_23` como PROVINCIAL,
  `CABA_LINEA_99` como NACIONAL (feb 2026). Excluir líneas `8012`-`8188` (solo 8-28 may 2024, volúmenes mínimos).
- `DATO_PRELIMINAR='SI'` desde feb 2026.
- **Dosis de un evento:** una línea "paró" si sus usos < 15% de la mediana del mismo día de semana
  (±3 semanas, solo días normales, base > 2000 usos). % ponderado por usos de base.
  Limitación: SUBE mide pasajeros, no colectivos en calle ni km dentro de CABA.

### Meteostat — DESCARTADO
Se usó en una primera versión (viento y temperatura horarios). Comparado con el SMN diario sobre datos públicos:
R² casi iguales (NOx/CO 0,50 vs 0,50; NOx 0,45 vs 0,46; NO2 0,55 vs 0,58), el viento correlaciona 0,81
y los percentiles del placebo son prácticamente idénticos. Se sacó para tener una sola fuente oficial
y no depender de 3 GB de parquet. Limitación a declarar: viento promedio de 24 h, no de la ventana 8-16 h.

### SMN diario (`landing/smn.csv`)
Columnas: `estacion, fecha, metrica, valor, unidad`. 2021-01-01 a 2026-07-31. Aeroparque y Observatorio.
Origen: SMN, "Descarga de datos" (https://www.smn.gob.ar/descarga-de-datos), datos diarios 2021-2026.
Hay que aceptar términos y condiciones; el enlace descarga un zip con el `.lst`: https://ssl.smn.gob.ar/dpd/zipopendata.php?dato=datosdiarios20212026
La descarga es manual (no hay script): el zip se descomprime en `data/raw/smn/`.
Es la ÚNICA fuente meteorológica del pipeline (viento, temperatura, humedad y lluvia).
Métricas: HELIOF, HUM_REL, NUB_TOT, PRECIP, PRE_EST, TMAX, TMEDIA, TMIN, VEL_MED, VTO_MDIR, VTO_MVEL.
- `PRECIP` solo tiene ~120 registros/año por estación (388 en cero): se asumió faltante = sin lluvia (**verificar**).
- `VTO_MDIR` en decenas de grado (×10); es la dirección del viento máximo, no la dirección media.

### Días normales
Día hábil normal = usos SUBE de colectivo, subte y tren > 0,9 × mediana del mismo día de semana (±4 semanas).
Excluye feriados, puentes, vacaciones de invierno y paros sin necesidad de calendario externo
(igual conviene un seed de feriados para el dashboard).

## 6. Eventos (`dbt/seeds/eventos.csv`)

| fecha | evento | grupo | % líneas paradas CABA |
|---|---|---|---|
| 2024-04-11 | Paro UTA | sin_colectivos | 67 |
| 2025-05-06 | Paro UTA (con lluvia ~10 mm) | sin_colectivos | 63 |
| 2024-05-09 | Paro general CGT | sin_colectivos | 68 |
| 2026-02-19 | Paro general CGT | sin_colectivos | 67 |
| 2025-04-10 | Paro general, colectivos funcionando (día muy ventoso) | control | 0 |
| 2024-10-30 | Paro de trenes y subte | control | 0 |

Descartados por no verse en SUBE: 2024-07-05, 2025-03-28. El 2024-01-24 fue un corte solo desde las 19 h.

## 7. Método del análisis de eventos

Detalle en `analysis/05_eventos.ipynb`: promedio del bloque `8-16` por estación y día, regresión OLS
sobre los días hábiles normales (`log(contaminante) ~ log(max(viento, 2)) + temperatura + lluvia + estación
+ mes + año + día de semana`, meteorología del SMN diario), desvío del evento = residuo y prueba placebo
(percentil del residuo frente a los días normales).

## 8. Próximos pasos

1. HECHO (calidad del aire): proyecto dbt en `dbt/` (correr desde `dbt/` con `--profiles-dir .`; la raíz se
   puede cambiar con la variable NOX_RAIZ). Schemas bronze/silver/gold vía macro `generate_schema_name`.
   Modelos: `bronze_aire`, `bronze_aire_manifiesto`, `silver_aire` (estado_valor, fuera_de_rango, valor_masa),
   `dim_calendario` (tipo_dia con seed `feriados` de la API ArgentinaDatos, evento), `gold_aire_diario`
   (estación × día, bloque 8-16, NOx/CO, 24 h en µg/m³). Tests: claves únicas, accepted_values y tests de
   coherencia física en `tests/` (warn: 196 casos NOx ≠ NO+NO2 > 2 ppb; La Boca 29/02/2024 NOx 8-16 = 0
   con mínimo horario 15). PM10 "<4" no entra a gold (se podría imputar LD/2).
   Flags de silver_aire: `nox_incoherente` (|NOx − (NO+NO2)| > 2), `fuera_de_max_min` (bloque fuera del
   rango horario del día) y `cero_sin_respaldo` (promedio 0 con máximo horario 0 o faltante: 29/02/2024 y
   Centenario 01/08/2026); gold excluye esas filas y el test `gold_aire_nox_co_positivo` es error.
2. HECHO (SUBE y meteorología): `bronze_sube`, `bronze_smn`; `silver_sube`,
   `silver_colectivos_caba_linea_dia` (universo CABA, número de línea), `silver_sube_actividad_diaria`
   (`es_dia_normal`: hábil, no feriado y colectivo/tren/subte > 0,9 × mediana ±4 semanas; 564 días),
   `silver_smn_diario`; `gold_sube_diario` (dosis ponderada:
   67/68/63/67 en los paros, 0 en controles; `actividad_colectivo_vs_habil` comparable entre tipos de día),
   `gold_meteo_diario` (solo SMN diario: viento, temperatura y humedad promedio de las 2 estaciones,
   lluvia = máximo; llega hasta el último dato SMN, 2026-07-31) y **`gold_analitico`** (estación × día, 2950 filas): LA tabla del análisis.
   Test `eventos_coherentes_con_sube` (error): paros ≥ 50% de dosis, controles ≤ 5%.
   Último build: PASS=56 WARN=2 ERROR=0.
   Gradiente para el EDA (actividad vs. NOx/CO media geométrica 8-16): hábil 0,97/114 · sábado 0,59/96 ·
   control 0,73/91 · feriado 0,38/81 · domingo 0,34/73 · sin colectivos 0,21/66.
   Feriados y fines de semana entran al EDA como gradiente, NO a la base de la regresión ni del placebo.
3. HECHO en `analysis/05_eventos.ipynb` (ver punto 5). Análisis en Python sobre `gold_analitico`: regresión OLS (días normales) + placebo para NOx/CO, NOx,
   CO, NO2 y PM10 en el bloque 8-16; sensibilidad con promedios 24 h. Escribe `gold_resultados_evento`.
   Plan B si no se sostiene: comparar contra semanas vecinas excluyendo días ventosos o con lluvia.
4. HECHO: `run.py` encadena extract (con `--extraer`) → `dbt build` → export a `export/*.parquet`
   (gold_analitico, gold_aire/sube/meteo_diario, dim_calendario, eventos). dbt no es un orquestador.
5. EDA en `analysis/` (notebooks que leen `export/*.parquet`, corren local o en Colab):
   HECHO `01_eda_aire` (cobertura, descriptivas, log, OMS, estacionalidad, ciclo semanal, atípicos) y
   `04_bivariado` (gradiente por tipo de día con índice dentro de cada estación, actividad vs. NOx/CO,
   viento, eventos sin ajustar). Hallazgo clave: en paros sin colectivos NOx −32%, CO +16%, NOx/CO −43%
   (domingo −36%). HECHO `05_eventos`: OLS en ~520 días normales (R² NOx/CO 0,50; validación cruzada 10
   partes para los desvíos de días normales), percentil placebo por estación y placebo de grupo sorteando
   días normales completos (5.000). Paros sin colectivos: NOx/CO −43% (p < 0,0002), NOx −28%, NO2 −23%,
   CO +7% (normal), PM10 sin efecto; controles NOx/CO −10% (p 0,2). Robusto a sacar un paro (−36 a −56%) y
   a usar 24 h (−44%). Escribe `export/resultados_evento.parquet` y `resultados_grupo.parquet`; el 04 escribe
   `indice_tipo_dia.parquet`. `run.py --analisis` ejecuta los notebooks. HECHO `02_eda_sube` (universo, demanda,
   día normal = 82% de los hábiles, dosis 63-68% en paros y 0% en controles, catálogo completo: fuera de los 4 paros
   solo Navidad/Año Nuevo y 07/03/2024 con 7%) y `03_eda_meteo` (64% de días sin registro de lluvia, totales
   anuales ≈1.450-1.700 mm → supuesto razonable; VIF ≈ 1,1; eventos ventosos: 11/04/24, 19/02/26 y 10/04/25 en
   P84-88 del viento de su mes). La dosis de `gold_sube_diario` es nula en sábados y domingos (antes daba 0).
   A revisar: Córdoba 19/02/2026 con NOx +66% y CO +110% sobre lo esperado.
   A revisar: Córdoba 23/05/2026 NOx 8-16 = 492 ppb con viento normal.
6. Dashboard Power BI sobre los Parquet: guía en `powerbi/README.md` (modelo estrella, medidas DAX, 5 páginas)
   y tema `powerbi/tema_nox.json`. Falta armarlo (Power BI Desktop, Windows).

Reparto propuesto: Ezequiel → calidad del aire, ETL y análisis de eventos; compañero 1 → EDA SUBE y eventos;
compañero 2 → EDA meteorología y calendario; compañero 3 → dashboard. Cada uno presenta su parte.

## 9. Pendientes de verificar

- Fuente de prensa de los eventos 2024-04-11 y 2024-10-30 (en el seed dice "a completar").
- Si los camioneros adhirieron a cada paro general.
- Fecha real de los 150 colectivos a GNC de las líneas 65 y 151 (Grupo Metropol): ¿antes del 2026-02-19?
- Si los días sin `PRECIP` en el SMN son realmente sin lluvia.

## 10. Antecedentes (para la diapositiva de contexto)

- Bauernschuster, Hener y Rainer (2017), AEJ: Economic Policy: paros de transporte público en Alemania → +PM10 14%.
- Basagaña, Querol y otros (2017), Science of the Total Environment: Barcelona, paros → NO2 +4%, NO +8% (metro hasta +48% NO).
- González, Perdiguero y Sanz (2021), Transportation Research D: Barcelona; paros de colectivos sin efecto en NOx a nivel ciudad, CO +12%.
- Krecl y otros (2020), Environmental Pollution: paro de camioneros en San Pablo 2018 → NOx −40 a −70%.
- McDonald y otros (2013), ES&T: la nafta domina el CO; el diésel, una parte creciente del NOx.
Contraste clave: en Europa los paros de transporte público aumentan la contaminación (más autos); acá el
cociente NOx/CO baja cuando desaparece el diésel.
