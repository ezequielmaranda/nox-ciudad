-- =====================================================================================
-- 05 · INDICADORES: serie larga de CONTEXTO, promedio anual por estación × contaminante ×
-- año, de `anio_contexto_desde` a `anio_contexto_hasta` (2010-2025).
--
-- No es parte del análisis principal (2024 a sep-2026): sirve para ubicar el período de
-- estudio en la historia de la red. Usa el mismo valor diario y las mismas reglas de calidad
-- que la fact (stg_aire_diario) y la misma regla del 75% de días con dato por año.
-- Solo contaminantes con guía OMS anual (NO2 y PM10): el JOIN con ref_oms hace el filtro.
-- El PM10 horario recién empieza en 2011, así que 2010 no tiene PM10.
-- =====================================================================================
with anios as (
    -- un año por fila, con cuántos días tiene (365 o 366)
    select
        anio,
        datediff('day', make_date(anio, 1, 1), make_date(anio + 1, 1, 1)) as n_dias_anio
    from range({{ var('anio_contexto_desde') }}, {{ var('anio_contexto_hasta') }} + 1) as t(anio)
),

guia_anual as (
    select id_contaminante, guia_oms, it1, it2, it3, it4, unidad
    from {{ ref('ref_oms') }}
    where promedio = 'anual'
),

diario as (
    select
        extract(year from d.fecha) as anio,
        d.id_estacion,
        d.id_contaminante,
        d.valor_diario * c.factor_masa as valor_masa
    from {{ ref('stg_aire_diario') }} as d
    join {{ ref('dim_contaminante') }} as c using (id_contaminante)
    where d.tiene_dato
),

resumen as (
    select anio, id_estacion, id_contaminante, count(*) as n_dias_con_dato, avg(valor_masa) as promedio
    from diario
    group by anio, id_estacion, id_contaminante
),

grilla as (
    select a.anio, a.n_dias_anio, e.id_estacion, g.id_contaminante, g.guia_oms, g.it1, g.it2, g.it3, g.it4, g.unidad
    from anios as a
    cross join {{ ref('dim_estacion') }} as e
    cross join guia_anual as g
),

base as (
    select
        g.*,
        coalesce(r.n_dias_con_dato, 0)                                      as n_dias_con_dato,
        round(coalesce(r.n_dias_con_dato, 0) * 1.0 / g.n_dias_anio, 4)      as completitud,
        coalesce(r.n_dias_con_dato, 0) * 1.0 / g.n_dias_anio
            >= {{ var('umbral_completitud') }}                              as es_valido,
        r.promedio
    from grilla as g
    left join resumen as r using (anio, id_estacion, id_contaminante)
)

select
    anio,
    id_estacion,
    id_contaminante,
    n_dias_anio,
    n_dias_con_dato,
    completitud,
    es_valido,
    unidad,
    case when es_valido then round(promedio, 2) end                     as promedio_anual,
    round(promedio, 2)                                                  as promedio_referencial,
    guia_oms                                                            as guia_anual,
    case when es_valido then round(promedio / guia_oms, 2) end          as veces_guia_anual,
    case
        when not es_valido     then null
        when promedio <= guia_oms then 'AQG'
        when promedio <= it4      then 'IT4'
        when promedio <= it3      then 'IT3'
        when promedio <= it2      then 'IT2'
        when promedio <= it1      then 'IT1'
        else '> IT1'
    end                                                                 as nivel_oms
from base
