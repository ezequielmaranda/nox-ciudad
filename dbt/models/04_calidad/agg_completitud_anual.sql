-- =====================================================================================
-- 04 · CALIDAD: completitud por estación × contaminante × período y REGLA DEL 75%.
--
-- Un indicador anual (promedio anual, percentil 99) solo es válido si el período tiene al
-- menos 75% de días con dato válido (variable umbral_completitud). Con menos, el promedio
-- puede estar sesgado por la estación del año que falta (p. ej. sin invierno da más bajo).
-- Los períodos (años, año parcial y últimos 12 meses) salen de dim_periodo.
-- =====================================================================================
select
    f.id_estacion,
    f.id_contaminante,
    p.id_periodo,
    count(*)                                                        as n_dias_periodo,
    count(*) filter (where f.tiene_dato)                            as n_dias_con_dato,
    round(count(*) filter (where f.tiene_dato) * 1.0 / count(*), 4) as completitud,
    count(*) filter (where f.tiene_dato) * 1.0 / count(*)
        >= {{ var('umbral_completitud') }}                          as es_valido
from {{ ref('fact_medicion_diaria') }} as f
join {{ ref('dim_periodo') }} as p
    on f.fecha between p.fecha_desde and p.fecha_hasta
where f.ventana = '24h'
group by f.id_estacion, f.id_contaminante, p.id_periodo
