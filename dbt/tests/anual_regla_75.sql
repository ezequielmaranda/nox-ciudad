-- Regla del 75%: todo indicador anual con completitud < 75% está marcado como no válido y no
-- tiene promedio_anual ni p99; y todo indicador con completitud >= 75% está marcado válido.
select *
from {{ ref('agg_anual') }}
where (completitud <  {{ var('umbral_completitud') }} and (es_valido or promedio_anual is not null or p99_24h is not null))
   or (completitud >= {{ var('umbral_completitud') }} and not es_valido)
