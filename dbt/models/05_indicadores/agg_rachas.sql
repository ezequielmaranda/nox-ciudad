-- =====================================================================================
-- 05 · INDICADORES: rachas de días seguidos por encima de la guía de 24 h.
--
-- Criterio: una racha es una sucesión de días CON DATO que superan la guía, sin ningún día con
-- dato que la cumpla en el medio. Los huecos cortos sin dato (hasta `dias_hueco_maximo_racha`
-- = 7 días seguidos) no cortan la racha ni la alargan: se informan aparte (dias_sin_dato). Un
-- hueco más largo sí la corta (no se sabe qué pasó en esa semana). Motivo: la serie horaria de
-- BA Data tiene huecos de exportación cortos (días cortados al mediodía, algunos días sin
-- filas) que sí tienen dato en los informes mensuales de la APrA; cortar la racha en cada uno
-- la subestimaría.
--
-- Técnica "gaps and islands", aplicada sobre la secuencia de días con dato: se numeran todos
-- los días con dato (n_dia) y, aparte, solo los que superan la guía. Mientras los días que
-- superan la guía vienen seguidos dentro de la secuencia, n_dia menos ese segundo número es
-- constante: esa diferencia identifica la racha (la "isla").
--   día con dato   1     2     3     4     5        (el 4 cumple la guía)
--   supera         sí    sí    sí    no    sí
--   nro sobre      1     2     3     -     4
--   diferencia     0     0     0     -     1        -> 2 rachas: 3 días y 1 día
-- =====================================================================================
with dias as (
    select
        id_estacion,
        id_contaminante,
        fecha,
        supera_guia,
        row_number() over (partition by id_estacion, id_contaminante order by fecha) as n_dia,
        -- días sin dato entre este día y el anterior con dato
        datediff('day', lag(fecha) over (partition by id_estacion, id_contaminante order by fecha), fecha) - 1
            as dias_sin_dato_antes
    from {{ ref('agg_cumplimiento_diario') }}
),

-- Tramo: se incrementa cada vez que hay un hueco largo; una racha no puede cruzar de tramo.
tramos as (
    select
        *,
        sum(case when dias_sin_dato_antes > {{ var('dias_hueco_maximo_racha') }} then 1 else 0 end)
            over (partition by id_estacion, id_contaminante order by fecha) as tramo
    from dias
),

sobre_guia as (
    select
        id_estacion,
        id_contaminante,
        fecha,
        tramo,
        n_dia - row_number() over (partition by id_estacion, id_contaminante order by fecha) as id_racha
    from tramos
    where supera_guia
),

rachas as (
    select
        id_estacion,
        id_contaminante,
        min(fecha)                         as fecha_inicio,
        max(fecha)                         as fecha_fin,
        count(*)                           as dias,
        datediff('day', min(fecha), max(fecha)) + 1 as dias_calendario
    from sobre_guia
    group by id_estacion, id_contaminante, tramo, id_racha
)

select
    id_estacion,
    id_contaminante,
    fecha_inicio,
    fecha_fin,
    dias,
    dias_calendario,
    dias_calendario - dias                                             as dias_sin_dato,
    dias = max(dias) over (partition by id_estacion, id_contaminante)  as es_racha_maxima
from rachas
