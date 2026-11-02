-- Silver: meteorología horaria OBSERVADA (se descartan los pronósticos marcados como 'modelo').
-- La hora queda en hora local de Buenos Aires (la fuente ya viene en -03:00).
-- Grano: estación × hora × métrica.
select
    estacion,
    cast(substr(fecha_hora, 1, 19) as timestamp) as fecha_hora_local,
    cast(substr(fecha_hora, 1, 10) as date) as fecha,
    cast(substr(fecha_hora, 12, 2) as integer) as hora,
    metrica,
    try_cast(valor as double) as valor,
    unidad,
    fuente
from {{ ref('bronze_meteostat') }}
where fuente_tipo = 'observacion'
