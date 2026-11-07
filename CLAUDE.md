# CLAUDE.md · nox-ciudad

Contexto para seguir el proyecto en Claude Code. Idioma de trabajo: español rioplatense. El usuario es data engineer
con experiencia en monitoreo atmosférico: comunicación directa, sin vueltas.

## Qué es

TP integrador de **Análisis de Datos** (Licenciatura en Ciencia de Datos). Equipo de 4. Pregunta: ¿cuán lejos está
el aire de la Ciudad de Buenos Aires de las guías de la OMS 2021, y cómo varía entre estaciones, contaminantes, tipo
de día y período? La referencia es la **consigna de la cátedra** (PDF "Trabajo Práctico Integrador", fuera del repo):
10 etapas (problema e hipótesis, dataset, modelado, SQL, limpieza y calidad, ETL, EDA en Python, visualizaciones e
indicadores, dashboard en **Power BI**, conclusiones), exposición grupal de 20 minutos y poder justificar cada
decisión técnica. El README tiene la tabla "Cómo cubre el TP la consigna". La guía `PROYECTO_TP_AIRE_OMS.md`, que
venía de otro chat, se sacó del repo: no es la consigna.

Hipótesis (reescritas por el equipo como expectativas previas al análisis, sin detalles que solo se saben después):
- **H1:** el NO₂ es el contaminante más crítico: el que más se aleja de las guías de la OMS. → Se sostiene (50-95% de días sobre la guía vs. 2-4% del PM10 y 0% del CO).
- **H2:** Córdoba, la estación ubicada sobre una avenida de tránsito intenso, es la más comprometida en NO₂. → **No se sostiene**: la peor es La Boca (flujo medio-bajo, fuentes fijas); Córdoba es segunda. La serie larga muestra que es reciente.
- **H3:** domingos y feriados la brecha se reduce de forma visible. → A medias (el perfil horario muestra las horas pico).
La matriz de escalones (hasta qué IT cumple cada estación) ya no es una hipótesis: responde las subpreguntas 1 y 2.
Fundamentación (README, "De dónde salen las hipótesis", con fuentes): premisa común "el NO₂ de la Ciudad viene sobre
todo del tránsito" (Bogo et al. 1999) aplicada a cada corte. H1: la OMS 2021 endureció el NO₂ anual 4 veces (40→10)
y el PM10 poco (20→15, 50→45). H2: la APrA describe a Córdoba con flujo vehicular alto y a La Boca medio-bajo con
fuentes fijas; en Europa las superaciones de NO₂ son en estaciones de tránsito (EEA). H3: efecto fin de semana
(Beirle et al. 2003). El período no tiene hipótesis (sin meteorología no hay base). Resultado conjunto: el tránsito
explica buena parte del NO₂, pero no todo.

Versión anterior del repo (paros de transporte, SUBE, meteorología del SMN, Looker Studio): **descartada** en
noviembre 2026 para simplificar. Está en la historia de git (hasta el commit `82aec79`). Después, la fuente pasó de
los informes mensuales en PDF de la APrA (extraídos con pdfminer, hasta el commit `e34af3c`) al **CSV horario de BA
Data**: más crudo, sin extracción de PDF. El usuario trabaja en la agencia que carga esos datos.

## Reglas

- **Explicable antes que sofisticado.** Cualquier integrante tiene que poder explicar todo. Nada de orquestadores,
  ML ni infraestructura extra.
- **No se borran filas:** se marcan (flags, `motivo_sin_dato`, `es_outlier`). La limpieza vive en SQL (dbt).
- **Umbrales en tablas** (`data/reference/`, variables de `dbt_project.yml`), nunca escritos en el SQL.
- Código, comentarios y documentación en español; identificadores en snake_case sin tildes.
- Rutas relativas a la raíz (`src/config.py`); dbt se corre siempre desde `dbt/` y llega a los archivos con `../`.
- Lenguaje de resultados: "es consistente con", "estimamos"; sin meteorología no se atribuyen causas.

## Stack y comandos

