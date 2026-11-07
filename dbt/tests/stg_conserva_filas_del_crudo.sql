-- "No se borra ninguna fila": el staging tiene exactamente una fila por cada celda del CSV
-- crudo de las 3 estaciones (filas del CSV × 3 estaciones × 3 contaminantes). Si el UNPIVOT, un
-- filtro o un JOIN perdiera o duplicara filas, falla.
with crudo as (
    select count(*) * 9 as filas
    from read_csv('../data/raw/calidad-aire.csv', header = true, all_varchar = true)
),
staging as (
    select count(*) as filas from {{ ref('stg_aire_horario_validado') }}
)
select crudo.filas as filas_esperadas, staging.filas as filas_staging
from crudo, staging
where crudo.filas <> staging.filas
