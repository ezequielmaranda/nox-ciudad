-- Una fila por estación y día en la tabla analítica.
select estacion, fecha, count(*) as n
from {{ ref('gold_aire_diario') }}
group by all
having count(*) > 1
