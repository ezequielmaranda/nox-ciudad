-- =====================================================================================
-- 04 · CALIDAD: completitud por estación × contaminante × mes (promedio de 24 h).
--
-- completitud = días con dato válido / días del mes. Desglosa los días sin dato en:
--   sin_fila         la fuente no tiene ninguna hora de ese día
--   sin_dato_fuente  todas las horas del día dicen 's/d'
--   incompletos      hay horas pero no alcanzan para el valor diario (ver stg_aire_diario)
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
    count(*) filter (where f.motivo_sin_dato = 'incompleto')                  as n_dias_incompletos,
    round(count(*) filter (where f.tiene_dato) * 1.0 / count(*), 4)           as completitud,
    count(*) filter (where f.tiene_dato) * 1.0 / count(*)
        >= {{ var('umbral_completitud') }}                                    as cumple_umbral
from {{ ref('fact_medicion_diaria') }} as f
join {{ ref('dim_calendario') }} as c using (fecha)
group by f.id_estacion, f.id_contaminante, c.anio, c.mes, c.anio_mes
