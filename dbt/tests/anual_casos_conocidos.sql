-- Casos documentados en docs/calidad_datos.md que la regla del 75% tiene que dejar afuera:
-- el NO2 de Centenario en 2024 (la fuente no publicó NOx de marzo a noviembre) y el CO de
-- Córdoba en 2024 (sin CO en enero, abril y mayo). Si alguno aparece válido, algo cambió.
select id_estacion, id_contaminante, id_periodo, completitud, es_valido
from {{ ref('agg_anual') }}
where id_periodo = '2024'
  and ((id_estacion = 'centenario' and id_contaminante = 'no2')
    or (id_estacion = 'cordoba'    and id_contaminante = 'co'))
  and es_valido
