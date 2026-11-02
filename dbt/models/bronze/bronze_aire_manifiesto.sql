-- Bronze: el manifiesto de la extracción (un registro por PDF, con su estado y avisos).
-- Sirve para documentar en el TP qué archivos se descartaron y por qué.
select
    *,
    current_timestamp as fecha_carga
from read_csv(
    '{{ ruta("data/landing/aire_publico_manifiesto.csv") }}',
    header = true,
    all_varchar = true
)
