-- "No se borra ninguna fila": silver.medicion_horaria tiene exactamente una fila por cada celda
-- del crudo de las 3 estaciones (filas de bronze × 3 estaciones × 3 contaminantes). Si el
-- UNPIVOT, un filtro o un JOIN perdiera o duplicara filas, falla.
with crudo as (
    select count(*) * 9 as filas from {{ ref('calidad_aire') }}
),
silver as (
    select count(*) as filas from {{ ref('medicion_horaria') }}
)
select crudo.filas as filas_esperadas, silver.filas as filas_silver
from crudo, silver
where crudo.filas <> silver.filas
