-- =====================================================================================================
-- Consultas de exploración: preguntas del TP respondidas con SQL sobre la base del pipeline.
--
-- Cómo correrlas (después de `uv run python run.py`):
--     duckdb data/nox.duckdb          (CLI de DuckDB 1.x)
--     .read analysis/consultas.sql
-- o pegarlas de a una en DBeaver / DataGrip conectado a data/nox.duckdb.
--
-- Todas leen las capas silver y gold. Los resultados que se citan en los comentarios son los del
-- período 01/2024 a 09/2026 y pueden cambiar si se vuelve a correr la extracción con datos nuevos.
-- =====================================================================================================


-- -----------------------------------------------------------------------------------------------------
-- 1. ¿Cuántos datos válidos tiene cada estación? (cobertura del bloque 8-16 h)
--    Un día cuenta si el promedio de 8 a 16 h pasó todos los controles de calidad y llegó a gold.
-- -----------------------------------------------------------------------------------------------------
with periodo as (
    select count(distinct fecha) as dias from gold.gold_analitico
)
select
    estacion,
    count(nox_816_ppb)                                        as dias_nox,
    count(co_816_ppm)                                         as dias_co,
    count(pm10_816_ugm3)                                      as dias_pm10,
    round(100.0 * count(nox_816_ppb) / any_value(periodo.dias), 0) as pct_cobertura_nox,
    round(100.0 * count(co_816_ppm) / any_value(periodo.dias), 0)  as pct_cobertura_co
from gold.gold_analitico, periodo
group by estacion
order by estacion;
-- Resultado: La Boca tiene la mejor cobertura (≈93%), a Centenario le falta el NOx de buena parte de 2024.


-- -----------------------------------------------------------------------------------------------------
-- 2. ¿Qué tan seguido el NO2 supera la guía de la OMS de 24 h (25 µg/m³)? Por estación y año.
-- -----------------------------------------------------------------------------------------------------
select
    estacion,
    anio,
    count(no2_24h_ugm3)                                                   as dias_con_dato,
    round(avg(no2_24h_ugm3), 1)                                           as media_ugm3,
    round(100.0 * count(*) filter (where no2_24h_ugm3 > 25) / count(no2_24h_ugm3), 0)
                                                                          as pct_dias_sobre_guia,
    round(quantile_cont(no2_24h_ugm3, 0.99), 0)                           as percentil_99_ugm3
from gold.gold_analitico
where no2_24h_ugm3 is not null
group by estacion, anio
order by estacion, anio;
-- Resultado: La Boca supera la guía más del 90% de los días con dato, Córdoba, entre 78% y 88%.
-- La OMS mide su guía de 24 h con el percentil 99 (admite 3-4 días por año sobre el valor).


-- -----------------------------------------------------------------------------------------------------
-- 3. ¿Cómo cambia el NOx según cuántos colectivos circulan? (gradiente por grupo de día)
--    Mediana de NOx y CO en el bloque 8-16 h y actividad de colectivos (1 = día hábil normal).
-- -----------------------------------------------------------------------------------------------------
select
    grupo_dia,
    count(distinct fecha)                                   as dias,
    round(median(actividad_colectivo_vs_habil), 2)          as actividad_colectivos,
    round(median(nox_816_ppb), 0)                           as nox_mediana_ppb,
    round(median(co_816_ppm), 2)                            as co_mediana_ppm,
    round(median(viento_kmh), 1)                            as viento_mediana_kmh
from gold.gold_analitico
group by grupo_dia
order by actividad_colectivos desc;
-- Resultado: el NOx baja con la actividad (hábil 51 > sábado 36 > feriado 26 > domingo 24 ppb). Los paros de
-- colectivos son el grupo con menos colectivos (≈0,2 de un día hábil), pero su mediana cruda (47 ppb) mezcla
-- estaciones con niveles distintos y no descuenta el clima: la comparación justa está en el notebook 05.


-- -----------------------------------------------------------------------------------------------------
-- 4. ¿Qué días pararon más líneas de colectivo? ¿Está completo el catálogo de paros?
--    Días de lunes a viernes con más del 5% de las líneas paradas (ponderado por viajes).
-- -----------------------------------------------------------------------------------------------------
select
    s.fecha,
    c.nombre_dia,
    c.tipo_dia,
    coalesce(c.evento, c.feriado, '(sin evento cargado)')   as que_paso,
    round(s.pct_lineas_paradas_ponderado, 1)                as pct_lineas_paradas,
    round(s.actividad_colectivo_vs_habil, 2)                as actividad_colectivos,
    round(s.ratio_tren, 2)                                  as tren_vs_habitual,
    round(s.ratio_subte, 2)                                 as subte_vs_habitual
