-- =====================================================================================
-- 02 · DIMENSIÓN ESTACIÓN: una fila por estación de monitoreo de la APrA.
-- Sale de data/reference/estaciones.csv (descripción tomada de las páginas de cada estación).
-- Las coordenadas son aproximadas (geocodificadas a mano a partir de la dirección).
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
    latitud_aprox,
    longitud_aprox,
    descripcion,
    row_number() over (order by nombre) as orden
from {{ ref('estaciones') }}