Todo el equipo usa Windows: no hay Makefile, los comandos van con `.venv\Scripts\python`.
Python 3.11+ con `requirements.txt`. DuckDB **fijado <2** (DuckDB 2 cambió el formato de archivo y
las herramientas 1.x no lo abren). dbt-duckdb. pandas, matplotlib, seaborn, sweetviz, ydata-profiling, pytest. Sin pdfminer, requests
ni pyarrow (la descarga usa urllib; `data/final` es solo CSV).
El EDA tiene un perfil automático con Sweetviz (`reports/sweetviz_*.html`, layout vertical, sin logo, columnas en
castellano con unidad) y gráficos con seaborn (boxplot, histograma, barras y líneas con IC 95%, heatmap) y matplotlib.
Sweetviz se corre dentro de `plt.style.context("default")`: con el estilo del notebook (200 dpi, bbox tight) sus
imágenes salen más grandes de lo que espera su HTML y se pisan con el texto; el bloque además deshace el cambio de
fuentes que hace Sweetviz. Se revisaron con capturas de Chromium/Playwright.
ydata-profiling 4.18 (`reports/ydata_perfil.html`, sección 1.2 del notebook): pide pandas < 3 (por eso el entorno quedó
en pandas 2.3, numpy 2.3, matplotlib 3.10) y `setuptools<82` (usa `pkg_resources`). Manda estadísticas de uso a
packages.ydata.ai: se desactiva con `YDATA_PROFILING_NO_ANALYTICS=True` antes de importarlo. Al importarse avisa que
sigue como `fg-data-profiling`; no se instaló (sin verificar). Correlaciones: Spearman (las distribuciones tienen
asimetría positiva; NO₂ moderada, 0,45-1,08 por estación), Pearson para comparar, V de Cramér; alerta de asimetría
desde 1. Con pandas 2, `leer()` del notebook pasa a booleana `supera_guia` (viene vacía en los días sin dato).

- `python -m src.etl`: verifica el crudo → `dbt build` (en subproceso, desde `dbt/`) → export de gold a `data/final/`
  (solo CSV, `order by all` para que sea idempotente) → corre `sql/99` (solo lectura) → genera
  `docs/diccionario_datos.md`.
- `python -m pytest -q`: 4 tests de pytest (~20 s). División: **dbt prueba los datos; pytest, el código y el pipeline**
  (idempotencia, `sql/99` corre en conexión de solo lectura, verificación de formato del extractor). No duplicar tests de datos en pytest. El
  EDA se ejecuta con `python -m jupyter nbconvert --to notebook --execute --inplace notebooks/eda.ipynb`.
- `python -m src.generar_pbip`: genera `dashboard/AireOMS.pbip` (modelo TMDL con las 8 tablas de gold + `_Medidas`,
  10 relaciones, 18 medidas DAX, orden de columnas, lat/long como categoría de mapa, descripciones de dbt, tema;
  informe PBIR con 3 páginas vacías; lee los CSV con configuración regional en-US).
  Validado con TmdlSerializer (paquete NuGet Microsoft.AnalysisServices.NetCore.retail.amd64; la salida es idéntica a
  su reserialización) y con los esquemas de microsoft/json-schemas, también después del cambio a medallón; no se
  abrió en Power BI Desktop. Lee los CSV con `Csv.Document` + tipos en-US. El tema base
  `src/recursos/Fluent2-CY26SU08.json` viene de microsoft/fabric-toolbox (MIT); el tema propio está en
  `src/recursos/powerbi_tema.json`. No regenera si ya hay gráficos.
- `python -m src.extract`: baja `calidad-aire.csv` de la CDN de BA Data
  (`cdn.buenosaires.gob.ar/datosabiertos/datasets/agencia-de-proteccion-ambiental/calidad-aire/`), con reintentos, y
  verifica el encabezado. Desde la nube de Claude funciona con `cdn.buenosaires.gob.ar` en los hosts permitidos del
  entorno; `data.buenosaires.gob.ar` (la página del dataset) corta la conexión. El CSV crudo está en git.

## Datos

