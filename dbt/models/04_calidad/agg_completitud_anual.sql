-- =====================================================================================
-- 04 · CALIDAD: completitud por estación × contaminante × período y REGLA DEL 75%.
--
-- Un indicador anual (promedio anual, percentil 99) solo es válido si el período tiene al
-- menos 75% de días con dato válido (variable umbral_completitud). Con menos, el promedio
-- puede estar sesgado por la época del año que falta (p. ej. sin invierno da más bajo).
--
-- De dónde sale el 75% (ver docs/calidad_datos.md, sección 3):
--   * La OMS (2021) no fija un criterio de completitud.
--   * EPA de EE.UU. (40 CFR 50, Apéndice S, NO2): el promedio anual es válido con al menos 75%
--     de las horas del año; para la norma de 1 hora pide además 75% en CADA trimestre.
--   * Unión Europea (Directiva 2008/50/CE, Anexo XI): 75% para pasar de horas a día (18 de 24
--     horas, que se aplica en stg_aire_diario), pero 90% para el promedio anual.
-- Se usa el 75% anual (criterio EPA) y se informa además el criterio trimestral de la EPA
-- (cumple_criterio_trimestral) como advertencia: marca años válidos a los que les falta buena
-- parte de una estación del año. No excluye: es información para leer el resultado.
-- =====================================================================================
with diario as (
    select
        f.id_estacion,
        f.id_contaminante,
        p.id_periodo,
        f.tiene_dato,
        -- trimestre calendario (2025-T3 = 20253). EXTRACT es SQL estándar.
        extract(year from f.fecha) * 10 + extract(quarter from f.fecha) as trimestre
    from {{ ref('fact_medicion_diaria') }} as f
    join {{ ref('dim_periodo') }} as p
        on f.fecha between p.fecha_desde and p.fecha_hasta
),

por_trimestre as (
    select id_estacion, id_contaminante, id_periodo, trimestre, avg(tiene_dato::int) as completitud
    from diario
    group by id_estacion, id_contaminante, id_periodo, trimestre
),

peor_trimestre as (
    select id_estacion, id_contaminante, id_periodo, min(completitud) as completitud_peor_trimestre
    from por_trimestre
    group by id_estacion, id_contaminante, id_periodo
)

select
    d.id_estacion,
    d.id_contaminante,
    d.id_periodo,
    count(*)                                                        as n_dias_periodo,
    count(*) filter (where d.tiene_dato)                            as n_dias_con_dato,
    round(count(*) filter (where d.tiene_dato) * 1.0 / count(*), 4) as completitud,
    count(*) filter (where d.tiene_dato) * 1.0 / count(*)
        >= {{ var('umbral_completitud') }}                          as es_valido,
    round(t.completitud_peor_trimestre, 4)                          as completitud_peor_trimestre,
    t.completitud_peor_trimestre >= {{ var('umbral_completitud') }} as cumple_criterio_trimestral
from diario as d
join peor_trimestre as t using (id_estacion, id_contaminante, id_periodo)
group by d.id_estacion, d.id_contaminante, d.id_periodo, t.completitud_peor_trimestre
