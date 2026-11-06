-- =====================================================================================
-- 05 · INDICADORES: cumplimiento diario de la guía OMS de 24 h.
--
-- Grano: fecha × estación × contaminante, solo días con dato válido (promedio de 24 h) y solo
-- contaminantes con guía de 24 h (NO2, PM10, CO): el INNER JOIN con ref_oms hace ese filtro.
--
-- nivel_oms: el escalón más exigente cuyo umbral el valor NO supera.
--   AQG = cumple la guía · IT4 … IT1 = cumple solo un objetivo intermedio · '> IT1' = no cumple
--   ni el menos exigente. Un umbral vacío (NULL) hace falsa la comparación y se saltea.
-- =====================================================================================
with diario as (
    select fecha, id_estacion, id_contaminante, valor_masa, unidad_masa, es_outlier
    from {{ ref('fact_medicion_diaria') }}
    where ventana = '24h'
      and tiene_dato
),

guia as (
    select id_contaminante, guia_oms, it1, it2, it3, it4
    from {{ ref('ref_oms') }}
    where promedio = '24h'
)

select
    d.fecha,
    d.id_estacion,
    d.id_contaminante,
    d.valor_masa                              as valor,
    d.unidad_masa                             as unidad,
    g.guia_oms                                as guia_oms_24h,
    d.valor_masa > g.guia_oms                 as supera_guia,
    round(d.valor_masa / g.guia_oms, 3)       as veces_guia,
    case
        when d.valor_masa <= g.guia_oms then 'AQG'
        when d.valor_masa <= g.it4      then 'IT4'
        when d.valor_masa <= g.it3      then 'IT3'
        when d.valor_masa <= g.it2      then 'IT2'
        when d.valor_masa <= g.it1      then 'IT1'
        else '> IT1'
    end                                       as nivel_oms,
    -- Orden del nivel para gráficos (1 = cumple la guía … 6 = no cumple ni el IT1)
    case
        when d.valor_masa <= g.guia_oms then 1
        when d.valor_masa <= g.it4      then 2
        when d.valor_masa <= g.it3      then 3
        when d.valor_masa <= g.it2      then 4
        when d.valor_masa <= g.it1      then 5
        else 6
    end                                       as orden_nivel_oms,
    d.es_outlier
from diario as d
join guia as g using (id_contaminante)