- `data/raw/calidad-aire.csv`: dataset "Calidad del aire" de BA Data, tal como se publica (8,5 MB, UTF-8 con BOM).
  Ancho: 147.470 filas fecha × hora (2009-10-01 a 2026-10-26), columnas `FECHA` (`12FEB2011:00:00:00`), `HORA` (1-24
  = hora que termina; trae algunas 0 y >24) y `CO_/NO2_/PM10_` × `CENTENARIO/CORDOBA/LA_BOCA/PALERMO` (Palermo
  vacía, desactivada en 2010). **NO2 = promedio horario (ppb); CO = móvil de 8 h (ppm); PM10 = móvil de 24 h
  (µg/m³)** (según `contaminantes.csv` de BA Data). Especiales: `s/d`, `S/d`, vacío, `<0.05` (CO 2010-2017),
  `#REF!` (17-18/05/2024 y 2020), `x/d`. Los archivos anuales del portal (`calidad_aire_2025.csv`...) son un
  subconjunto idéntico.
- `data/reference/`: `oms_2021.csv` (Tabla 0.1 del resumen ejecutivo OMS 2021), `contaminantes.csv` (peso molecular,
  `promedio_fuente`, `maximo_plausible`: NO2 500, PM10 1000, CO 15), `estaciones.csv` (coordenadas de
  `estaciones-ambientales.csv` de BA Data), `feriados.csv` (ArgentinaDatos). `eventos.csv` (paros) se sacó: no se usaba.
- En git: crudo, referencias y `data/final/`. Fuera de git: `data/warehouse/`.

## Modelo (dbt, `data/warehouse/aire.duckdb`): arquitectura medallón

Simplificado en noviembre 2026 (antes: 6 schemas y 21 modelos). Tres schemas = tres carpetas de `dbt/models/`:
- `bronze`: `calidad_aire` (el CSV con `read_csv(all_varchar)`, sin tocar) + seeds `oms_2021`, `contaminantes`,
  `estaciones`, `feriados`.
- `silver`: `medicion_horaria` (UNPIVOT a largo, tipos, reglas por hora, `motivo_invalido`, toda la serie: 1.327.230
  filas = CSV × 9) y `medicion_diaria` (valor diario de toda la serie).
- `gold` (lo único que se exporta a `data/final`): `dim_calendario`, `dim_estacion`, `dim_contaminante`, `guia_oms`
  (OMS en largo, una fila por nivel), `fact_medicion_diaria`, `fact_medicion_horaria`, `agg_anual` (por año
  2010-2026 + `movil_12m`: regla del 75%, promedio anual y escalón, P99, % de días por escalón, racha máxima;
  `es_periodo_estudio` separa estudio de contexto) y `calidad_resumen`. La completitud mensual se calcula de la fact.
`sql/99` son solo consultas (21, no crea vistas).
Columnas revisadas una por una en noviembre 2026 (gold: 120 → 91): sin columnas que no use nadie (SQL, notebook,
PBIP, spec o tests); las unidades solo en `dim_contaminante` y las guías solo en `guia_oms` (las facts no las repiten);
sin el criterio trimestral de la EPA (la tabla de sensibilidad de `calidad_datos.md` §3.4 quedó como verificación
hecha una vez). Se dejaron a propósito, aunque nada las lea: `entorno`, `flujo_vehicular`, `fuentes_fijas` (base de
H2) y `descripcion` en las dimensiones.

- Reglas por hora: hora_invalida, sin_dato_fuente, texto_invalido, fuera_de_rango, fila_en_cero, valor_trabado
  (NO2 igual ≥ 10 h). `<x` → x/2 (queda marcado en `estado_valor = 'bajo_limite_deteccion'`).
- Valor diario: NO2 = promedio con ≥ 18 de 24 horas válidas (`horas_minimas_dia`, criterio UE); PM10 = móvil de la
  hora 24; CO = promedio de las horas 8, 16 y 24. Coincide con los PDF de la APrA en 94% (NO2), 97% (CO) y 98%
  (PM10) de los días; ±1 unidad: 98,8-99,6%.
