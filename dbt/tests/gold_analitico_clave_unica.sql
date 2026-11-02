-- Una fila por estación y día en la tabla del análisis (los joins no tienen que duplicar filas).
select estacion, fecha, count(*) as n
from {{ ref('gold_analitico') }}
group by all
having count(*) > 1
