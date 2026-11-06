-- "No se borra ninguna fila": el staging tiene exactamente las mismas filas que el CSV crudo
-- (una por celda de los PDF). Si un filtro o un JOIN perdiera o duplicara filas, falla.
with crudo as (
    select count(*) as filas
    from read_csv('{{ ruta("data/raw/aire_publico.csv") }}', header = true, all_varchar = true)
),
staging as (
    select count(*) as filas from {{ ref('stg_aire') }}
)
select crudo.filas as filas_crudo, staging.filas as filas_staging
from crudo, staging
where crudo.filas <> staging.filas
