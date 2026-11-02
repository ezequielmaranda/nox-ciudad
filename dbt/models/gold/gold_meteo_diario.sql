-- Gold: meteorología de cada día para el análisis, una fila por día (valor de ciudad).
-- Fuente única: registro diario del SMN, estaciones Aeroparque y Observatorio Central.
--   Viento, temperatura y humedad: promedio de las dos estaciones (promedios de 24 h).
--   Lluvia: máximo diario entre las dos estaciones. Un día sin registro de PRECIP se toma como
--   sin lluvia (supuesto a declarar: el SMN solo informa algunos días).
-- Se probó usar el promedio 8-16 h de observaciones horarias (Meteostat): la regresión y la prueba
-- placebo dan prácticamente lo mismo, así que se eligió la fuente más simple y oficial.
with smn as (
    select
        fecha,
        avg(viento_medio_kmh) as viento_kmh,
        max(viento_max_kmh) as viento_max_kmh,
        avg(temp_media_c) as temp_c,
        avg(humedad_pct) as humedad_pct,
        max(precipitacion_mm) as precipitacion_mm,
        count(viento_medio_kmh) as estaciones_con_viento
    from {{ ref('silver_smn_diario') }}
    group by fecha
),

-- Hasta qué fecha llegan los datos del SMN: después de esa fecha todo es desconocido, no cero.
cobertura_smn as (
    select max(fecha) as ultima_fecha from {{ ref('silver_smn_diario') }}
)

select
    cal.fecha,
    s.viento_kmh,
    s.viento_max_kmh,
    s.temp_c,
    s.humedad_pct,
    s.estaciones_con_viento,
    coalesce(s.precipitacion_mm, 0) as precipitacion_mm,
    s.precipitacion_mm is null as precipitacion_sin_registro,
    coalesce(s.precipitacion_mm, 0) >= 1 as hubo_lluvia
from {{ ref('dim_calendario') }} as cal
cross join cobertura_smn
left join smn as s using (fecha)
where cal.fecha <= cobertura_smn.ultima_fecha
