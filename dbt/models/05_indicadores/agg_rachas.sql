-- =====================================================================================
-- 05 · INDICADORES: rachas de días consecutivos por encima de la guía de 24 h.
--
-- Técnica "gaps and islands": dentro de cada estación × contaminante se numeran los días que
-- superan la guía en orden de fecha (ROW_NUMBER). Si los días son consecutivos, fecha menos
-- ese número da siempre la misma fecha: ese valor identifica la racha (la "isla").
--   fecha       2024-06-01  2024-06-02  2024-06-03  2024-06-07
--   nro             1           2           3           4
--   fecha - nro 2024-05-31  2024-05-31  2024-05-31  2024-06-03   -> 2 rachas: 3 días y 1 día
-- Un día sin dato corta la racha (criterio conservador).
-- fecha - entero es de DuckDB/PostgreSQL; en otros motores: DATEADD / fecha - INTERVAL.
-- =====================================================================================
with sobre_guia as (
    select
        id_estacion,
        id_contaminante,
        fecha,
        fecha - cast(row_number() over (
            partition by id_estacion, id_contaminante order by fecha
        ) as integer) as id_racha
    from {{ ref('agg_cumplimiento_diario') }}
    where supera_guia
),

rachas as (
    select
        id_estacion,
        id_contaminante,
        min(fecha) as fecha_inicio,
        max(fecha) as fecha_fin,
        count(*)   as dias
    from sobre_guia
    group by id_estacion, id_contaminante, id_racha
)

select
    *,
    dias = max(dias) over (partition by id_estacion, id_contaminante) as es_racha_maxima
from rachas
