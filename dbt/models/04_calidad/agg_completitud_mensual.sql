-- =====================================================================================
-- 04 · CALIDAD: completitud por estación × contaminante × mes (promedio de 24 h).
--
-- completitud = días con dato válido / días del mes. Desglosa los días sin dato en:
--   sin_fila        la fuente no publicó ese día (p. ej. mes sin PDF)
--   sin_dato_fuente la planilla dice 's/d' o 'DND'
--   descartados     había número pero lo descartó una regla de calidad (stg_aire_validado)
-- Es la tabla del heatmap de completitud (EDA y página de calidad del dashboard).
-- =====================================================================================
select
    f.id_estacion,
    f.id_contaminante,
    c.anio,
    c.mes,
    c.anio_mes,
    count(*)                                                                  as n_dias_calendario,
    count(*) filter (where f.tiene_fila)                                      as n_dias_con_fila,
    count(*) filter (where f.tiene_dato)                                      as n_dias_con_dato,
    count(*) filter (where f.motivo_sin_dato = 'sin_fila')                    as n_dias_sin_fila,
    count(*) filter (where f.motivo_sin_dato = 'sin_dato_fuente')             as n_dias_sin_dato_fuente,
    count(*) filter (where f.tiene_fila and not f.tiene_dato
                       and f.motivo_sin_dato <> 'sin_dato_fuente')            as n_dias_descartados,
    round(count(*) filter (where f.tiene_dato) * 1.0 / count(*), 4)           as completitud,
    count(*) filter (where f.tiene_dato) * 1.0 / count(*)
        >= {{ var('umbral_completitud') }}                                    as cumple_umbral
from {{ ref('fact_medicion_diaria') }} as f
join {{ ref('dim_calendario') }} as c using (fecha)
where f.ventana = '24h'
group by f.id_estacion, f.id_contaminante, c.anio, c.mes, c.anio_mes
