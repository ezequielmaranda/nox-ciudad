-- =====================================================================================
-- 05 · INDICADORES: indicadores anuales por estación × contaminante × período.
--
-- Períodos (dim_periodo): 2024, 2025, 2026 parcial (ene-sep) y últimos 12 meses (comparable).
--
-- Regla del 75% (agg_completitud_anual): si el período tiene < 75% de días con dato, el
-- indicador es 'no_valido' y promedio_anual / p99_24h quedan en NULL. El valor calculado igual
-- se informa en promedio_referencial, solo para transparencia (no para sacar conclusiones).
--
-- Dos formas de comparar con la guía de 24 h (se reportan las dos):
--   * pct_dias_supera_24h: % de días sobre la guía. Fácil de comunicar.
--   * p99_24h: percentil 99 de los valores diarios. Es la definición formal de la OMS: la guía
--     de 24 h es el P99 anual (se toleran 3 o 4 días por año por encima).
--
-- nivel_oms (guía anual): el escalón más exigente que el promedio no supera.
-- ug_para_proximo_nivel: cuánto tendría que bajar el promedio para subir un escalón.
-- =====================================================================================
with diario as (
    select d.*, p.id_periodo
    from {{ ref('agg_cumplimiento_diario') }} as d
    join {{ ref('dim_periodo') }} as p
        on d.fecha between p.fecha_desde and p.fecha_hasta
),

resumen as (
    select
        id_estacion,
        id_contaminante,
        id_periodo,
        avg(valor)                               as promedio_calculado,
        quantile_cont(valor, 0.99)               as p99_calculado,
        max(valor)                               as maximo_diario,
        count(*) filter (where supera_guia)      as n_dias_supera_24h
    from diario
    group by id_estacion, id_contaminante, id_periodo
),

-- Guías en columnas: una fila por contaminante con la guía de 24 h y la anual (si existe).
guias as (
    select
        id_contaminante,
        max(guia_oms) filter (where promedio = '24h')   as guia_24h,
        max(guia_oms) filter (where promedio = 'anual') as guia_anual,
        max(it1)      filter (where promedio = 'anual') as it1_anual,
        max(it2)      filter (where promedio = 'anual') as it2_anual,
        max(it3)      filter (where promedio = 'anual') as it3_anual,
        max(it4)      filter (where promedio = 'anual') as it4_anual,
        max(unidad)                                     as unidad
    from {{ ref('ref_oms') }}
    group by id_contaminante
),

base as (
    select
        c.id_estacion,
        c.id_contaminante,
        c.id_periodo,
        p.etiqueta                                              as periodo,
        p.tipo_periodo,
        p.anio,
        c.n_dias_periodo,
        c.n_dias_con_dato,
        c.completitud,
        c.es_valido,
        c.completitud_peor_trimestre,
        c.cumple_criterio_trimestral,
        case when c.es_valido then 'valido' else 'no_valido' end as estado_indicador,
        g.unidad,
        round(r.promedio_calculado, 2)                          as promedio_referencial,
        case when c.es_valido then round(r.promedio_calculado, 2) end as promedio_anual,
        g.guia_anual,
        g.it1_anual, g.it2_anual, g.it3_anual, g.it4_anual,
        case when c.es_valido then round(r.p99_calculado, 2) end as p99_24h,
        g.guia_24h,
        round(r.maximo_diario, 2)                               as maximo_diario,
        coalesce(r.n_dias_supera_24h, 0)                        as n_dias_supera_24h
    from {{ ref('agg_completitud_anual') }} as c
    join guias as g using (id_contaminante)             -- deja solo contaminantes con guía OMS
    join {{ ref('dim_periodo') }} as p using (id_periodo)
    left join resumen as r using (id_estacion, id_contaminante, id_periodo)
)

select
    id_estacion,
    id_contaminante,
    id_periodo,
    periodo,
    tipo_periodo,
    anio,
    n_dias_periodo,
    n_dias_con_dato,
    completitud,
    es_valido,
    completitud_peor_trimestre,
    cumple_criterio_trimestral,
    estado_indicador,
    unidad,
    promedio_anual,
    promedio_referencial,
    guia_anual,
    round(promedio_anual / guia_anual, 2)                       as veces_guia_anual,
    case
        when promedio_anual is null or guia_anual is null then null
        when promedio_anual <= guia_anual then 'AQG'
        when promedio_anual <= it4_anual  then 'IT4'
        when promedio_anual <= it3_anual  then 'IT3'
        when promedio_anual <= it2_anual  then 'IT2'
        when promedio_anual <= it1_anual  then 'IT1'
        else '> IT1'
    end                                                         as nivel_oms,
    case
        when promedio_anual is null or guia_anual is null then null
        when promedio_anual <= guia_anual then 1
        when promedio_anual <= it4_anual  then 2
        when promedio_anual <= it3_anual  then 3
        when promedio_anual <= it2_anual  then 4
        when promedio_anual <= it1_anual  then 5
        else 6
    end                                                         as orden_nivel_oms,
    -- Próximo escalón: el umbral más alto que el promedio todavía supera
    case
        when promedio_anual > it1_anual  then 'IT1'
        when promedio_anual > it2_anual  then 'IT2'
        when promedio_anual > it3_anual  then 'IT3'
        when promedio_anual > it4_anual  then 'IT4'
        when promedio_anual > guia_anual then 'AQG'
    end                                                         as proximo_nivel,
    round(promedio_anual - coalesce(
        case when promedio_anual > it1_anual  then it1_anual end,
        case when promedio_anual > it2_anual  then it2_anual end,
        case when promedio_anual > it3_anual  then it3_anual end,
        case when promedio_anual > it4_anual  then it4_anual end,
        case when promedio_anual > guia_anual then guia_anual end
    ), 2)                                                       as ug_para_proximo_nivel,
    p99_24h,
    guia_24h,
    round(p99_24h / guia_24h, 2)                                as p99_veces_guia_24h,
    p99_24h > guia_24h                                          as p99_supera_guia_24h,
    maximo_diario,
    n_dias_supera_24h,
    round(n_dias_supera_24h * 1.0 / nullif(n_dias_con_dato, 0), 4) as pct_dias_supera_24h
from base
