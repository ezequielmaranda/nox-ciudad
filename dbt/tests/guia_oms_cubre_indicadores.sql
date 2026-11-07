-- Cada guía que usan los indicadores existe en la tabla de la OMS: 24 h para NO2, PM10 y CO, y
-- anual para NO2 y PM10. Si alguien borra una fila del CSV de referencia, este test falla en
-- lugar de dejar indicadores vacíos sin aviso.
with necesarias as (
    select * from (values
        ('no2', '24h'), ('pm10', '24h'), ('co', '24h'),
        ('no2', 'anual'), ('pm10', 'anual')
    ) as t(id_contaminante, promedio)
)
select n.*
from necesarias as n
left join {{ ref('guia_oms') }} as g
    on g.id_contaminante = n.id_contaminante and g.promedio = n.promedio and g.nivel = 'AQG'
where g.id_contaminante is null
