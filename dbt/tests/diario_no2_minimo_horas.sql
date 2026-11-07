-- Regla de horas a día: todo promedio diario de NO2 válido tiene que salir de al menos
-- `horas_minimas_dia` horas válidas (18 de 24 = 75%, criterio de la Directiva 2008/50/CE).
select fecha, id_estacion, n_horas_validas, valor
from {{ ref('fact_medicion_diaria') }}
where id_contaminante = 'no2'
  and tiene_dato
  and n_horas_validas < {{ var('horas_minimas_dia') }}
