-- Rangos físicos (consigna, sección 4.5): entre los valores que quedan como válidos en la fact,
-- ni el NO ni el NO2 pueden superar al NOx del mismo día y ventana (NOx = NO + NO2).
with dia as (
    select
        fecha, id_estacion, ventana,
        max(valor) filter (where id_contaminante = 'no')  as v_no,
        max(valor) filter (where id_contaminante = 'no2') as v_no2,
        max(valor) filter (where id_contaminante = 'nox') as v_nox
    from {{ ref('fact_medicion_diaria') }}
    where tiene_dato
    group by fecha, id_estacion, ventana
)
select *
from dia
where v_no > v_nox or v_no2 > v_nox