from gold.gold_sube_diario as s
join silver.dim_calendario as c using (fecha)
where s.pct_lineas_paradas_ponderado > 5
order by s.pct_lineas_paradas_ponderado desc;
-- Resultado: arriba aparecen los 4 paros de colectivos (63-68%). Después solo Navidad, Año Nuevo y el
-- 07/03/2024 (7%). No hay paros grandes de colectivos fuera del estudio.


-- -----------------------------------------------------------------------------------------------------
-- 5. ¿Cómo estuvo el tiempo en cada paro, comparado con los días hábiles normales del mismo mes?
--    Usa una función de ventana para ubicar el viento del paro dentro de su mes (percentil).
-- -----------------------------------------------------------------------------------------------------
with dias as (
    select
        m.fecha,
        c.mes,
        c.evento,
        c.grupo_dia,
        c.es_dia_normal,
        m.viento_kmh,
        m.temp_c,
        m.precipitacion_mm
    from gold.gold_meteo_diario as m
    join silver.dim_calendario as c using (fecha)
    where c.es_dia_normal or c.evento is not null
),
ubicados as (
    select
        *,
        -- percentil del viento del día entre todos los días (normales y eventos) del mismo mes
        round(100 * percent_rank() over (partition by mes order by viento_kmh), 0) as percentil_viento_mes,
        median(viento_kmh) filter (where es_dia_normal) over (partition by mes)  as viento_tipico_mes
    from dias
)
select fecha, evento, grupo_dia, viento_kmh, round(viento_tipico_mes, 1) as viento_tipico_mes,
       percentil_viento_mes, temp_c, precipitacion_mm
from ubicados
where evento is not null
order by grupo_dia, fecha;
-- Resultado: varios paros cayeron en días ventosos para su mes (el viento baja la contaminación), el
-- 06/05/2025 tuvo 11 mm de lluvia. Por eso el análisis de eventos ajusta por meteorología (notebook 05).


-- -----------------------------------------------------------------------------------------------------
-- 6. Comparación cruda de cada paro: NOx, NO2 y CO contra la mediana de los días hábiles normales
--    del mismo mes y la misma estación. (Sin ajustar por clima: el ajuste está en el notebook 05.)
-- -----------------------------------------------------------------------------------------------------
with referencia as (
    select
        estacion,
        date_trunc('month', fecha)  as mes,
        median(nox_816_ppb)         as nox_ref,
        median(no2_816_ppb)         as no2_ref,
        median(co_816_ppm)          as co_ref
    from gold.gold_analitico
    where es_dia_normal
    group by all
)
select
    a.fecha,
    a.grupo_dia,
    a.estacion,
    a.nox_816_ppb,
    round(100 * (a.nox_816_ppb / r.nox_ref - 1), 0)   as nox_vs_tipico_pct,
    round(100 * (a.no2_816_ppb / r.no2_ref - 1), 0)   as no2_vs_tipico_pct,
    round(100 * (a.co_816_ppm / r.co_ref - 1), 0)     as co_vs_tipico_pct,
    a.viento_kmh
from gold.gold_analitico as a
join referencia as r
    on r.estacion = a.estacion and r.mes = date_trunc('month', a.fecha)
where a.evento is not null
order by a.grupo_dia, a.fecha, a.estacion;
-- Resultado: en general, en los paros de colectivos el NOx baja y el CO queda igual o sube, en los paros de
-- trenes o subte bajan los dos (hay excepciones, como Córdoba el 19/02/2026).


-- -----------------------------------------------------------------------------------------------------
-- 7. ¿Qué problemas de calidad encontró el pipeline en los datos de aire? (marcas de silver)
--    Ninguna fila se borra: se marca y gold solo toma las válidas.
-- -----------------------------------------------------------------------------------------------------
select
    contaminante,
    count(*)                                                        as valores,
    count(*) filter (where estado_valor = 'sin_dato')               as sin_dato,
    count(*) filter (where estado_valor = 'bajo_limite_deteccion')  as bajo_limite_deteccion,
    count(*) filter (where estado_valor = 'invalido')               as invalido,
    count(*) filter (where fuera_de_rango)                          as fuera_de_rango,
    count(*) filter (where nox_incoherente)                         as nox_distinto_de_no_mas_no2,
    count(*) filter (where fuera_de_max_min)                        as promedio_fuera_de_min_max,
    count(*) filter (where cero_sin_respaldo)                       as cero_sin_respaldo,
    round(100.0 * count(*) filter (where estado_valor = 'valido' and not fuera_de_rango
                                   and not nox_incoherente and not fuera_de_max_min
                                   and not cero_sin_respaldo) / count(*), 1)
                                                                    as pct_utilizable
from silver.silver_aire
group by contaminante
order by contaminante;
-- Resultado: la mayor parte de lo que se pierde son días sin dato en la fuente ("s/d"), las marcas de
-- coherencia física afectan a pocos valores, pero sin ellas entraban ceros falsos al análisis.
