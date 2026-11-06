-- Aviso (no frena el pipeline): cuántos valores crudos violan alguna regla de validación.
-- Describe la fuente: esos valores ya quedan fuera del análisis. El detalle está en
-- calidad.calidad_violaciones y en docs/calidad_datos.md.
{{ config(severity = 'warn') }}
select *
from {{ ref('calidad_violaciones') }}
