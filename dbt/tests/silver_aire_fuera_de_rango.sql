{{ config(severity = 'warn') }}
-- Valores negativos o físicamente imposibles. Quedan en silver marcados, pero no pasan a gold.
select estacion, fecha, contaminante, estadistico, valor_crudo
from {{ ref('silver_aire') }}
where fuera_de_rango
