-- Aviso (no frena el pipeline): cuántos valores horarios del período de estudio descartó una
-- regla de calidad (no cuenta los 's/d', que son falta de dato, ni las horas inválidas vacías).
-- Describe la fuente: esos valores ya quedan fuera del análisis. Detalle en gold.calidad_resumen
-- y en docs/calidad_datos.md.
{{ config(severity = 'warn') }}
select fecha, hora, id_estacion, id_contaminante, valor_crudo, motivo_invalido
from {{ ref('medicion_horaria') }}
where fecha between '{{ var("fecha_inicio") }}' and '{{ var("fecha_fin") }}'
  and motivo_invalido in ('texto_invalido', 'fuera_de_rango', 'fila_en_cero', 'valor_trabado')
