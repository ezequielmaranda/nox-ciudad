-- =====================================================================================================
-- CONSULTAS DE ANÁLISIS
-- ¿Cuán lejos está el aire porteño de las guías de la OMS (2021)?
--
-- Se corren sobre la base que arma el ETL (data/warehouse/aire.duckdb), por ejemplo desde DBeaver,
-- la CLI de DuckDB (`duckdb data/warehouse/aire.duckdb < sql/99_consultas_analisis.sql`) o Python.
-- El ETL las ejecuta todas al final de cada corrida, así que si alguna se rompe, el ETL avisa.
--
-- Cada consulta tiene un encabezado con:
--   PREGUNTA  qué subpregunta del TP responde
--   POR QUÉ   por qué hace falta
--   TÉCNICA   qué herramienta de SQL muestra
--
-- Schemas de la base:  staging (crudo tipado) · modelo (dimensiones y fact) · calidad · indicadores
--                      analisis (las vistas que se crean al final de este archivo)
-- Funciones propias de DuckDB (comentadas donde aparecen): FILTER, quantile_cont, fecha - entero.
-- =====================================================================================================


-- =====================================================================================================
-- PARTE A · PERFILADO Y CALIDAD (antes de analizar, saber con qué datos contamos)
-- =====================================================================================================

-- A1 · Tamaño y cobertura del crudo
-- PREGUNTA  ¿Cuántos datos hay, de cuándo a cuándo y de cuántas estaciones?
-- POR QUÉ   Es la "ficha" del dataset: lo primero que se presenta.
-- TÉCNICA   SELECT con funciones de agregación (COUNT, COUNT DISTINCT, MIN, MAX).
SELECT
    count(*)                    AS valores_crudos,
    count(DISTINCT id_estacion) AS estaciones,
    count(DISTINCT id_contaminante) AS contaminantes,
    min(fecha)                  AS desde,
    max(fecha)                  AS hasta,
    count(DISTINCT archivo_pdf) AS pdf_de_origen
FROM staging.stg_aire;


-- A2 · Nulos y valores especiales por contaminante
-- PREGUNTA  ¿Qué proporción de las celdas de los PDF no es un número válido?
-- POR QUÉ   's/d', '<4' o texto suelto no se pueden promediar: hay que saber cuántos son.
-- TÉCNICA   GROUP BY + función de ventana (SUM ... OVER) para el porcentaje dentro de cada grupo.
SELECT
    id_contaminante,
    estado_valor,
    count(*) AS n,
    round(100.0 * count(*) / sum(count(*)) OVER (PARTITION BY id_contaminante), 2) AS pct
FROM staging.stg_aire
GROUP BY id_contaminante, estado_valor
ORDER BY id_contaminante, n DESC;


-- A3 · Duplicados
-- PREGUNTA  ¿Hay más de un valor para la misma estación, fecha, contaminante y estadístico?
-- POR QUÉ   Un duplicado contaría dos veces el mismo día en los promedios. Resultado esperado: 0 filas.
-- TÉCNICA   GROUP BY + HAVING.
SELECT id_estacion, fecha, id_contaminante, estadistico, count(*) AS repeticiones
FROM staging.stg_aire
GROUP BY id_estacion, fecha, id_contaminante, estadistico
HAVING count(*) > 1;


-- A4 · Días faltantes: calendario completo + LEFT JOIN
-- PREGUNTA  ¿Qué días no publicó la fuente, por estación y contaminante?
-- POR QUÉ   Un día sin fila no aparece en un GROUP BY común: hay que generar todos los días posibles
--           y ver cuáles no tienen pareja. Distingue "no hay fila" de "hay fila con s/d".
-- TÉCNICA   CROSS JOIN (todas las combinaciones) + LEFT JOIN + filtro IS NULL (anti-join).
WITH esperado AS (
    SELECT c.fecha, e.id_estacion, k.id_contaminante
    FROM modelo.dim_calendario c
    CROSS JOIN modelo.dim_estacion e
    CROSS JOIN modelo.dim_contaminante k
),
publicado AS (
    SELECT DISTINCT id_estacion, fecha, id_contaminante
    FROM staging.stg_aire
    WHERE estadistico = '24h'
)
SELECT
    x.id_estacion,
    x.id_contaminante,
    count(*)     AS dias_sin_fila,
    min(x.fecha) AS primer_dia_faltante,
    max(x.fecha) AS ultimo_dia_faltante
