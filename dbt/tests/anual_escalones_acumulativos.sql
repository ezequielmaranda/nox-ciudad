-- El cumplimiento por escalón es acumulativo: un día que cumple un nivel más exigente cumple
-- también todos los menos exigentes. Por eso, en cada fila de agg_anual, el % de días que cumple
-- la guía <= IT4 <= IT3 <= IT2 <= IT1 (comparando solo los niveles que existen).
select id_estacion, id_contaminante, id_periodo,
       pct_cumple_guia_24h, pct_cumple_it4_24h, pct_cumple_it3_24h, pct_cumple_it2_24h, pct_cumple_it1_24h
from {{ ref('agg_anual') }}
where pct_cumple_guia_24h > coalesce(pct_cumple_it4_24h, pct_cumple_it3_24h, pct_cumple_it2_24h, pct_cumple_it1_24h)
   or pct_cumple_it4_24h  > coalesce(pct_cumple_it3_24h, pct_cumple_it2_24h, pct_cumple_it1_24h)
   or pct_cumple_it3_24h  > coalesce(pct_cumple_it2_24h, pct_cumple_it1_24h)
   or pct_cumple_it2_24h  > pct_cumple_it1_24h
