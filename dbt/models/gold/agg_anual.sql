-- =====================================================================================
-- GOLD · INDICADORES ANUALES por estación × contaminante × período.
--
-- Períodos: un año calendario por fila desde `anio_contexto_desde` (2010) hasta el último año
-- del estudio (2026, parcial hasta `fecha_fin`), más los últimos 12 meses ('movil_12m', octubre
-- 2025 a septiembre 2026: un año completo de estaciones, comparable con la guía anual).
--   * es_periodo_estudio = true: 2024, 2025, 2026 y últimos 12 meses (el análisis principal).
--   * Los años 2010-2023 son CONTEXTO: ubican el período de estudio en la serie larga.
-- Se calcula sobre silver.medicion_diaria (toda la serie), con los mismos valores diarios que
-- la fact de gold.
--
-- Regla del 75%: si el período tiene menos de 75% de días con dato (`umbral_completitud`), el
-- indicador no es válido (es_valido = false) y los promedios, el P99 y los % por escalón quedan
-- en NULL. El promedio calculado igual se informa en promedio_referencial, solo por
-- transparencia. Ver docs/calidad_datos.md §3.
--
-- Qué tiene cada fila:
--   1. completitud y validez
--   2. promedio anual contra la guía anual y su escalón (nivel_oms), y cuánto falta para subir
--   3. contra la guía de 24 h: P99 (la definición formal: se toleran 3 o 4 días por año) y
--      % de días sobre la guía (más fácil de comunicar)
--   4. % de días que cumplen cada escalón de 24 h (la "matriz de escalones"); es acumulativo:
--      un día que cumple la guía cumple todos los objetivos intermedios
--   5. racha más larga de días con dato seguidos sobre la guía de 24 h (gaps and islands)
-- =====================================================================================
with

-- Períodos -----------------------------------------------------------------------------------
anios as (
    select anio
    from range({{ var('anio_contexto_desde') }}, year(date '{{ var("fecha_fin") }}') + 1) as t(anio)
),

periodos as (
    select
        cast(anio as varchar)                                           as id_periodo,
        anio,
        make_date(anio, 1, 1)                                           as fecha_desde,
        least(make_date(anio, 12, 31), date '{{ var("fecha_fin") }}')  as fecha_hasta
    from anios
    union all
    select
        'movil_12m',
        null,
        cast(date '{{ var("fecha_fin") }}' - interval 1 year + interval 1 day as date),
        date '{{ var("fecha_fin") }}'
),

periodos_etiquetados as (
    select
        *,
        case
            when id_periodo = 'movil_12m'               then 'movil_12m'
            when fecha_hasta < make_date(anio, 12, 31)  then 'anio_parcial'
            else 'anio_completo'
        end                                                             as tipo_periodo,
        case
            when id_periodo = 'movil_12m'
                then 'Últimos 12 meses (' || strftime(fecha_desde, '%m/%Y') || ' a ' || strftime(fecha_hasta, '%m/%Y') || ')'
            when fecha_hasta < make_date(anio, 12, 31)
                then id_periodo || ' (parcial: ' || strftime(fecha_desde, '%d/%m') || ' a ' || strftime(fecha_hasta, '%d/%m') || ')'
            else id_periodo
        end                                                             as periodo,
        coalesce(anio, 9999)                                            as orden_periodo,
        id_periodo = 'movil_12m' or anio >= year(date '{{ var("fecha_inicio") }}') as es_periodo_estudio,
        datediff('day', fecha_desde, fecha_hasta) + 1                   as n_dias_periodo
    from periodos
),

-- Cada día de cada período × estación × contaminante, con su valor en la unidad de la OMS
-- (nulo si ese día no hay dato). generate_series de DuckDB/PostgreSQL arma la lista de días.
dias as (
    select id_periodo, cast(unnest(generate_series(fecha_desde, fecha_hasta, interval 1 day)) as date) as fecha
    from periodos_etiquetados
),

grilla as (
    select
        d.id_periodo,
        d.fecha,
        e.id_estacion,
        c.id_contaminante,
        m.valor_diario * c.factor_masa as valor
    from dias as d
    cross join {{ ref('dim_estacion') }}     as e
    cross join {{ ref('dim_contaminante') }} as c
    left join {{ ref('medicion_diaria') }}   as m
        on  m.fecha = d.fecha
        and m.id_estacion = e.id_estacion
        and m.id_contaminante = c.id_contaminante
        and m.tiene_dato
),

