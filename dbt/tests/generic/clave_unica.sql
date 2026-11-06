{#
  Test genérico: la combinación de columnas no se repite (clave primaria compuesta).
  Devuelve las combinaciones duplicadas; el test pasa si no devuelve filas.
  Uso en un .yml:   data_tests: [{clave_unica: {arguments: {columnas: [fecha, id_estacion]}}}]
#}
{% test clave_unica(model, columnas) %}
select {{ columnas | join(', ') }}, count(*) as repeticiones
from {{ model }}
group by {{ columnas | join(', ') }}
having count(*) > 1
{% endtest %}
