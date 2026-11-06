{#
  Test genérico: los valores de la columna están entre un mínimo y un máximo (inclusive).
  Los NULL no se evalúan (para eso está not_null).
#}
{% test entre(model, column_name, minimo, maximo) %}
select *
from {{ model }}
where {{ column_name }} < {{ minimo }} or {{ column_name }} > {{ maximo }}
{% endtest %}
