{#
  Ruta a un archivo del repo, relativa a la raíz (NOX_RAIZ, por defecto "..").
  Uso: {{ ruta('data/landing/aire_publico.csv') }}
#}
{% macro ruta(relativa) -%}
    {{ env_var('NOX_RAIZ', '..') ~ '/' ~ relativa }}
{%- endmacro %}
