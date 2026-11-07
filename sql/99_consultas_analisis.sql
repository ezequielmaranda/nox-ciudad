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
-- Capas de la base (arquitectura medallón):
--   bronze  el CSV tal como viene (todo texto) y las tablas de referencia
--   silver  valores horarios limpios (silver.medicion_horaria) y valor diario (silver.medicion_diaria)
--   gold    modelo estrella (dimensiones, fact diaria y horaria), guías OMS e indicadores
--           (gold.agg_anual, gold.calidad_resumen): lo que se exporta a data/final
-- Son todas consultas de lectura: no crean ni modifican tablas.
-- Funciones propias de DuckDB (comentadas donde aparecen): FILTER, quantile_cont, fecha - entero.
-- =====================================================================================================


-- =====================================================================================================
-- PARTE A · PERFILADO Y CALIDAD (antes de analizar, saber con qué datos contamos)
-- =====================================================================================================

-- A1 · Tamaño y cobertura del crudo
-- PREGUNTA  ¿Cuántos datos hay, de cuándo a cuándo y de cuántas estaciones?
-- POR QUÉ   Es la "ficha" del dataset: lo primero que se presenta. El CSV de BA Data trae toda la serie
--           (desde 2009); el estudio usa 2024 a septiembre de 2026.
-- TÉCNICA   SELECT con funciones de agregación (COUNT, COUNT DISTINCT, MIN, MAX) y FILTER, más una
--           subconsulta escalar para contar las filas del CSV en bronze (cada fila tiene 9 valores).
SELECT
    (SELECT count(*) FROM bronze.calidad_aire)       AS filas_csv,
    count(*)                                         AS valores_horarios,
    count(DISTINCT id_estacion)                      AS estaciones,
    count(DISTINCT id_contaminante)                  AS contaminantes,
    min(fecha)                                       AS desde,
    max(fecha)                                       AS hasta,
    count(*) FILTER (WHERE fecha BETWEEN '2024-01-01' AND '2026-09-30') AS valores_del_periodo
FROM silver.medicion_horaria;


-- A2 · Nulos y valores especiales por contaminante
-- PREGUNTA  ¿Qué proporción de los valores horarios del período no es un número válido?
-- POR QUÉ   's/d', '#REF!' o '<0.05' no se pueden promediar: hay que saber cuántos son.
-- TÉCNICA   GROUP BY + función de ventana (SUM ... OVER) para el porcentaje dentro de cada grupo.
SELECT
    id_contaminante,
    estado_valor,
    count(*) AS n,
    round(100.0 * count(*) / sum(count(*)) OVER (PARTITION BY id_contaminante), 2) AS pct
FROM silver.medicion_horaria
WHERE fecha BETWEEN '2024-01-01' AND '2026-09-30'
GROUP BY id_contaminante, estado_valor
ORDER BY id_contaminante, n DESC;


-- A3 · Duplicados
-- PREGUNTA  ¿Hay más de un valor para la misma fecha, hora, estación y contaminante?
-- POR QUÉ   Un duplicado contaría dos veces la misma hora en los promedios. Resultado esperado: 0 filas.
-- TÉCNICA   GROUP BY + HAVING.
SELECT fecha, hora, id_estacion, id_contaminante, count(*) AS repeticiones
FROM silver.medicion_horaria
GROUP BY fecha, hora, id_estacion, id_contaminante
HAVING count(*) > 1;


