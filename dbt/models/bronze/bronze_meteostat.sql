-- Bronze: meteorología horaria de Meteostat (Aeroparque y Observatorio), tal cual, todo como texto.
-- Mezcla observaciones de estación (isd_lite, metar) con pronósticos (DWD MOSMIX, MET Norway):
-- la columna fuente_tipo las distingue y el filtro se hace en silver.
select
    *,
    current_timestamp as fecha_carga
from read_csv(
    '{{ ruta("data/landing/meteostat.csv") }}',
    header = true,
    all_varchar = true
)
