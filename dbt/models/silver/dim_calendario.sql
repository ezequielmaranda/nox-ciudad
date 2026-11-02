-- Dimensión de fechas: un registro por día del período de estudio.
-- Tipo de día: hábil, sábado, domingo o feriado (feriados desde el seed `feriados`).
-- Día normal: hábil, no feriado y con actividad de transporte típica según SUBE
-- (ver silver_sube_actividad_diaria). Es el universo de comparación del análisis.
with dias as (
    select cast(d as date) as fecha
    from generate_series(date '2024-01-01', date '2026-12-31', interval 1 day) as t(d)
)

select
    dias.fecha,
    year(dias.fecha) as anio,
    month(dias.fecha) as mes,
    isodow(dias.fecha) as dia_semana,  -- 1 = lunes ... 7 = domingo
    case isodow(dias.fecha)
        when 1 then 'lunes' when 2 then 'martes' when 3 then 'miércoles' when 4 then 'jueves'
        when 5 then 'viernes' when 6 then 'sábado' when 7 then 'domingo' end as nombre_dia,
    feriados.nombre as feriado,
    case
        when feriados.fecha is not null then 'feriado'
        when isodow(dias.fecha) = 6 then 'sábado'
        when isodow(dias.fecha) = 7 then 'domingo'
        else 'hábil'
    end as tipo_dia,
    coalesce(actividad.es_dia_normal, false) as es_dia_normal,
    eventos.evento,
    eventos.grupo as grupo_evento,
    eventos.pct_lineas_paradas_caba
from dias
left join {{ ref('feriados') }} as feriados on feriados.fecha = dias.fecha
left join {{ ref('eventos') }} as eventos on eventos.fecha = dias.fecha
left join {{ ref('silver_sube_actividad_diaria') }} as actividad on actividad.fecha = dias.fecha