-- A4 · Días faltantes: calendario completo + LEFT JOIN
-- PREGUNTA  ¿Qué días no tienen ninguna hora en la fuente, por estación y contaminante?
-- POR QUÉ   Un día sin filas no aparece en un GROUP BY común: hay que generar todos los días posibles
--           y ver cuáles no tienen pareja. Distingue "no hay fila" de "hay filas con s/d".
-- TÉCNICA   CROSS JOIN (todas las combinaciones) + LEFT JOIN + filtro IS NULL (anti-join).
WITH esperado AS (
    SELECT c.fecha, e.id_estacion, k.id_contaminante
    FROM gold.dim_calendario c
    CROSS JOIN gold.dim_estacion e
    CROSS JOIN gold.dim_contaminante k
),
publicado AS (
    SELECT DISTINCT id_estacion, fecha, id_contaminante
    FROM silver.medicion_horaria
    WHERE hora BETWEEN 1 AND 24
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
-- TÉCNICA   GROUP BY + COUNT con condición (COUNT(CASE WHEN ...)) + CASE para clasificar. El umbral no se
--           escribe acá: es_valido viene de gold.agg_anual (variable umbral_completitud de dbt).
SELECT
    f.id_estacion,
    f.id_contaminante,
    c.anio,
    count(*)                                         AS dias_calendario,
    count(CASE WHEN f.tiene_dato THEN 1 END)         AS dias_con_dato,
    round(100.0 * count(CASE WHEN f.tiene_dato THEN 1 END) / count(*), 1) AS completitud_pct,
    CASE
        WHEN v.es_valido THEN 'válido'
        ELSE 'NO válido (< 75%)'
    END                                              AS regla_75
FROM gold.fact_medicion_diaria f
JOIN gold.dim_calendario c ON c.fecha = f.fecha
JOIN gold.agg_anual v
  ON v.id_estacion = f.id_estacion AND v.id_contaminante = f.id_contaminante
 AND v.id_periodo = CAST(c.anio AS VARCHAR)
GROUP BY f.id_estacion, f.id_contaminante, c.anio, v.es_valido
ORDER BY f.id_contaminante, f.id_estacion, c.anio;


-- A6 · Qué descartaron las reglas de calidad
-- PREGUNTA  ¿Cuántos valores horarios se descartaron por cada regla y en qué contaminante?
-- POR QUÉ   Mostrar que la limpieza es acotada y explicable (no se "tiraron datos" a ciegas).
--           's/d' no cuenta: es un dato que la fuente no tiene, no algo que se descartó.
-- TÉCNICA   Agregación condicional con FILTER (estándar SQL; en motores sin FILTER: SUM(CASE ...)).
SELECT
    motivo_invalido                                   AS regla,
    count(*)                                          AS descartados,
    count(*) FILTER (WHERE id_contaminante = 'no2')   AS en_no2,
    count(*) FILTER (WHERE id_contaminante = 'pm10')  AS en_pm10,
    count(*) FILTER (WHERE id_contaminante = 'co')    AS en_co,
    min(fecha)                                        AS primera,
    max(fecha)                                        AS ultima
FROM silver.medicion_horaria
WHERE fecha BETWEEN '2024-01-01' AND '2026-09-30'
  AND motivo_invalido <> 'sin_dato_fuente'
GROUP BY motivo_invalido
ORDER BY descartados DESC;


-- A7 · De horas a días: cuántas horas válidas tiene cada día de NO2
-- PREGUNTA  ¿Cuántos días tienen las 24 horas, cuántos alcanzan el mínimo de 18 y cuántos no?
-- POR QUÉ   El promedio diario de NO2 solo se calcula con 18 horas válidas o más (75%, criterio de la UE).
--           Muestra cuántos días se pierden por esa regla y que la mayoría está completa.
-- TÉCNICA   CTE + CASE para agrupar en tramos + GROUP BY + porcentaje con SUM ... OVER.
WITH tramos AS (
    SELECT
        id_estacion,
        CASE
            WHEN n_horas_validas = 24 THEN '1. 24 horas'
            WHEN n_horas_validas >= 18 THEN '2. 18 a 23 horas (se calcula)'
            WHEN n_horas_validas >= 1 THEN '3. 1 a 17 horas (no alcanza)'
            ELSE '4. ninguna hora válida'
        END AS horas_validas
    FROM gold.fact_medicion_diaria
    WHERE id_contaminante = 'no2'
)
SELECT
    id_estacion,
    horas_validas,
    count(*)                                                                    AS dias,
    round(100.0 * count(*) / sum(count(*)) OVER (PARTITION BY id_estacion), 1) AS pct
FROM tramos
GROUP BY id_estacion, horas_validas
ORDER BY id_estacion, horas_validas;


-- =====================================================================================================
-- PARTE B · CUÁN LEJOS ESTAMOS DE LA OMS
-- =====================================================================================================

-- B0 · ¿En qué escalón de la OMS cae cada día?
-- PREGUNTA  Subpreguntas 1 y 2: ¿hasta qué objetivo intermedio cumple el NO2 (y el PM10) día a día?
-- POR QUÉ   La guía es muy exigente; los objetivos intermedios (IT) miden en qué escalón se está, que dice
--           más que "cumple / no cumple".
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
FROM gold.fact_medicion_diaria
WHERE tiene_dato
  AND id_contaminante IN ('no2', 'pm10')
GROUP BY id_contaminante, id_estacion, nivel_oms, orden_nivel_oms
ORDER BY id_contaminante, id_estacion, orden_nivel_oms;


-- B0b · Matriz de escalones: % de días que cumplen cada nivel, por estación y año (NO2)
-- PREGUNTA  Subpreguntas 1, 2 y 3: ¿hasta qué escalón cumple cada estación, año por año?
-- POR QUÉ   Es la tabla que va a la presentación: muestra en una sola vista la guía, los objetivos
--           intermedios y el escalón del promedio anual. Celdas vacías = período con menos de 75% de días.
-- TÉCNICA   Lectura de la tabla de indicadores (gold.agg_anual): dbt ya contó, para cada período, los
--           días que cumplen cada escalón (COUNT ... FILTER) y los dejó en columnas. Si el período no
--           llega al 75% de días con dato, esas columnas vienen vacías (NULL).
SELECT
    e.nombre                                      AS estacion,
    a.periodo,
    round(100 * a.pct_cumple_guia_24h, 1)         AS pct_cumple_guia_25,
    round(100 * a.pct_cumple_it2_24h, 1)          AS pct_cumple_it2_50,
    round(100 * a.pct_cumple_it1_24h, 1)          AS pct_cumple_it1_120,
    a.nivel_oms                                   AS escalon_promedio_anual
FROM gold.agg_anual a
JOIN gold.dim_estacion e ON e.id_estacion = a.id_estacion
WHERE a.id_contaminante = 'no2'
  AND a.es_periodo_estudio
ORDER BY e.nombre, a.orden_periodo;


-- B1 · % de días por encima de la guía diaria (24 h)
-- PREGUNTA  Subpregunta 1 y H1: ¿qué porcentaje de días se supera la guía diaria, por estación y contaminante?
--           ¿El NO2 es el que más se aleja de la guía?
-- POR QUÉ   Es el indicador más fácil de comunicar ("9 de cada 10 días").
--           Denominador = días CON DATO (no todos los días): un día sin dato no es un día "limpio".
-- TÉCNICA   JOIN de la fact con la tabla de guías (gold.guia_oms, en formato largo: una fila por
--           contaminante × promedio × nivel). El umbral no está escrito en el SQL.
SELECT
    e.nombre                                           AS estacion,
    k.codigo_fuente                                    AS contaminante,
    count(*)                                           AS dias_con_dato,
    sum(CASE WHEN f.valor_masa > r.umbral THEN 1 ELSE 0 END) AS dias_sobre_guia,
    round(100.0 * avg(CASE WHEN f.valor_masa > r.umbral THEN 1 ELSE 0 END), 1) AS pct_dias_sobre_guia,
    r.umbral                                           AS guia_24h,
    r.unidad
FROM gold.fact_medicion_diaria f
JOIN gold.guia_oms r           ON r.id_contaminante = f.id_contaminante AND r.promedio = '24h' AND r.nivel = 'AQG'
JOIN gold.dim_estacion e     ON e.id_estacion = f.id_estacion
JOIN gold.dim_contaminante k ON k.id_contaminante = f.id_contaminante
WHERE f.tiene_dato
GROUP BY e.nombre, k.codigo_fuente, k.orden, r.umbral, r.unidad
ORDER BY k.orden, pct_dias_sobre_guia DESC;


-- B2 · Promedio anual contra la guía anual: "cuántas veces por encima"
-- PREGUNTA  Subpregunta 2: ¿cuántas veces por encima de la guía anual están los promedios anuales?
-- POR QUÉ   La guía anual mide la exposición de largo plazo (la que más pesa en la salud).
--           Solo años con >= 75% de días con dato (regla del 75%). 2026 está marcado como parcial.
-- TÉCNICA   CTE (WITH) + AVG que ignora NULL + JOIN con las guías y con la tabla de indicadores (de
--           ahí salen la regla del 75% y si el año es parcial).
WITH anual AS (
    SELECT
        f.id_estacion,
        f.id_contaminante,
        c.anio,
        avg(f.valor_masa)                       AS promedio,      -- AVG ignora los días sin dato (NULL)
        count(f.valor_masa) * 1.0 / count(*)    AS completitud
    FROM gold.fact_medicion_diaria f
    JOIN gold.dim_calendario c ON c.fecha = f.fecha
    GROUP BY f.id_estacion, f.id_contaminante, c.anio
)
SELECT
    a.id_estacion,
    a.id_contaminante,
    a.anio,
    CASE WHEN v.tipo_periodo = 'anio_parcial' THEN 'parcial (ene-sep)' ELSE 'completo' END AS anio_tipo,
    round(100 * a.completitud, 1)          AS completitud_pct,
    round(a.promedio, 1)                   AS promedio_anual,
    r.umbral                               AS guia_anual,
    round(a.promedio / r.umbral, 1)        AS veces_la_guia,
    r.unidad
FROM anual a
JOIN gold.guia_oms r ON r.id_contaminante = a.id_contaminante AND r.promedio = 'anual' AND r.nivel = 'AQG'
JOIN gold.agg_anual v
  ON v.id_estacion = a.id_estacion AND v.id_contaminante = a.id_contaminante
 AND v.id_periodo = CAST(a.anio AS VARCHAR)
WHERE v.es_valido
ORDER BY veces_la_guia DESC;


-- B3 · Percentil 99 anual contra la guía de 24 h (la definición formal de la OMS)
-- PREGUNTA  Subpreguntas 1 y 2: ¿se cumple la guía de 24 h tal como la define la OMS?
-- POR QUÉ   La OMS define la guía de 24 h como el percentil 99 de los valores diarios del año
--           (se toleran 3 o 4 días por año por encima). El "% de días" es una simplificación.
-- TÉCNICA   Agregado de percentil: percentile_cont(p) WITHIN GROUP (ORDER BY x), SQL estándar
--           (DuckDB lo acepta y también tiene el atajo quantile_cont(x, p)) + JOIN con las guías.
SELECT
    d.id_estacion,
    d.id_contaminante,
    year(d.fecha)                                                        AS anio,
    count(*)                                                             AS dias_con_dato,
    round(percentile_cont(0.99) WITHIN GROUP (ORDER BY d.valor_masa), 1) AS p99,
    r.umbral                                                             AS guia_24h,
    round(percentile_cont(0.99) WITHIN GROUP (ORDER BY d.valor_masa) / r.umbral, 2) AS p99_veces_guia
FROM gold.fact_medicion_diaria d
JOIN gold.guia_oms r ON r.id_contaminante = d.id_contaminante AND r.promedio = '24h' AND r.nivel = 'AQG'
WHERE d.tiene_dato
  AND d.id_contaminante IN ('no2', 'pm10')
GROUP BY d.id_estacion, d.id_contaminante, year(d.fecha), r.umbral
ORDER BY d.id_contaminante, d.id_estacion, anio;


-- B4 · Escalón y ranking de las estaciones (últimos 12 meses)
-- PREGUNTA  Subpreguntas 2 y 3, H2: ¿qué objetivo intermedio alcanza cada estación, cuánto le falta
--           para el siguiente y cuál está peor? (H2 espera que sea Córdoba, la de tránsito intenso).
-- POR QUÉ   Para un tomador de decisión es más útil "bajar 6 µg/m³ para llegar al IT1" que "no cumple".
--           El ranking usa dos criterios (veces la guía anual y % de días sobre la guía diaria) para
--           ver si coinciden. Se usan los últimos 12 meses (oct-2025 a sep-2026): un año completo y
--           el más reciente.
-- TÉCNICA   Lectura de una tabla agregada (gold.agg_anual) + JOIN con dimensiones + funciones de
--           ventana RANK() OVER (PARTITION BY ... ORDER BY ...).
SELECT
    a.id_contaminante,
    e.nombre                                                                          AS estacion,
    a.promedio_anual,
    a.guia_anual,
    a.veces_guia_anual,
    a.nivel_oms,
    a.proximo_nivel,
    a.ug_para_proximo_nivel,
    round(100 * a.pct_dias_supera_24h, 1)                                             AS pct_dias_sobre_guia_24h,
    RANK() OVER (PARTITION BY a.id_contaminante ORDER BY a.veces_guia_anual DESC)     AS ranking_anual,
    RANK() OVER (PARTITION BY a.id_contaminante ORDER BY a.pct_dias_supera_24h DESC)  AS ranking_diario
FROM gold.agg_anual a
JOIN gold.dim_estacion e ON e.id_estacion = a.id_estacion
WHERE a.id_periodo = 'movil_12m'
  AND a.guia_anual IS NOT NULL
ORDER BY a.id_contaminante, ranking_anual;


-- B5 · Racha más larga de días seguidos por encima de la guía de NO2
-- PREGUNTA  Subpregunta 3: ¿cuánto tiempo seguido se respira aire por encima de la guía?
-- POR QUÉ   "254 días con dato seguidos sobre la guía" comunica la persistencia del problema mejor que
--           un promedio. Solo un día con dato que cumple la guía corta la racha; un hueco de más de 7
--           días sin dato también (la fuente tiene huecos cortos de exportación que no son falta de
--           medición). gold.agg_anual guarda la racha más larga de cada período para el dashboard.
-- TÉCNICA   Gaps and islands sobre la secuencia de días con dato: ROW_NUMBER() numera todos los días
--           con dato y, aparte, los que superan la guía; la diferencia es constante dentro de una
--           racha. LAG() mide el hueco con el día anterior y SUM() OVER acumulado arma los tramos.
WITH dias AS (
    SELECT
        id_estacion,
        fecha,
        supera_guia,
        ROW_NUMBER() OVER (PARTITION BY id_estacion ORDER BY fecha)                    AS n_dia,
        fecha - LAG(fecha) OVER (PARTITION BY id_estacion ORDER BY fecha) - 1          AS dias_sin_dato_antes
    FROM gold.fact_medicion_diaria
    WHERE id_contaminante = 'no2'
      AND tiene_dato
),
tramos AS (
    SELECT *,
           SUM(CASE WHEN dias_sin_dato_antes > 7 THEN 1 ELSE 0 END)
               OVER (PARTITION BY id_estacion ORDER BY fecha)                          AS tramo
    FROM dias
),
sobre_guia AS (
    SELECT id_estacion, fecha, tramo,
           n_dia - ROW_NUMBER() OVER (PARTITION BY id_estacion ORDER BY fecha)        AS id_racha
    FROM tramos
    WHERE supera_guia
),
rachas AS (
    SELECT id_estacion, min(fecha) AS desde, max(fecha) AS hasta, count(*) AS dias_con_dato,
           max(fecha) - min(fecha) + 1 AS dias_calendario
    FROM sobre_guia
    GROUP BY id_estacion, tramo, id_racha
)
SELECT *
FROM (
    SELECT r.*, ROW_NUMBER() OVER (PARTITION BY id_estacion ORDER BY dias_con_dato DESC, desde) AS orden
    FROM rachas r
) t
WHERE orden = 1
ORDER BY dias_con_dato DESC;


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
        avg(d.valor_masa)                                     AS no2_promedio,
        avg(CASE WHEN d.supera_guia THEN 1.0 ELSE 0 END)      AS prop_sobre_guia
    FROM gold.fact_medicion_diaria d
    JOIN gold.dim_calendario c ON c.fecha = d.fecha
    WHERE d.id_contaminante = 'no2'
      AND d.tiene_dato
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


-- C1b · Perfil horario del NO2: hábil contra domingo
-- PREGUNTA  Subpregunta 4 (H3): ¿en qué horas del día se nota la diferencia entre hábil y domingo?
-- POR QUÉ   Si el NO2 sale del tránsito, en día hábil tiene que haber picos en las horas pico (mañana
--           y tarde) que el domingo no aparecen. Es lo que el promedio diario no puede mostrar.
-- TÉCNICA   Segunda tabla de hechos con otro grano (fact_medicion_horaria) + JOIN con el calendario
--           + PIVOT manual con FILTER: una columna por tipo de día.
SELECT
    h.id_estacion,
    h.hora,
    round(avg(h.valor_masa) FILTER (WHERE c.tipo_dia = 'habil'), 1)   AS no2_habil_ugm3,
    round(avg(h.valor_masa) FILTER (WHERE c.tipo_dia = 'domingo'), 1) AS no2_domingo_ugm3,
    round(avg(h.valor_masa) FILTER (WHERE c.tipo_dia = 'domingo')
        / avg(h.valor_masa) FILTER (WHERE c.tipo_dia = 'habil') * 100 - 100, 1) AS domingo_vs_habil_pct
FROM gold.fact_medicion_horaria h
JOIN gold.dim_calendario c ON c.fecha = h.fecha
WHERE h.es_valido
GROUP BY h.id_estacion, h.hora
ORDER BY h.id_estacion, h.hora;


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
    round(avg(d.valor_masa), 1)                                        AS promedio,
    round(100 * avg(CASE WHEN d.supera_guia THEN 1.0 ELSE 0 END), 1)   AS pct_dias_sobre_guia
FROM gold.fact_medicion_diaria d
JOIN gold.dim_calendario c ON c.fecha = d.fecha
WHERE d.tiene_dato
  AND d.id_contaminante IN ('no2', 'pm10')
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
FROM gold.fact_medicion_diaria
WHERE id_contaminante = 'no2'
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
    FROM gold.fact_medicion_diaria
    WHERE id_contaminante = 'no2' AND tiene_dato
    GROUP BY fecha
    HAVING count(DISTINCT id_estacion) = 3
)
SELECT 'todas las estaciones, todos los días' AS criterio, year(fecha) AS anio,
       round(avg(valor), 1) AS no2_ppb_ene_sep, count(*) AS mediciones
