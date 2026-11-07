-- Casos documentados en docs/calidad_datos.md que la regla del 75% tiene que dejar afuera:
-- el NO2 de Centenario en 2024 (la estación no tiene NO2 de marzo a octubre) y el CO de
-- Córdoba en 2024 (62% de días con dato). Si alguno aparece válido, algo cambió.
select id_estacion, id_contaminante, id_periodo, completitud, es_valido
from {{ ref('agg_anual') }}
where id_periodo = '2024'
  and ((id_estacion = 'centenario' and id_contaminante = 'no2')
    or (id_estacion = 'cordoba'    and id_contaminante = 'co'))
  and es_valido