FROM esperado x
LEFT JOIN publicado p
    ON p.id_estacion = x.id_estacion AND p.fecha = x.fecha AND p.id_contaminante = x.id_contaminante
WHERE p.fecha IS NULL
GROUP BY x.id_estacion, x.id_contaminante
ORDER BY dias_sin_fila DESC;


-- A5 · Completitud por estación × contaminante × año y regla del 75%
-- PREGUNTA  ¿Qué indicadores anuales se pueden calcular y cuáles no? (subpregunta 6)
-- POR QUÉ   Un promedio anual con la mitad de los días puede estar sesgado (p. ej. si falta el invierno).
-- TÉCNICA   GROUP BY + COUNT con condición (COUNT(CASE WHEN ...)) + CASE para clasificar.
SELECT
    f.id_estacion,
    f.id_contaminante,
    c.anio,
    count(*)                                         AS dias_calendario,
    count(CASE WHEN f.tiene_dato THEN 1 END)         AS dias_con_dato,
    round(100.0 * count(CASE WHEN f.tiene_dato THEN 1 END) / count(*), 1) AS completitud_pct,
    CASE
        WHEN count(CASE WHEN f.tiene_dato THEN 1 END) >= 0.75 * count(*) THEN 'válido'
        ELSE 'NO válido (< 75%)'
    END                                              AS regla_75
FROM modelo.fact_medicion_diaria f
JOIN modelo.dim_calendario c ON c.fecha = f.fecha
WHERE f.ventana = '24h'
  AND f.id_contaminante IN ('no2', 'pm10', 'co')
GROUP BY f.id_estacion, f.id_contaminante, c.anio
ORDER BY f.id_contaminante, f.id_estacion, c.anio;


-- A6 · Qué descartaron las reglas de calidad
-- PREGUNTA  ¿Cuántos valores se descartaron por cada regla y en qué contaminante?
-- POR QUÉ   Mostrar que la limpieza es acotada y explicable (no se "tiraron datos" a ciegas).
-- TÉCNICA   Agregación condicional con FILTER (estándar SQL; en motores sin FILTER: SUM(CASE ...)).
SELECT
    regla,
    count(*)                                         AS violaciones,
    count(*) FILTER (WHERE se_descarta)              AS descartadas,
    count(*) FILTER (WHERE id_contaminante = 'no2')  AS en_no2,
    count(*) FILTER (WHERE id_contaminante = 'no')   AS en_no,
    count(*) FILTER (WHERE id_contaminante = 'nox')  AS en_nox
FROM calidad.calidad_violaciones
GROUP BY regla
ORDER BY violaciones DESC;


-- A7 · El "día 8": dónde se concentran las incoherencias de NOx
-- PREGUNTA  ¿Las incoherencias NOx ≠ NO + NO2 están repartidas al azar o tienen un patrón?
-- POR QUÉ   Un patrón (siempre el mismo día del mes) sugiere un problema de carga en la fuente y
--           justifica descartar el NO de esos días sin tocar el NO2.
-- TÉCNICA   Función de fecha (day) + GROUP BY + ORDER BY + LIMIT.
SELECT
    day(fecha)                                        AS dia_del_mes,
    count(*) FILTER (WHERE regla = 'nox_incoherente') AS incoherencias_nox,
    count(*) FILTER (WHERE regla = 'valor_trabado')   AS valores_trabados
FROM calidad.calidad_violaciones
GROUP BY day(fecha)
ORDER BY incoherencias_nox DESC
LIMIT 5;


