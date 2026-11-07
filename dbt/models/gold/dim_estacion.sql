-- =====================================================================================
-- GOLD · DIMENSIÓN ESTACIÓN: una fila por estación de monitoreo de la APrA.
-- Sale de data/reference/estaciones.csv: dirección, entorno, flujo vehicular y fuentes fijas vienen de las
-- páginas de cada estación en la web de la APrA; inicio de operación y coordenadas, del archivo
-- estaciones-ambientales.csv del dataset de BA Data; `descripcion` es redacción del equipo.
-- =====================================================================================
select
    id_estacion,
    codigo_fuente,
    nombre,
    direccion,
    entorno,
    flujo_vehicular,
    fuentes_fijas,
    inicio_operacion,
    latitud,
    longitud,
    descripcion,
    row_number() over (order by nombre) as orden
from {{ ref('estaciones') }}