- Fact diaria: grilla completa, 1.004 × 3 × 3 = 9.036 filas, sin ventanas; `motivo_sin_dato` = sin_fila,
  sin_dato_fuente o incompleto; `n_horas_validas`. Fact horaria: solo NO2, 70.704 filas.
- Outliers: Q3 + 3·IQR por estación × contaminante, marcados.
- Regla del 75% sobre días por período (`agg_anual.id_periodo`: años, 2026 parcial, `movil_12m`).
- Rachas: un día con dato bajo la guía corta; huecos sin dato de hasta 7 días (`dias_hueco_maximo_racha`) no cortan.
- Contexto 2010-2025: filas de `agg_anual` con `es_periodo_estudio = false`, misma regla del 75%.
- Último build: 11 modelos, 4 seeds, 87 tests: PASS 101, WARN 1 (`silver_valores_descartados`, esperado: 239).

## Resultados verificados

- % días NO₂ > 25 µg/m³: La Boca 95,0% (900 d), Córdoba 85,6% (864), Centenario 54,9% (676). PM10 > 45: 2,4-4,1%.
  CO: 0%. Denominador = días con dato (dividir por todas las filas daría 37% en Centenario).
- NO₂ últimos 12 meses: La Boca 45,9 (4,6×, > IT1), Córdoba 35,1 (3,5×, IT1), Centenario 26,3 (2,6×, IT2).
  La Boca 2024: 56,5. PM10: 21,7-26,4 (1,4-1,8×, IT3); P99 de PM10 ≥ 45 en todas las estaciones y años.
- Días que cumplen el IT2 diario de NO₂ (50): Centenario 98,5%, Córdoba 87,6%, La Boca 50,0%. IT1 diario (120):
  todos salvo uno (La Boca 12/07/2024, 124). Matriz por año: La Boca 40% → 53% → 59%; Córdoba 83-92%; Centenario 98-100%.
- No válidos por el 75%: NO₂ Centenario 2024 (18,9%: la estación no midió de marzo a noviembre), CO Córdoba 2024 (61,5%).
- Racha máxima NO₂: La Boca 254 días con dato (14/02 a 28/11/2024; 289 de calendario, 35 sin dato) y 206 en 2025;
  Córdoba 111; Centenario 26.
- Domingo vs. hábil (NO₂): −26% Centenario, −21% Córdoba, −17% La Boca; 90% de los domingos de La Boca sobre la guía.
  Perfil horario: máximo a las 19-20 h; a las 9 h el hábil tiene 27% a 75% más que el domingo; piso de madrugada de
  La Boca 43 µg/m³ (otras 17-24).
- Invierno/verano NO₂ La Boca: 62,4 vs. 34,8 µg/m³.
- Ene-sep NO₂: 26,0 → 20,7 → 18,9 ppb juntando estaciones (−27%), inflado por falta de Centenario en 2024 (40 días).
  Por estación: La Boca −20%, Córdoba −13%, Centenario plano.
- Contexto 2010-2025 (NO₂ anual válido): Córdoba 68 (2012) → 32-45 desde 2015; Centenario 28-36; La Boca irregular
  (20-24 en 2015-16, ~40 en 2017-19, 24-32 en 2021-22, 50-57 en 2024-25). Ningún año cumple la guía de 10.
- Calidad del período: 87,8% de valores horarios válidos, 11,9% s/d, 0,3% descartados (#REF!, hora 0, fila en cero,
  CO 23 ppm en La Boca el 01/06/2026, NO2 −2).

## Pendiente

- Abrir `dashboard/AireOMS.pbip` en Power BI Desktop (parámetro `RutaDatos` con la ruta local de `data/final\`,
  Actualizar) y armar los gráficos de las 3 páginas siguiendo `docs/powerbi_spec.md` (lo hace el equipo). Después
  de armar gráficos, el modelo se toca desde Power BI, no con `src.generar_pbip`.
- Preguntar a la APrA por los saltos de la serie larga de La Boca (¿cambios de equipo, calibración o fuentes?).
- Preparar la presentación (guion en el README).
