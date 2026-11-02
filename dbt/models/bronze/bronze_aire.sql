-- Bronze: el CSV que genera extract/aire_publico.py, cargado tal cual.
-- Todo como texto: los tipos y la limpieza se resuelven en silver.
select
    estacion,
    fecha,
    contaminante,
    estadistico,
    valor_crudo,
    unidad,
    archivo,
    filename as archivo_landing,
    current_timestamp as fecha_carga
from read_csv(
    '{{ ruta("data/landing/aire_publico.csv") }}',
    header = true,
    all_varchar = true,
    filename = true
)
