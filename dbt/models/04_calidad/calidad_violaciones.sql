-- =====================================================================================
-- 04 · CALIDAD: listado de cada violación a una regla de validación (una fila por regla).
-- Un mismo valor puede violar más de una regla. `se_descarta` indica si el valor quedó fuera
-- del análisis (algunas reglas se informan pero no descartan: ver stg_aire_validado).
-- =====================================================================================
with v as (
    select * from {{ ref('stg_aire_validado') }}
),

reglas as (
    select *, 'texto_invalido' as regla from v where estado_valor = 'invalido'
    union all
    select *, 'fuera_de_rango' from v where fuera_de_rango
    union all
    select *, 'valor_trabado' from v where valor_trabado
    union all
    select *, 'cero_sin_respaldo' from v where cero_sin_respaldo
    union all
    select *, 'fuera_de_max_min' from v where fuera_de_max_min
    union all
    select *, 'promedio_incoherente' from v where promedio_incoherente
    union all
    select *, 'no_mayor_que_nox' from v where no_mayor_que_nox and id_contaminante = 'no'
    union all
    select *, 'no2_mayor_que_nox' from v where no2_mayor_que_nox and id_contaminante = 'no2'
    union all
    select *, 'nox_incoherente' from v where nox_incoherente
)

select
    id_estacion,
    fecha,
    id_contaminante,
    estadistico,
    valor_crudo,
    regla,
    not es_valido      as se_descarta,
    motivo_invalido,
    archivo_pdf
from reglas
