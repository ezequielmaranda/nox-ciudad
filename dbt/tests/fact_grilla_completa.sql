-- La fact tiene exactamente una fila por día × estación × contaminante × ventana (2 ventanas).
-- Si faltara alguna combinación, el conteo de días faltantes dejaría de ser confiable.
with esperado as (
    select
        (select count(*) from {{ ref('dim_calendario') }})
      * (select count(*) from {{ ref('dim_estacion') }})
      * (select count(*) from {{ ref('dim_contaminante') }})
      * 2 as filas
),
real as (
    select count(*) as filas from {{ ref('fact_medicion_diaria') }}
)
select esperado.filas as esperado, real.filas as real
from esperado, real
where esperado.filas <> real.filas
