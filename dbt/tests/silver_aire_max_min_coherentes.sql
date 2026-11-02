{{ config(severity = 'warn') }}
-- Coherencia física: el promedio de cada bloque de 8 h tiene que estar entre el mínimo y el
-- máximo horario del día (con 1 unidad de tolerancia por redondeo).
with v as (
    select estacion, fecha, contaminante,
        max(valor) filter (where estadistico = 'max_1h') as maximo,
        max(valor) filter (where estadistico = 'min_1h') as minimo,
        max(valor) filter (where estadistico = '8-16')   as bloque_816
    from {{ ref('silver_aire') }}
    where estado_valor = 'valido'
    group by all
)
select *
from v
where bloque_816 > maximo + 1 or bloque_816 < minimo - 1
