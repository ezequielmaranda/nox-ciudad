{#
  Por defecto dbt arma el schema como <schema_del_perfil>_<schema_custom> (p. ej. main_bronze).
  Para que las capas se llamen exactamente bronze, silver y gold, se usa el nombre custom tal cual.
#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}
        {{ target.schema }}
    {%- else -%}
        {{ custom_schema_name | trim }}
    {%- endif -%}
{%- endmacro %}
