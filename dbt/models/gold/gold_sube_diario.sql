-- Gold: actividad del transporte público y "dosis" de paro de colectivos, un registro por día.
--
-- Dosis: qué parte de las líneas que circulan por CABA dejó de funcionar.
-- Para cada línea y día, la base es la mediana de usos del mismo día de la semana en las
-- 3 semanas anteriores y posteriores, usando solo días normales. Una línea se considera parada si
-- ese día registró menos del 15% de su base. Solo cuentan líneas con base > 2000 usos.
-- El porcentaje ponderado pesa cada línea por sus usos de base (las líneas grandes pesan más).
with dias as (
    select fecha, es_dia_normal from {{ ref('silver_sube_actividad_diaria') }}
),

lineas as (
    select linea_num, bool_or(es_linea_solo_caba) as es_linea_solo_caba
    from {{ ref('silver_colectivos_caba_linea_dia') }}
    group by linea_num
),

semanas as (select unnest([-3, -2, -1, 1, 2, 3]) as k),

base_linea as (
    select
        d.fecha,
        l.linea_num,
        median(u.usos) as usos_base  -- días sin registro de la línea no cuentan (la línea no existía)
    from dias as d
    cross join semanas
    join dias as r on r.fecha = d.fecha + to_days(7 * semanas.k) and r.es_dia_normal
    cross join lineas as l
    left join {{ ref('silver_colectivos_caba_linea_dia') }} as u
        on u.fecha = r.fecha and u.linea_num = l.linea_num
    group by d.fecha, l.linea_num
),

linea_dia as (
    select
        b.fecha,
        b.linea_num,
        l.es_linea_solo_caba,
        b.usos_base,
        coalesce(u.usos, 0) as usos,
        coalesce(u.usos, 0) < 0.15 * b.usos_base as parada
    from base_linea as b
    join lineas as l using (linea_num)
    left join {{ ref('silver_colectivos_caba_linea_dia') }} as u
        on u.fecha = b.fecha and u.linea_num = b.linea_num
    where b.usos_base > 2000
),

dosis as (
    select
        fecha,
        count(*) as lineas_evaluadas,
        100.0 * avg(parada::int) as pct_lineas_paradas,
        100.0 * sum(usos_base) filter (where parada) / sum(usos_base) as pct_lineas_paradas_ponderado,
        100.0 * sum(usos_base) filter (where parada and es_linea_solo_caba)
            / sum(usos_base) filter (where es_linea_solo_caba) as pct_paradas_solo_caba,
        100.0 * sum(usos_base) filter (where parada and not es_linea_solo_caba)
            / sum(usos_base) filter (where not es_linea_solo_caba) as pct_paradas_interjurisdiccionales,
        sum(usos) / sum(usos_base) as ratio_colectivo_caba
    from linea_dia
    group by fecha
),

-- Actividad comparable entre tipos de día: usos de colectivos de CABA respecto de un día hábil
-- normal típico (mediana de los días normales de las 4 semanas anteriores y posteriores).
-- Un domingo da ~0,4 y un paro ~0,1: es el eje X del gráfico "actividad vs. firma diésel".
vs_habil as (
    select
        d.fecha,
        d.usos_colectivo_caba / median(r.usos_colectivo_caba) as actividad_colectivo_vs_habil
    from {{ ref('silver_sube_actividad_diaria') }} as d
    join {{ ref('silver_sube_actividad_diaria') }} as r
        on r.es_dia_normal and r.fecha between d.fecha - interval 28 day and d.fecha + interval 28 day
        and r.fecha <> d.fecha
    group by d.fecha, d.usos_colectivo_caba
)

select
    a.fecha,
    a.es_dia_normal,
    a.usos_colectivo,
    a.usos_tren,
    a.usos_subte,
    a.usos_colectivo_caba,
    a.ratio_colectivo,
    a.ratio_tren,
    a.ratio_subte,
    d.ratio_colectivo_caba,
    h.actividad_colectivo_vs_habil,
    d.lineas_evaluadas,
    coalesce(d.pct_lineas_paradas, 0) as pct_lineas_paradas,
    coalesce(d.pct_lineas_paradas_ponderado, 0) as pct_lineas_paradas_ponderado,
    coalesce(d.pct_paradas_solo_caba, 0) as pct_paradas_solo_caba,
    coalesce(d.pct_paradas_interjurisdiccionales, 0) as pct_paradas_interjurisdiccionales
from {{ ref('silver_sube_actividad_diaria') }} as a
left join dosis as d using (fecha)
left join vs_habil as h using (fecha)
