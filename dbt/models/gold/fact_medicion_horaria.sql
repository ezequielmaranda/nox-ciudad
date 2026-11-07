-- =====================================================================================
-- GOLD · HECHOS: fact_medicion_horaria, los valores horarios de NO2 del período de estudio.
--
-- Grano: fecha × hora × estación (solo NO2). Comparte las dimensiones de la fact diaria
-- (calendario, estación, contaminante): es una segunda tabla de hechos con otro grano.
--
-- Por qué solo NO2: es el único contaminante que la fuente publica como promedio de cada hora.
-- CO y PM10 vienen como promedios móviles (8 h y 24 h): una "serie horaria" de esos valores
-- confundiría (un pico se ve repartido en 8 o 24 horas).
--
-- Sirve para el perfil horario por tipo de día (hora pico, efecto domingo), que la fact
-- diaria no puede mostrar. Hora 1 a 24 = hora que termina (la 8 es de 07:00 a 08:00).
-- Se incluyen las horas no válidas, con su motivo, para poder contarlas.
-- =====================================================================================
select
    h.fecha,
    h.hora,
    h.id_estacion,
    h.id_contaminante,
    h.es_valido,
    case when h.es_valido then h.valor end                           as valor,
    case when h.es_valido then round(h.valor * c.factor_masa, 3) end as valor_masa
from {{ ref('medicion_horaria') }} as h
join {{ ref('dim_contaminante') }} as c using (id_contaminante)
where h.id_contaminante = 'no2'
  and h.hora between 1 and 24
  and h.fecha between '{{ var("fecha_inicio") }}' and '{{ var("fecha_fin") }}'