-- =====================================================================================================
-- PARTE B · CUÁN LEJOS ESTAMOS DE LA OMS
-- =====================================================================================================

-- B0 · ¿En qué escalón de la OMS cae cada día?
-- PREGUNTA  Subpregunta 1 y H1: ¿hasta qué objetivo intermedio cumple el NO2 (y el PM10) día a día?
-- POR QUÉ   La guía es muy exigente; los objetivos intermedios (IT) miden en qué escalón se está. H1 dice
--           que la mayoría de los días se cumple el IT2 diario del NO2 (50 µg/m³).
-- TÉCNICA   GROUP BY + dos funciones de ventana: el % de cada nivel (SUM ... OVER PARTITION) y el %
--           ACUMULADO de días que cumplen ese nivel o uno más exigente (SUM ... OVER ... ORDER BY ...
--           ROWS UNBOUNDED PRECEDING). En la fila IT2 del NO2, el acumulado es el % de días que cumple el IT2.
SELECT
    id_contaminante,
    id_estacion,
    nivel_oms,
    count(*) AS dias,
    round(100.0 * count(*) / sum(count(*)) OVER (PARTITION BY id_contaminante, id_estacion), 1) AS pct_dias,
    round(100.0 * sum(count(*)) OVER (PARTITION BY id_contaminante, id_estacion ORDER BY orden_nivel_oms
                                      ROWS UNBOUNDED PRECEDING)
                / sum(count(*)) OVER (PARTITION BY id_contaminante, id_estacion), 1) AS pct_cumple_este_nivel_o_mejor
FROM indicadores.agg_cumplimiento_diario
WHERE id_contaminante IN ('no2', 'pm10')
GROUP BY id_contaminante, id_estacion, nivel_oms, orden_nivel_oms
ORDER BY id_contaminante, id_estacion, orden_nivel_oms;


-- B0b · Matriz de escalones: % de días que cumplen cada nivel, por estación y año (NO2)
-- PREGUNTA  Subpreguntas 1, 2 y 3 y H1: ¿hasta qué escalón cumple cada estación, año por año?
-- POR QUÉ   Es la tabla que va a la presentación: muestra en una sola vista la guía, los objetivos
--           intermedios y el escalón del promedio anual. Celdas vacías = período con menos de 75% de días.
-- TÉCNICA   "Pivot" con agregación condicional (MAX ... FILTER): las filas de nivel pasan a columnas.
--           LEFT JOIN con agg_anual para sumar el escalón del promedio anual.
SELECT
    e.nombre                                                                         AS estacion,
    p.etiqueta                                                                       AS periodo,
    round(100 * max(n.pct_dias_cumple) FILTER (WHERE n.nivel = 'AQG'), 1)             AS pct_cumple_guia_25,
    round(100 * max(n.pct_dias_cumple) FILTER (WHERE n.nivel = 'IT2'), 1)             AS pct_cumple_it2_50,
    round(100 * max(n.pct_dias_cumple) FILTER (WHERE n.nivel = 'IT1'), 1)             AS pct_cumple_it1_120,
    max(a.nivel_oms)                                                                 AS escalon_promedio_anual,
    bool_and(n.cumple_criterio_trimestral)                                           AS todos_los_trimestres_75
FROM indicadores.agg_cumplimiento_niveles n
JOIN modelo.dim_estacion e ON e.id_estacion = n.id_estacion
JOIN modelo.dim_periodo p  ON p.id_periodo = n.id_periodo
LEFT JOIN indicadores.agg_anual a
       ON a.id_estacion = n.id_estacion AND a.id_contaminante = n.id_contaminante AND a.id_periodo = n.id_periodo
WHERE n.id_contaminante = 'no2'
GROUP BY e.nombre, p.etiqueta, p.orden
ORDER BY e.nombre, p.orden;


