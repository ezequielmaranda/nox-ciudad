-- Gold: LA tabla del análisis. Una fila por estación de monitoreo y día, con:
--   calidad del aire (bloque 8-16 h y 24 h)  <- gold_aire_diario
--   actividad del transporte y dosis de paro <- gold_sube_diario
--   meteorología del día                     <- gold_meteo_diario
--   tipo de día, día normal y evento         <- dim_calendario
-- Todo lo demás (EDA, regresión, prueba placebo, dashboard) lee de acá.
select
    a.estacion,
    a.fecha,
    cal.anio,
    cal.mes,
    cal.dia_semana,
    cal.nombre_dia,
    cal.tipo_dia,
    cal.feriado,
    cal.es_dia_normal,
    cal.evento,
    cal.grupo_evento,

    -- Calidad del aire
    a.no_816_ppb,
    a.no2_816_ppb,
    a.nox_816_ppb,
    a.co_816_ppm,
    a.pm10_816_ugm3,
    a.nox_co_816,
    a.no2_24h_ppb,
    a.no2_24h_ugm3,
    a.nox_24h_ppb,
    a.co_24h_ppm,
    a.pm10_24h_ugm3,

    -- Transporte (SUBE)
    s.actividad_colectivo_vs_habil,
    s.ratio_colectivo_caba,
    s.ratio_colectivo,
    s.ratio_tren,
    s.ratio_subte,
    s.pct_lineas_paradas_ponderado,

    -- Meteorología
    m.viento_kmh,
    m.viento_max_kmh,
    m.temp_c,
    m.humedad_pct,
    m.precipitacion_mm,
    m.hubo_lluvia
from {{ ref('gold_aire_diario') }} as a
join {{ ref('dim_calendario') }} as cal using (fecha)
left join {{ ref('gold_sube_diario') }} as s using (fecha)
left join {{ ref('gold_meteo_diario') }} as m using (fecha)
