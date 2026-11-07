-- =====================================================================================
-- 04 · CALIDAD: cuántos valores horarios del período de estudio hay en cada categoría, por
-- contaminante. Grano: contaminante × categoría. Base: stg_aire_horario_validado (una fila
-- por celda del CSV de BA Data), recortado al período del estudio.
-- =====================================================================================
with categorizado as (
    select
        id_contaminante,
        case
            when es_valido and es_imputado then 'valido_imputado'   -- '<LD' reemplazado por LD/2
            when es_valido                 then 'valido'
            else motivo_invalido
        end as categoria
    from {{ ref('stg_aire_horario_validado') }}
    where fecha between '{{ var("fecha_inicio") }}' and '{{ var("fecha_fin") }}'
)

select
    id_contaminante,
    categoria,
    count(*)                                                                         as n_valores,
    round(count(*) * 1.0 / sum(count(*)) over (partition by id_contaminante), 4)     as proporcion
from categorizado
group by id_contaminante, categoria