-- B1 · % de días por encima de la guía diaria (24 h)
-- PREGUNTA  Subpregunta 1: ¿qué porcentaje de días se supera la guía diaria, por estación y contaminante?
-- POR QUÉ   Es el indicador más fácil de comunicar ("9 de cada 10 días").
--           Denominador = días CON DATO (no todos los días): un día sin dato no es un día "limpio".
-- TÉCNICA   JOIN de la fact con la tabla de referencia OMS (el umbral no está escrito en el SQL).
SELECT
    e.nombre                                           AS estacion,
    k.codigo_fuente                                    AS contaminante,
    count(*)                                           AS dias_con_dato,
    sum(CASE WHEN f.valor_masa > r.guia_oms THEN 1 ELSE 0 END) AS dias_sobre_guia,
    round(100.0 * avg(CASE WHEN f.valor_masa > r.guia_oms THEN 1 ELSE 0 END), 1) AS pct_dias_sobre_guia,
    r.guia_oms                                         AS guia_24h,
    r.unidad
FROM modelo.fact_medicion_diaria f
JOIN modelo.ref_oms r          ON r.id_contaminante = f.id_contaminante AND r.promedio = '24h'
JOIN modelo.dim_estacion e     ON e.id_estacion = f.id_estacion
JOIN modelo.dim_contaminante k ON k.id_contaminante = f.id_contaminante
WHERE f.ventana = '24h'
  AND f.tiene_dato
GROUP BY e.nombre, k.codigo_fuente, k.orden, r.guia_oms, r.unidad
ORDER BY k.orden, pct_dias_sobre_guia DESC;


-- B2 · Promedio anual contra la guía anual: "cuántas veces por encima"
-- PREGUNTA  Subpregunta 2: ¿cuántas veces por encima de la guía anual están los promedios anuales?
-- POR QUÉ   La guía anual mide la exposición de largo plazo (la que más pesa en la salud).
--           Solo años con >= 75% de días con dato (regla del 75%). 2026 está marcado como parcial.
-- TÉCNICA   CTE (WITH) + AVG que ignora NULL + JOIN con la referencia + filtro sobre un agregado.
WITH anual AS (
    SELECT
        f.id_estacion,
        f.id_contaminante,
        c.anio,
        bool_or(c.es_anio_parcial)              AS es_parcial,
        avg(f.valor_masa)                       AS promedio,      -- AVG ignora los días sin dato (NULL)
        count(f.valor_masa) * 1.0 / count(*)    AS completitud
    FROM modelo.fact_medicion_diaria f
    JOIN modelo.dim_calendario c ON c.fecha = f.fecha
    WHERE f.ventana = '24h'
    GROUP BY f.id_estacion, f.id_contaminante, c.anio
)
SELECT
    a.id_estacion,
    r.contaminante,
    a.anio,
    CASE WHEN a.es_parcial THEN 'parcial (ene-sep)' ELSE 'completo' END AS anio_tipo,
    round(100 * a.completitud, 1)          AS completitud_pct,
    round(a.promedio, 1)                   AS promedio_anual,
    r.guia_oms                             AS guia_anual,
    round(a.promedio / r.guia_oms, 1)      AS veces_la_guia,
    r.unidad
FROM anual a
JOIN modelo.ref_oms r ON r.id_contaminante = a.id_contaminante AND r.promedio = 'anual'
WHERE a.completitud >= 0.75
ORDER BY veces_la_guia DESC;


-- B3 · Percentil 99 anual contra la guía de 24 h (la definición formal de la OMS)
-- PREGUNTA  Subpreguntas 1 y 2: ¿se cumple la guía de 24 h tal como la define la OMS?
-- POR QUÉ   La OMS define la guía de 24 h como el percentil 99 de los valores diarios del año
--           (se toleran 3 o 4 días por año por encima). El "% de días" es una simplificación.
-- TÉCNICA   Agregado de percentil: percentile_cont(p) WITHIN GROUP (ORDER BY x), SQL estándar
--           (DuckDB lo acepta y también tiene el atajo quantile_cont(x, p)).
SELECT
    d.id_estacion,
    d.id_contaminante,
    year(d.fecha)                                                     AS anio,
    count(*)                                                          AS dias_con_dato,
    round(percentile_cont(0.99) WITHIN GROUP (ORDER BY d.valor), 1)   AS p99,
    max(d.guia_oms_24h)                                               AS guia_24h,
    round(percentile_cont(0.99) WITHIN GROUP (ORDER BY d.valor) / max(d.guia_oms_24h), 2) AS p99_veces_guia