FROM gold.fact_medicion_diaria
WHERE id_contaminante = 'no2' AND tiene_dato AND month(fecha) <= 9
GROUP BY year(fecha)
UNION ALL
SELECT 'solo días con las 3 estaciones', year(f.fecha),
       round(avg(f.valor), 1), count(*)
FROM gold.fact_medicion_diaria f
JOIN comunes c ON c.fecha = f.fecha
WHERE f.id_contaminante = 'no2' AND f.tiene_dato AND month(f.fecha) <= 9
GROUP BY year(f.fecha)
ORDER BY criterio, anio;


-- C5 · Días atípicos y contexto
-- PREGUNTA  ¿Los valores atípicos son errores o episodios reales?
-- POR QUÉ   Si el mismo día aparece alto en las tres estaciones, es un episodio atmosférico
--           (p. ej. una inversión térmica), no un error de un equipo: por eso no se borran.
-- TÉCNICA   Filtro por la marca es_outlier de la fact (valor > Q3 + 3·IQR de su estación ×
--           contaminante) + GROUP BY + HAVING + STRING_AGG para listar estaciones.
SELECT
    fecha,
    id_contaminante,
    count(DISTINCT id_estacion)                                  AS estaciones_con_outlier,
    string_agg(DISTINCT id_estacion, ', ' ORDER BY id_estacion)  AS estaciones,
    max(valor_masa)                                              AS valor_maximo
