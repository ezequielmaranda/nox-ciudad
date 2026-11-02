-- Los porcentajes de líneas paradas tienen que estar entre 0 y 100.
select fecha, pct_lineas_paradas, pct_lineas_paradas_ponderado
from {{ ref('gold_sube_diario') }}
where pct_lineas_paradas not between 0 and 100
   or pct_lineas_paradas_ponderado not between 0 and 100