FROM indicadores.agg_cumplimiento_diario d
WHERE d.id_contaminante IN ('no2', 'pm10')
GROUP BY d.id_estacion, d.id_contaminante, year(d.fecha)
ORDER BY d.id_contaminante, d.id_estacion, anio;


-- B4 · ¿En qué escalón de la OMS está cada estación? (últimos 12 meses)
-- PREGUNTA  Subpregunta 2: más allá de "cumple / no cumple", ¿qué objetivo intermedio se alcanza y
--           cuánto falta para el siguiente?
-- POR QUÉ   Para un tomador de decisión es más útil "bajar 6 µg/m³ para llegar al IT1" que "no cumple".
--           Se usan los últimos 12 meses (oct-2025 a sep-2026): un año completo y el más reciente.
-- TÉCNICA   Lectura de una tabla agregada (agg_anual) + JOIN con dimensiones + ORDER BY.
SELECT
    e.nombre               AS estacion,
    a.id_contaminante,
    a.periodo,
    a.promedio_anual,
    a.guia_anual,
    a.veces_guia_anual,
    a.nivel_oms,
    a.proximo_nivel,
    a.ug_para_proximo_nivel
FROM indicadores.agg_anual a
JOIN modelo.dim_estacion e ON e.id_estacion = a.id_estacion
WHERE a.id_periodo = 'movil_12m'
  AND a.guia_anual IS NOT NULL
ORDER BY a.id_contaminante, a.veces_guia_anual DESC;


-- B5 · Ranking de estaciones
-- PREGUNTA  Subpregunta 3: ¿qué estación tiene la peor situación y con qué contaminante? (H2: La Boca en NO2)
-- POR QUÉ   Ordenar las estaciones con dos criterios (veces la guía anual y % de días sobre la guía
--           diaria) y ver si coinciden.
-- TÉCNICA   Funciones de ventana RANK() OVER (PARTITION BY ... ORDER BY ...).
SELECT
    a.id_contaminante,
    e.nombre                                                                          AS estacion,
    a.veces_guia_anual,
    round(100 * a.pct_dias_supera_24h, 1)                                             AS pct_dias_sobre_guia_24h,
    RANK() OVER (PARTITION BY a.id_contaminante ORDER BY a.veces_guia_anual DESC)     AS ranking_anual,
    RANK() OVER (PARTITION BY a.id_contaminante ORDER BY a.pct_dias_supera_24h DESC)  AS ranking_diario
FROM indicadores.agg_anual a
JOIN modelo.dim_estacion e ON e.id_estacion = a.id_estacion
WHERE a.id_periodo = 'movil_12m'
  AND a.guia_anual IS NOT NULL
ORDER BY a.id_contaminante, ranking_anual;


-- B6 · Racha más larga de días seguidos por encima de la guía de NO2
-- PREGUNTA  Subpregunta 3: ¿cuánto tiempo seguido se respira aire por encima de la guía?
-- POR QUÉ   "216 días seguidos" comunica la persistencia del problema mejor que un promedio.
-- TÉCNICA   Gaps and islands: ROW_NUMBER() numera los días sobre la guía; en días consecutivos,
--           fecha − número es constante e identifica la racha. Después GROUP BY racha.
--           (fecha − entero es de DuckDB/PostgreSQL; en otros motores, DATEADD.) El modelo
--           indicadores.agg_rachas guarda todas las rachas para el dashboard.
WITH sobre_guia AS (
    SELECT
        id_estacion,
        fecha,
        fecha - CAST(ROW_NUMBER() OVER (PARTITION BY id_estacion ORDER BY fecha) AS INTEGER) AS id_racha
    FROM indicadores.agg_cumplimiento_diario
    WHERE id_contaminante = 'no2'
      AND supera_guia
),
rachas AS (
    SELECT id_estacion, min(fecha) AS desde, max(fecha) AS hasta, count(*) AS dias
    FROM sobre_guia
    GROUP BY id_estacion, id_racha
)
SELECT *
FROM (
    SELECT r.*, ROW_NUMBER() OVER (PARTITION BY id_estacion ORDER BY dias DESC, desde) AS orden
    FROM rachas r
) t
WHERE orden = 1
ORDER BY dias DESC;