-- Guías de 24 h y anual en columnas (una fila por contaminante)
guias as (
    select
        id_contaminante,
        max(guia_oms) filter (where promedio = '24h')   as guia_24h,
        max(it4)      filter (where promedio = '24h')   as it4_24h,
        max(it3)      filter (where promedio = '24h')   as it3_24h,
        max(it2)      filter (where promedio = '24h')   as it2_24h,
        max(it1)      filter (where promedio = '24h')   as it1_24h,
        max(guia_oms) filter (where promedio = 'anual') as guia_anual,
        max(it4)      filter (where promedio = 'anual') as it4_anual,
        max(it3)      filter (where promedio = 'anual') as it3_anual,
        max(it2)      filter (where promedio = 'anual') as it2_anual,
        max(it1)      filter (where promedio = 'anual') as it1_anual
    from {{ ref('oms_2021') }}
    group by id_contaminante
),

-- 1 a 4. Días con dato, promedio, P99 y conteos contra cada umbral de 24 h
resumen as (
    select
        g.id_periodo, g.id_estacion, g.id_contaminante,
        count(g.valor)                                      as n_dias_con_dato,
        avg(g.valor)                                        as promedio,
        quantile_cont(g.valor, 0.99)                        as p99,
        count(*) filter (where g.valor >  o.guia_24h)       as n_dias_supera_24h,
        count(*) filter (where g.valor <= o.guia_24h)       as n_cumple_guia,
        count(*) filter (where g.valor <= o.it4_24h)        as n_cumple_it4,
        count(*) filter (where g.valor <= o.it3_24h)        as n_cumple_it3,
        count(*) filter (where g.valor <= o.it2_24h)        as n_cumple_it2,
        count(*) filter (where g.valor <= o.it1_24h)        as n_cumple_it1
    from grilla as g
    join guias as o using (id_contaminante)
    group by g.id_periodo, g.id_estacion, g.id_contaminante
),

-- 5. Rachas: sucesiones de días CON DATO sobre la guía de 24 h, sin ningún día con dato que la
-- cumpla en el medio. Un hueco corto sin dato (hasta `dias_hueco_maximo_racha` = 7 días) no
-- corta la racha ni la alarga; uno más largo sí la corta. Motivo: la fuente tiene huecos de
-- exportación cortos (días cortados al mediodía) que sí tienen dato en los informes en PDF.
-- Técnica gaps and islands: se numeran todos los días con dato (n_dia) y, aparte, los que
-- superan la guía; mientras vienen seguidos, la diferencia es constante e identifica la racha.
dias_con_dato as (
    select
        g.id_periodo, g.id_estacion, g.id_contaminante, g.fecha,
        g.valor > o.guia_24h                                                    as supera,
        row_number() over (partition by g.id_periodo, g.id_estacion, g.id_contaminante order by g.fecha) as n_dia,
        datediff('day', lag(g.fecha) over (partition by g.id_periodo, g.id_estacion, g.id_contaminante
                                           order by g.fecha), g.fecha) - 1      as dias_sin_dato_antes
    from grilla as g
    join guias as o using (id_contaminante)
    where g.valor is not null
),

-- Tramo: sube cada vez que hay un hueco largo; una racha no puede cruzar de tramo
tramos as (
    select
        *,
        sum(case when dias_sin_dato_antes > {{ var('dias_hueco_maximo_racha') }} then 1 else 0 end)
            over (partition by id_periodo, id_estacion, id_contaminante order by fecha) as tramo
    from dias_con_dato
),

islas as (
    select
        id_periodo, id_estacion, id_contaminante, fecha, tramo,
        n_dia - row_number() over (partition by id_periodo, id_estacion, id_contaminante order by fecha) as id_racha
    from tramos
    where supera
),

rachas as (
    select
        id_periodo, id_estacion, id_contaminante,
        count(*)   as dias,
        min(fecha) as desde,
        max(fecha) as hasta,
        row_number() over (partition by id_periodo, id_estacion, id_contaminante
                           order by count(*) desc, min(fecha)) as orden
    from islas
    group by id_periodo, id_estacion, id_contaminante, tramo, id_racha
),

