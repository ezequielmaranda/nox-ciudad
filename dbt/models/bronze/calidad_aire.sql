-- =====================================================================================
-- BRONZE · el CSV de BA Data tal como llega, sin tocar.
--
-- Bronze es la copia fiel de la fuente dentro de la base: las mismas filas y columnas que
-- data/raw/calidad-aire.csv, todo como texto (all_varchar). No se corrige nada acá: si algo
-- está mal en la fuente, se ve igual que en el archivo. Formato ANCHO: una fila por fecha y
-- hora, una columna por estación × contaminante (CO_CENTENARIO, NO2_CENTENARIO, ...).
-- Las tablas de referencia (seeds de data/reference/) también viven en bronze.
-- =====================================================================================
select *
from read_csv('../data/raw/calidad-aire.csv', header = true, all_varchar = true)