-- =====================================================================================================
-- PARTE C · CÓMO VARÍA LA BRECHA
-- =====================================================================================================

-- C1 · Por tipo de día (hábil, sábado, domingo, feriado)
-- PREGUNTA  Subpregunta 4 (H3): ¿los domingos y feriados la brecha se reduce de forma visible?
-- POR QUÉ   Si el NO2 baja cuando baja la actividad urbana, el tránsito es una fuente principal.
-- TÉCNICA   CTE + JOIN con el calendario + ventana con MAX(CASE ...) OVER para comparar cada tipo
--           de día contra el día hábil de la misma estación.
WITH por_tipo AS (
    SELECT
        d.id_estacion,
        c.tipo_dia_etiqueta                                   AS tipo_dia,
        c.orden_tipo_dia,
        count(*)                                              AS dias,
        avg(d.valor)                                          AS no2_promedio,
        avg(CASE WHEN d.supera_guia THEN 1.0 ELSE 0 END)      AS prop_sobre_guia
    FROM indicadores.agg_cumplimiento_diario d
    JOIN modelo.dim_calendario c ON c.fecha = d.fecha
    WHERE d.id_contaminante = 'no2'
    GROUP BY d.id_estacion, c.tipo_dia_etiqueta, c.orden_tipo_dia
)
SELECT
    id_estacion,
    tipo_dia,
    dias,
    round(no2_promedio, 1)                                    AS no2_ugm3,
    round(100 * prop_sobre_guia, 1)                           AS pct_dias_sobre_guia,
    round(100 * (no2_promedio / max(CASE WHEN orden_tipo_dia = 1 THEN no2_promedio END)
                 OVER (PARTITION BY id_estacion) - 1), 1)     AS variacion_vs_habil_pct
FROM por_tipo
ORDER BY id_estacion, orden_tipo_dia;


-- C2 · Por estación del año
-- PREGUNTA  Subpregunta 5: ¿hay estacionalidad (invierno vs verano)?
-- POR QUÉ   En invierno hay menos mezcla vertical (inversiones térmicas) y el NO2 se acumula.
-- TÉCNICA   JOIN + GROUP BY por una columna derivada del calendario + ordenamiento por una
--           columna auxiliar (orden_estacion_del_anio) para no ordenar alfabéticamente.
SELECT
    d.id_contaminante,
    d.id_estacion,
    c.estacion_del_anio,
    count(*)                                                           AS dias,
    round(avg(d.valor), 1)                                             AS promedio,
    round(100 * avg(CASE WHEN d.supera_guia THEN 1.0 ELSE 0 END), 1)   AS pct_dias_sobre_guia
FROM indicadores.agg_cumplimiento_diario d
JOIN modelo.dim_calendario c ON c.fecha = d.fecha
WHERE d.id_contaminante IN ('no2', 'pm10')
GROUP BY d.id_contaminante, d.id_estacion, c.estacion_del_anio, c.orden_estacion_del_anio
ORDER BY d.id_contaminante, d.id_estacion, c.orden_estacion_del_anio;


