-- Bronze: datos diarios del Servicio Meteorológico Nacional (Aeroparque y Observatorio), tal cual.
select
    *,
    current_timestamp as fecha_carga
from read_csv(
    '{{ ruta("data/landing/smn.csv") }}',
    header = true,
    all_varchar = true
)
