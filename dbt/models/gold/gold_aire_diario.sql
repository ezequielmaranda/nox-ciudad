-- Gold: una fila por estación y día, con los valores que usa el análisis.
-- Ventana diurna = bloque de 8 a 16 h (la que publica la APrA); también el promedio de 24 h.
-- Solo entran valores válidos, dentro de rango y físicamente coherentes
-- (NOx = NO + NO2 y promedios entre el mínimo y el máximo horario).
with v as (
    select estacion, fecha, contaminante, estadistico, valor
    from {{ ref('silver_aire') }}
    where estado_valor = 'valido'
      and not fuera_de_rango
      and not nox_incoherente
      and not fuera_de_max_min
),

ancho as (
    select
        estacion,
        fecha,
        max(valor) filter (where contaminante = 'NO'   and estadistico = '8-16') as no_816_ppb,
        max(valor) filter (where contaminante = 'NO2'  and estadistico = '8-16') as no2_816_ppb,
        max(valor) filter (where contaminante = 'NOx'  and estadistico = '8-16') as nox_816_ppb,
        max(valor) filter (where contaminante = 'CO'   and estadistico = '8-16') as co_816_ppm,
        max(valor) filter (where contaminante = 'PM10' and estadistico = '8-16') as pm10_816_ugm3,
        max(valor) filter (where contaminante = 'NO2'  and estadistico = '24h')  as no2_24h_ppb,
        max(valor) filter (where contaminante = 'NOx'  and estadistico = '24h')  as nox_24h_ppb,
        max(valor) filter (where contaminante = 'CO'   and estadistico = '24h')  as co_24h_ppm,
        max(valor) filter (where contaminante = 'PM10' and estadistico = '24h')  as pm10_24h_ugm3
    from v
    group by estacion, fecha
)

select
    ancho.estacion,
    ancho.fecha,
    cal.tipo_dia,
    cal.nombre_dia,
    cal.feriado,
    cal.evento,
    cal.grupo_evento,
    ancho.no_816_ppb,
    ancho.no2_816_ppb,
    ancho.nox_816_ppb,
    ancho.co_816_ppm,
    ancho.pm10_816_ugm3,
    -- Firma diésel: NOx/CO. Con CO publicado a 0,1 ppm, valores de CO bajos lo vuelven ruidoso.
    ancho.nox_816_ppb / nullif(ancho.co_816_ppm, 0) as nox_co_816,
    ancho.no2_24h_ppb,
    ancho.no2_24h_ppb * 1.88 as no2_24h_ugm3,  -- para comparar con la guía OMS de 24 h (25 µg/m³)
    ancho.nox_24h_ppb,
    ancho.co_24h_ppm,
    ancho.pm10_24h_ugm3                         -- guía OMS de 24 h: 45 µg/m³
from ancho
left join {{ ref('dim_calendario') }} as cal on cal.fecha = ancho.fecha
