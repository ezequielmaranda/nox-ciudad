-- Los outliers se MARCAN, no se borran: todo valor marcado como atípico conserva su dato válido
-- (tiene_dato y valor). Si una regla futura los anulara, este test falla.
select fecha, id_estacion, id_contaminante, ventana, valor, tiene_dato
from {{ ref('fact_medicion_diaria') }}
where es_outlier
  and (not tiene_dato or valor is null or valor_masa is null)
