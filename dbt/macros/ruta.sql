{#
  Ruta a un archivo del repo, relativa a la raíz (variable de entorno AIRE_RAIZ, por defecto "..").
  Uso: {{ ruta('data/raw/aire_publico.csv') }}
#}
{% macro ruta(relativa) -%}
    {{ env_var('AIRE_RAIZ', '..') ~ '/' ~ relativa }}
{%- endmacro %}
