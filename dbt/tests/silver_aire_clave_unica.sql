-- Cada estación, fecha, contaminante y estadístico aparece una sola vez.
select estacion, fecha, contaminante, estadistico, count(*) as n
from {{ ref('silver_aire') }}
group by all
having count(*) > 1
