-- El promedio diario de NO2 de la fact tiene que ser el promedio de sus horas válidas en
-- fact_medicion_horaria (las dos facts no se pueden contradecir).
with horas as (
    select fecha, id_estacion, avg(valor) as promedio, count(*) as n
    from {{ ref('fact_medicion_horaria') }}
    where es_valido
    group by fecha, id_estacion
)
select d.fecha, d.id_estacion, d.valor, h.promedio
from {{ ref('fact_medicion_diaria') }} as d
join horas as h using (fecha, id_estacion)
where d.id_contaminante = 'no2'
  and d.tiene_dato
  and abs(d.valor - h.promedio) > 0.01
