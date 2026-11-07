-- =====================================================================================
-- GOLD · DIMENSIÓN ESTACIÓN: una fila por estación de monitoreo de la APrA.
-- Sale de data/reference/estaciones.csv: entorno, flujo vehicular y fuentes fijas vienen de las
-- páginas de cada estación en la web de la APrA (son la base de la hipótesis H2); las coordenadas,
-- del archivo estaciones-ambientales.csv del dataset de BA Data; `descripcion` es redacción del equipo.
-- =====================================================================================
select
    id_estacion,
    nombre,
    entorno,
    flujo_vehicular,
    fuentes_fijas,
    latitud,
    longitud,
    descripcion,
    row_number() over (order by nombre) as orden
from {{ ref('estaciones') }}