FROM gold.fact_medicion_diaria
WHERE es_outlier
GROUP BY fecha, id_contaminante
HAVING count(DISTINCT id_estacion) >= 2
ORDER BY estaciones_con_outlier DESC, valor_maximo DESC;


-- =====================================================================================================
-- PARTE D · CONTROL DEL DASHBOARD
-- Power BI importa los CSV de data/final; estas consultas calculan lo mismo que las medidas DAX del
-- modelo (src/generar_pbip.py) y sirven para verificar que el dashboard muestre los números correctos.
-- =====================================================================================================

-- D1 · Resumen por estación y contaminante (tarjetas y KPIs de la página "Resumen")
-- TÉCNICA   CTE + LEFT JOIN de la fact (días) con la tabla de indicadores (últimos 12 meses y racha).
WITH diario AS (
    SELECT
        id_estacion,
        id_contaminante,
        count(*)                                          AS dias_con_dato,
        avg(CASE WHEN supera_guia THEN 1.0 ELSE 0 END)    AS prop_dias_sobre_guia_24h
    FROM gold.fact_medicion_diaria
    WHERE tiene_dato
    GROUP BY id_estacion, id_contaminante
),
racha AS (
    SELECT id_estacion, id_contaminante, max(racha_maxima_dias) AS racha_maxima_dias
    FROM gold.agg_anual
    WHERE es_periodo_estudio
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
JOIN gold.dim_estacion e ON e.id_estacion = d.id_estacion
LEFT JOIN gold.agg_anual a
       ON a.id_estacion = d.id_estacion AND a.id_contaminante = d.id_contaminante
      AND a.id_periodo = 'movil_12m'
LEFT JOIN racha r ON r.id_estacion = d.id_estacion AND r.id_contaminante = d.id_contaminante
ORDER BY d.id_contaminante, pct_dias_sobre_guia_24h DESC;