-- Todo junto, con la regla del 75%
base as (
    select
        r.id_estacion,
        r.id_contaminante,
        p.id_periodo,
        p.periodo,
        p.tipo_periodo,
        p.anio,
        p.orden_periodo,
        p.es_periodo_estudio,
        p.n_dias_periodo,
        r.n_dias_con_dato,
        round(r.n_dias_con_dato * 1.0 / p.n_dias_periodo, 4)                    as completitud,
        r.n_dias_con_dato * 1.0 / p.n_dias_periodo >= {{ var('umbral_completitud') }} as es_valido,
        o.guia_24h, o.it4_24h, o.it3_24h, o.it2_24h, o.it1_24h,
        o.guia_anual, o.it4_anual, o.it3_anual, o.it2_anual, o.it1_anual,
        r.promedio, r.p99,
        r.n_dias_supera_24h, r.n_cumple_guia, r.n_cumple_it4, r.n_cumple_it3, r.n_cumple_it2, r.n_cumple_it1,
        k.dias  as racha_maxima_dias,
        k.desde as racha_desde,
        k.hasta as racha_hasta
    from resumen as r
    join periodos_etiquetados as p using (id_periodo)
    join guias as o using (id_contaminante)
    left join rachas as k
        on  k.id_periodo = r.id_periodo and k.id_estacion = r.id_estacion
        and k.id_contaminante = r.id_contaminante and k.orden = 1
),

validado as (
    select
        *,
        case when es_valido then round(promedio, 2) end as promedio_anual,
        case when es_valido then round(p99, 2) end      as p99_24h
    from base
)

select
    id_estacion,
    id_contaminante,
    id_periodo,
    periodo,
    tipo_periodo,
    anio,
    orden_periodo,
    es_periodo_estudio,
    n_dias_periodo,
    n_dias_con_dato,
    completitud,
    es_valido,
    -- 2. Promedio contra la guía anual (el CO no tiene guía anual: queda vacío)
    promedio_anual,
    round(promedio, 2)                                          as promedio_referencial,
    guia_anual,
    round(promedio_anual / guia_anual, 2)                       as veces_guia_anual,
    case
        when promedio_anual is null or guia_anual is null then null
        when promedio_anual <= guia_anual then 'AQG'
        when promedio_anual <= it4_anual  then 'IT4'
        when promedio_anual <= it3_anual  then 'IT3'
        when promedio_anual <= it2_anual  then 'IT2'
        when promedio_anual <= it1_anual  then 'IT1'
        else '> IT1'
    end                                                         as nivel_oms,
    case
        when promedio_anual is null or guia_anual is null then null
        when promedio_anual <= guia_anual then 1
        when promedio_anual <= it4_anual  then 2
        when promedio_anual <= it3_anual  then 3
        when promedio_anual <= it2_anual  then 4
        when promedio_anual <= it1_anual  then 5
        else 6
    end                                                         as orden_nivel_oms,
    -- Próximo escalón: el umbral más alto que el promedio todavía supera
    case
        when promedio_anual > it1_anual  then 'IT1'
        when promedio_anual > it2_anual  then 'IT2'
        when promedio_anual > it3_anual  then 'IT3'
        when promedio_anual > it4_anual  then 'IT4'
        when promedio_anual > guia_anual then 'AQG'
    end                                                         as proximo_nivel,
    round(promedio_anual - case
        when promedio_anual > it1_anual  then it1_anual
        when promedio_anual > it2_anual  then it2_anual
        when promedio_anual > it3_anual  then it3_anual
        when promedio_anual > it4_anual  then it4_anual
        when promedio_anual > guia_anual then guia_anual
    end, 2)                                                     as ug_para_proximo_nivel,
    -- 3. Contra la guía de 24 h
    p99_24h,
    round(p99_24h / guia_24h, 2)                                as p99_veces_guia_24h,
    round(n_dias_supera_24h * 1.0 / nullif(n_dias_con_dato, 0), 4) as pct_dias_supera_24h,
    -- 4. % de días que cumplen cada escalón de 24 h (vacío si el nivel no existe o el período no es válido)
    case when es_valido then round(n_cumple_guia * 1.0 / n_dias_con_dato, 4) end                    as pct_cumple_guia_24h,
    case when es_valido and it4_24h is not null then round(n_cumple_it4 * 1.0 / n_dias_con_dato, 4) end as pct_cumple_it4_24h,
    case when es_valido and it3_24h is not null then round(n_cumple_it3 * 1.0 / n_dias_con_dato, 4) end as pct_cumple_it3_24h,
    case when es_valido and it2_24h is not null then round(n_cumple_it2 * 1.0 / n_dias_con_dato, 4) end as pct_cumple_it2_24h,
    case when es_valido and it1_24h is not null then round(n_cumple_it1 * 1.0 / n_dias_con_dato, 4) end as pct_cumple_it1_24h,
    -- 5. Racha más larga del período
    coalesce(racha_maxima_dias, 0)                              as racha_maxima_dias,
    racha_desde,
    racha_hasta
from validado
