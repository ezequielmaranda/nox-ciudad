-- El cumplimiento por escalón es acumulativo: dentro de una estación, contaminante y período,
-- el % de días que cumple un nivel menos exigente nunca puede ser menor que el de uno más exigente.
with ordenado as (
    select
        *,
        lag(pct_referencial) over (
            partition by id_estacion, id_contaminante, id_periodo order by orden_exigencia
        ) as pct_nivel_mas_exigente
    from {{ ref('agg_cumplimiento_niveles') }}
)
select *
from ordenado
where pct_referencial < pct_nivel_mas_exigente
