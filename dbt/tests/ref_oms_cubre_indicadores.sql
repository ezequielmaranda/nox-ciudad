-- Cada combinación contaminante × promedio que usan los indicadores existe en ref_oms:
-- 24 h para NO2, PM10 y CO, y anual para NO2 y PM10. Si alguien borra una fila del CSV de
-- referencia, este test falla en lugar de dejar indicadores vacíos sin aviso.
with necesarias as (
    select * from (values
        ('no2', '24h'), ('pm10', '24h'), ('co', '24h'),
        ('no2', 'anual'), ('pm10', 'anual')
    ) as t(id_contaminante, promedio)
)
select n.*
from necesarias as n
left join {{ ref('ref_oms') }} as r using (id_contaminante, promedio)
where r.id_contaminante is null
