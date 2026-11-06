-- =====================================================================================
-- 04 · CALIDAD: cuántos valores crudos hay en cada categoría, por contaminante.
-- Grano: contaminante × categoría. Base: las 83.010 celdas de los PDF (stg_aire_validado).
-- =====================================================================================
with categorizado as (
    select
        id_contaminante,
        case
            when es_valido and es_imputado then 'valido_imputado'   -- '<LD' reemplazado por LD/2
            when es_valido                 then 'valido'
            else motivo_invalido
        end as categoria
    from {{ ref('stg_aire_validado') }}
)

select
    id_contaminante,
    categoria,
    count(*)                                                                         as n_valores,
    round(count(*) * 1.0 / sum(count(*)) over (partition by id_contaminante), 4)     as proporcion
from categorizado
group by id_contaminante, categoria
