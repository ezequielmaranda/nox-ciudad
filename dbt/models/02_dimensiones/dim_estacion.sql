-- =====================================================================================
-- 02 · DIMENSIÓN ESTACIÓN: una fila por estación de monitoreo de la APrA.
-- Sale de data/reference/estaciones.csv: descripción tomada de las páginas de cada estación y
-- coordenadas del archivo estaciones-ambientales.csv del mismo dataset de BA Data.
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
