-- =====================================================================================
-- GOLD · CALIDAD: qué pasó con cada valor horario del período de estudio.
--
-- Grano: contaminante × categoría. Categoría = 'valido', 'valido_imputado' ('<LD' reemplazado
-- por LD/2) o el motivo por el que se descartó (las reglas de silver.medicion_horaria). Además
-- del conteo, dice en cuántos días y entre qué fechas aparece cada categoría: así se ve que,
-- por ejemplo, los '#REF!' son de dos días puntuales y no un problema repartido.
-- =====================================================================================
with horas as (
    select
        id_contaminante,
        fecha,
        case
            when es_valido and es_imputado then 'valido_imputado'
            when es_valido                 then 'valido'
            else motivo_invalido
        end as categoria
    from {{ ref('medicion_horaria') }}
    where fecha between '{{ var("fecha_inicio") }}' and '{{ var("fecha_fin") }}'
)

select
    id_contaminante,
    categoria,
    count(*)                                                                         as n_valores,
    round(count(*) * 1.0 / sum(count(*)) over (partition by id_contaminante), 4)     as proporcion,
    count(distinct fecha)                                                            as n_dias,
    min(fecha)                                                                       as primera_fecha,
    max(fecha)                                                                       as ultima_fecha
from horas
group by id_contaminante, categoria
