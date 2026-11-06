-- =====================================================================================
-- 05 · INDICADORES: % de días que cumplen cada escalón de la OMS (guía y objetivos
-- intermedios de 24 h), por estación × contaminante × período.
--
-- "Cumple un nivel" = el promedio de 24 h no supera su umbral. Es acumulativo: un día que
-- cumple la guía también cumple todos los objetivos intermedios. Por eso, dentro de cada
-- estación y período, el % crece de la guía (más exigente) al IT1 (menos exigente).
--
-- Es la "matriz de escalones": responde hasta qué escalón cumple cada estación (subpreguntas 1 y 2).
-- Regla del 75%: en los períodos con menos de 75% de días con dato, pct_dias_cumple queda
-- en NULL (el valor calculado igual se informa en pct_referencial).
-- Grano: estación × contaminante × período × nivel.
-- =====================================================================================
with diario as (
    select d.id_estacion, d.id_contaminante, d.valor, p.id_periodo
    from {{ ref('agg_cumplimiento_diario') }} as d
    join {{ ref('dim_periodo') }} as p
        on d.fecha between p.fecha_desde and p.fecha_hasta
),

niveles as (
    select id_contaminante, nivel, nivel_etiqueta, orden_exigencia, umbral, unidad
    from {{ ref('ref_oms_niveles') }}
    where promedio = '24h'
),

conteo as (
    select
        d.id_estacion,
        d.id_contaminante,
        d.id_periodo,
        n.nivel,
        n.nivel_etiqueta,
        n.orden_exigencia,
        n.umbral,
        n.unidad,
        count(*)                                   as n_dias_con_dato,
        count(*) filter (where d.valor <= n.umbral) as n_dias_cumple
    from diario as d
    join niveles as n using (id_contaminante)
    group by d.id_estacion, d.id_contaminante, d.id_periodo,
             n.nivel, n.nivel_etiqueta, n.orden_exigencia, n.umbral, n.unidad
)

select
    c.id_estacion,
    c.id_contaminante,
    c.id_periodo,
    c.nivel,
    c.nivel_etiqueta,
    c.orden_exigencia,
    c.umbral,
    c.unidad,
    c.n_dias_con_dato,
    c.n_dias_cumple,
    a.completitud,
    a.es_valido,
    a.cumple_criterio_trimestral,
    case when a.es_valido then round(c.n_dias_cumple * 1.0 / c.n_dias_con_dato, 4) end as pct_dias_cumple,
    round(c.n_dias_cumple * 1.0 / c.n_dias_con_dato, 4)                                as pct_referencial
from conteo as c
join {{ ref('agg_completitud_anual') }} as a using (id_estacion, id_contaminante, id_periodo)
