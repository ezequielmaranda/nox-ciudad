-- Silver: actividad diaria del transporte público del AMBA por modo, comparada con un día típico.
-- Base de comparación: mediana del mismo día de la semana en las 4 semanas anteriores y posteriores.
-- De acá sale la marca de "día normal" que usa todo el análisis.
with diario as (
    select
        fecha,
        sum(usos) filter (where tipo_transporte = 'COLECTIVO') as usos_colectivo,
        sum(usos) filter (where tipo_transporte = 'TREN') as usos_tren,
        sum(usos) filter (where tipo_transporte = 'SUBTE') as usos_subte,
        sum(usos) filter (where es_colectivo_caba) as usos_colectivo_caba
    from {{ ref('silver_sube') }}
    where es_amba
    group by fecha
),

semanas as (select unnest([-4, -3, -2, -1, 1, 2, 3, 4]) as k),

base as (
    select
        d.fecha,
        median(r.usos_colectivo) as base_colectivo,
        median(r.usos_tren) as base_tren,
        median(r.usos_subte) as base_subte
    from diario as d
    cross join semanas
    join diario as r on r.fecha = d.fecha + to_days(7 * semanas.k)
    group by d.fecha
)

select
    diario.fecha,
    diario.usos_colectivo,
    diario.usos_tren,
    diario.usos_subte,
    diario.usos_colectivo_caba,
    diario.usos_colectivo / base.base_colectivo as ratio_colectivo,
    diario.usos_tren / base.base_tren as ratio_tren,
    diario.usos_subte / base.base_subte as ratio_subte,
    -- Día normal: hábil, no feriado y con colectivo, tren y subte por encima del 90% de un día típico.
    -- Deja afuera feriados, puentes, vacaciones de invierno, paros y días de actividad atípica.
    coalesce(
        isodow(diario.fecha) <= 5
        and diario.fecha not in (select fecha from {{ ref('feriados') }})
        and diario.usos_colectivo / base.base_colectivo > 0.9
        and diario.usos_tren / base.base_tren > 0.9
        and diario.usos_subte / base.base_subte > 0.9,
        false
    ) as es_dia_normal
from diario
join base using (fecha)
