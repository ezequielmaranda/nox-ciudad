-- =====================================================================================
-- 02 · DIMENSIÓN PERÍODO: los períodos sobre los que se calculan los indicadores anuales.
--
--   * Un período por año calendario. El último (2026) es PARCIAL (enero a septiembre):
--     le faltan la primavera y el verano, así que su promedio no se compara con un año completo.
--   * 'movil_12m': los últimos 12 meses con datos (octubre 2025 a septiembre 2026). Es un año
--     completo de estaciones y SÍ es comparable con la guía anual de la OMS.
-- =====================================================================================
with anios as (
    select
        anio,
        min(fecha) as fecha_desde,
        max(fecha) as fecha_hasta,
        count(*)   as n_dias
    from {{ ref('dim_calendario') }}
    group by anio
),

fin as (
    select date '{{ var("fecha_fin") }}' as fecha_fin
)

select
    cast(anio as varchar)                                       as id_periodo,
    case
        when fecha_desde = make_date(anio, 1, 1) and fecha_hasta = make_date(anio, 12, 31)
            then cast(anio as varchar)
        else cast(anio as varchar) || ' (parcial: ' || strftime(fecha_desde, '%d/%m')
             || ' a ' || strftime(fecha_hasta, '%d/%m') || ')'
    end                                                         as etiqueta,
    case
        when fecha_desde = make_date(anio, 1, 1) and fecha_hasta = make_date(anio, 12, 31)
            then 'anio_completo'
        else 'anio_parcial'
    end                                                         as tipo_periodo,
    anio,
    fecha_desde,
    fecha_hasta,
    n_dias,
    anio - min(anio) over () + 1                                as orden
from anios

union all

select
    'movil_12m'                                                 as id_periodo,
    'Últimos 12 meses (' || strftime(cast(fecha_fin - interval 1 year + interval 1 day as date), '%m/%Y')
        || ' a ' || strftime(fecha_fin, '%m/%Y') || ')'         as etiqueta,
    'movil_12m'                                                 as tipo_periodo,
    null                                                        as anio,
    cast(fecha_fin - interval 1 year + interval 1 day as date)  as fecha_desde,
    fecha_fin                                                   as fecha_hasta,
    datediff('day', cast(fecha_fin - interval 1 year as date), fecha_fin) as n_dias,
    99                                                          as orden
from fin
