-- Silver: datos diarios del SMN, una fila por estación y día.
-- VTO_MDIR viene en decenas de grado: se pasa a grados.
-- PRECIP solo figura en una parte de los días: un día sin registro queda nulo, no cero
-- (se decide en gold cómo tratarlo).
select
    estacion,
    cast(fecha as date) as fecha,
    max(try_cast(valor as double)) filter (where metrica = 'TMEDIA') as temp_media_c,
    max(try_cast(valor as double)) filter (where metrica = 'TMAX') as temp_max_c,
    max(try_cast(valor as double)) filter (where metrica = 'TMIN') as temp_min_c,
    max(try_cast(valor as double)) filter (where metrica = 'HUM_REL') as humedad_pct,
    max(try_cast(valor as double)) filter (where metrica = 'PRE_EST') as presion_hpa,
    max(try_cast(valor as double)) filter (where metrica = 'VEL_MED') as viento_medio_kmh,
    max(try_cast(valor as double)) filter (where metrica = 'VTO_MVEL') as viento_max_kmh,
    max(try_cast(valor as double)) filter (where metrica = 'VTO_MDIR') * 10 as viento_max_dir_grados,
    max(try_cast(valor as double)) filter (where metrica = 'NUB_TOT') as nubosidad_octavos,
    max(try_cast(valor as double)) filter (where metrica = 'HELIOF') as heliofania_h,
    max(try_cast(valor as double)) filter (where metrica = 'PRECIP') as precipitacion_mm
from {{ ref('bronze_smn') }}
group by estacion, cast(fecha as date)
