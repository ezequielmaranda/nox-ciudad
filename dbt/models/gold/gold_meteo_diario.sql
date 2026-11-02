-- Gold: meteorología de cada día para el análisis, una fila por día (valor de ciudad).
-- Viento y temperatura: promedio de las observaciones horarias de 8 a 16 h (horas 08 a 15, la misma
-- ventana que el bloque de calidad del aire), juntando Aeroparque y Observatorio.
-- Lluvia: máximo diario entre las dos estaciones del SMN. Un día sin registro de PRECIP se toma
-- como sin lluvia (supuesto a declarar: el SMN solo informa algunos días).
with viento_816 as (
    select
        fecha,
        avg(valor) filter (where metrica = 'wspd') as viento_816_kmh,
        avg(valor) filter (where metrica = 'temp') as temp_816_c,
        avg(valor) filter (where metrica = 'rhum') as humedad_816_pct,
        count(*) filter (where metrica = 'wspd') as horas_con_viento,
        -- Dirección media vectorial (no se puede promediar grados directamente: 350° y 10° dan 180°).
        (degrees(atan2(avg(sin(radians(valor))) filter (where metrica = 'wdir'),
                       avg(cos(radians(valor))) filter (where metrica = 'wdir'))) + 360) % 360
            as viento_816_dir_grados
    from {{ ref('silver_meteo_horaria') }}
    where hora between 8 and 15
    group by fecha
),

lluvia as (
    select fecha, max(precipitacion_mm) as precipitacion_mm
    from {{ ref('silver_smn_diario') }}
    group by fecha
),

-- Hasta qué fecha llegan los datos del SMN: después de esa fecha la lluvia es desconocida, no cero.
cobertura_smn as (
    select max(fecha) as ultima_fecha from {{ ref('silver_smn_diario') }}
)

select
    cal.fecha,
    v.viento_816_kmh,
    v.viento_816_dir_grados,
    v.temp_816_c,
    v.humedad_816_pct,
    v.horas_con_viento,
    case when cal.fecha <= cobertura_smn.ultima_fecha
        then coalesce(l.precipitacion_mm, 0) end as precipitacion_mm,
    l.precipitacion_mm is null as precipitacion_sin_registro,
    case when cal.fecha <= cobertura_smn.ultima_fecha
        then coalesce(l.precipitacion_mm, 0) >= 1 end as hubo_lluvia
from {{ ref('dim_calendario') }} as cal
cross join cobertura_smn
left join viento_816 as v using (fecha)
left join lluvia as l using (fecha)
where cal.fecha <= (select max(fecha) from {{ ref('silver_meteo_horaria') }})