-- C3 · Enero a septiembre de cada año (mismos meses), por estación
-- PREGUNTA  Subpregunta 6 / tendencia: ¿el NO2 bajó de 2024 a 2026?
-- POR QUÉ   2026 solo llega a septiembre: para comparar años hay que usar los mismos meses
--           (si no, se mezcla la estacionalidad). Y hay que mirarlo POR ESTACIÓN: en 2024 falta casi
--           todo Centenario (la estación más limpia) y el promedio de todas juntas sale inflado.
--           Sin controlar la meteorología, una baja no se puede atribuir a una mejora real.
-- TÉCNICA   Filtro por mes + GROUP BY + agregación condicional para pasar los años a columnas (pivot).
SELECT
    id_estacion,
    round(avg(valor) FILTER (WHERE year(fecha) = 2024), 1) AS no2_ene_sep_2024,
    round(avg(valor) FILTER (WHERE year(fecha) = 2025), 1) AS no2_ene_sep_2025,
    round(avg(valor) FILTER (WHERE year(fecha) = 2026), 1) AS no2_ene_sep_2026,
    count(*) FILTER (WHERE year(fecha) = 2024)             AS dias_2024,
    count(*) FILTER (WHERE year(fecha) = 2025)             AS dias_2025,
    count(*) FILTER (WHERE year(fecha) = 2026)             AS dias_2026
FROM modelo.fact_medicion_diaria
WHERE id_contaminante = 'no2'
  AND ventana = '24h'
  AND tiene_dato
  AND month(fecha) <= 9
GROUP BY id_estacion
ORDER BY id_estacion;


-- C4 · El mismo promedio, todas las estaciones juntas: el efecto de los huecos
-- PREGUNTA  Subpregunta 6: ¿cuánto condicionan los huecos de datos a las conclusiones?
-- POR QUÉ   Junta las tres estaciones como hace un análisis apurado: la "caída" de 2024 a 2025 sale
--           más grande que en cada estación por separado, porque en 2024 casi no hay días de la
--           estación más limpia. Se repite usando solo días en que las tres estaciones tienen dato:
--           en 2024 NO hay ninguno entre enero y septiembre, o sea que la comparación contra 2024
--           no se puede hacer en igualdad de condiciones.
-- TÉCNICA   Subconsulta con GROUP BY + HAVING para encontrar "días comunes" + UNION ALL.
WITH comunes AS (
    SELECT fecha
    FROM modelo.fact_medicion_diaria
    WHERE id_contaminante = 'no2' AND ventana = '24h' AND tiene_dato
    GROUP BY fecha
    HAVING count(DISTINCT id_estacion) = 3
)
SELECT 'todas las estaciones, todos los días' AS criterio, year(fecha) AS anio,
       round(avg(valor), 1) AS no2_ppb_ene_sep, count(*) AS mediciones
FROM modelo.fact_medicion_diaria
WHERE id_contaminante = 'no2' AND ventana = '24h' AND tiene_dato AND month(fecha) <= 9
GROUP BY year(fecha)
UNION ALL
SELECT 'solo días con las 3 estaciones', year(f.fecha),
       round(avg(f.valor), 1), count(*)
FROM modelo.fact_medicion_diaria f
JOIN comunes c ON c.fecha = f.fecha
WHERE f.id_contaminante = 'no2' AND f.ventana = '24h' AND f.tiene_dato AND month(f.fecha) <= 9
GROUP BY year(f.fecha)
ORDER BY criterio, anio;


-- C5 · Días atípicos y contexto
-- PREGUNTA  ¿Los valores atípicos son errores o episodios reales?
-- POR QUÉ   Si el mismo día aparece alto en las tres estaciones, es un episodio atmosférico
--           (p. ej. una inversión térmica), no un error de un equipo: por eso no se borran.
-- TÉCNICA   GROUP BY sobre la tabla de outliers + HAVING + STRING_AGG para listar estaciones.
SELECT
    fecha,
    id_contaminante,
    count(DISTINCT id_estacion)                                  AS estaciones_con_outlier,
    string_agg(DISTINCT id_estacion, ', ' ORDER BY id_estacion)  AS estaciones,
    max(veces_mediana)                                           AS max_veces_mediana
FROM calidad.calidad_outliers
WHERE ventana = '24h'
GROUP BY fecha, id_contaminante
HAVING count(DISTINCT id_estacion) >= 2
ORDER BY estaciones_con_outlier DESC, max_veces_mediana DESC;


-- =====================================================================================================
-- PARTE D · VISTAS (las tablas que muestra el dashboard, en SQL)
-- Power BI importa los CSV de data/final; estas vistas calculan lo mismo que las medidas DAX de
-- docs/powerbi_spec.md y sirven para verificar que el dashboard muestre los números correctos.
-- =====================================================================================================

CREATE SCHEMA IF NOT EXISTS analisis;

-- D1 · Resumen por estación y contaminante (tarjetas y KPIs de la página "Resumen")
CREATE OR REPLACE VIEW analisis.v_resumen_estacion AS
WITH diario AS (
    SELECT
        id_estacion,
        id_contaminante,
        count(*)                                          AS dias_con_dato,
        avg(CASE WHEN supera_guia THEN 1.0 ELSE 0 END)    AS prop_dias_sobre_guia_24h
    FROM indicadores.agg_cumplimiento_diario
    GROUP BY id_estacion, id_contaminante
),
racha AS (
    SELECT id_estacion, id_contaminante, max(dias) AS racha_maxima_dias
    FROM indicadores.agg_rachas
    GROUP BY id_estacion, id_contaminante
)
SELECT
    e.nombre                         AS estacion,
    d.id_contaminante,
    d.dias_con_dato,
    round(100 * d.prop_dias_sobre_guia_24h, 1) AS pct_dias_sobre_guia_24h,
    a.promedio_anual                 AS promedio_ultimos_12m,
    a.veces_guia_anual               AS veces_guia_anual_ultimos_12m,
    a.nivel_oms                      AS nivel_oms_ultimos_12m,
    a.p99_24h                        AS p99_ultimos_12m,
    coalesce(r.racha_maxima_dias, 0) AS racha_maxima_dias
FROM diario d
JOIN modelo.dim_estacion e ON e.id_estacion = d.id_estacion
LEFT JOIN indicadores.agg_anual a
       ON a.id_estacion = d.id_estacion AND a.id_contaminante = d.id_contaminante
      AND a.id_periodo = 'movil_12m'
LEFT JOIN racha r ON r.id_estacion = d.id_estacion AND r.id_contaminante = d.id_contaminante;

-- D2 · Cumplimiento por tipo de día y estación del año (matriz de la página "Detalle")
CREATE OR REPLACE VIEW analisis.v_cumplimiento_por_tipo_dia AS
SELECT
    d.id_estacion,
    d.id_contaminante,
    c.tipo_dia_etiqueta                                              AS tipo_dia,
    c.estacion_del_anio,
    count(*)                                                         AS dias,
    round(avg(d.valor), 2)                                           AS promedio,
    round(100 * avg(CASE WHEN d.supera_guia THEN 1.0 ELSE 0 END), 1) AS pct_dias_sobre_guia
FROM indicadores.agg_cumplimiento_diario d
JOIN modelo.dim_calendario c ON c.fecha = d.fecha
GROUP BY d.id_estacion, d.id_contaminante, c.tipo_dia_etiqueta, c.estacion_del_anio;

-- D3 · Qué quedó afuera y por qué (página "Calidad de datos")
CREATE OR REPLACE VIEW analisis.v_indicadores_excluidos AS
SELECT
    id_estacion,
    id_contaminante,
    periodo,
    round(100 * completitud, 1) AS completitud_pct,
    'Menos de 75% de días con dato: el promedio anual y el P99 no se calculan' AS motivo
FROM indicadores.agg_anual
WHERE NOT es_valido;

-- Uso de las vistas
SELECT * FROM analisis.v_resumen_estacion ORDER BY id_contaminante, pct_dias_sobre_guia_24h DESC;
SELECT * FROM analisis.v_indicadores_excluidos;
