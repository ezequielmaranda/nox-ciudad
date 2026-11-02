-- Silver: calidad del aire tipada y con estado de cada valor. No se borra ninguna fila:
-- lo que no sirve queda marcado para que el análisis decida qué usar.
-- Grano: estación × fecha × contaminante × estadístico.
with base as (
    select
        estacion,
        cast(fecha as date) as fecha,
        contaminante,
        estadistico,
        trim(valor_crudo) as valor_crudo,
        unidad as unidad_original,
        archivo as archivo_pdf
    from {{ ref('bronze_aire') }}
),

clasificado as (
    select
        *,
        case
            when lower(valor_crudo) in ('s/d', 'dnd') then 'sin_dato'
            when valor_crudo like '<%' then 'bajo_limite_deteccion'
            when regexp_matches(valor_crudo, '^-?[0-9]+(,[0-9]+)?$') then 'valido'
            else 'invalido'  -- p. ej. "Lunes" en el PM10 de Córdoba de julio 2025
        end as estado_valor
    from base
),

numerico as (
    select
        *,
        case when estado_valor = 'valido'
            then cast(replace(valor_crudo, ',', '.') as double) end as valor,
        case when estado_valor = 'bajo_limite_deteccion'
            then cast(replace(substr(valor_crudo, 2), ',', '.') as double) end as limite_deteccion
    from clasificado
),

-- Coherencia física 1: NOx = NO + NO2 (tolerancia de 2 ppb por el redondeo de publicación).
-- Si no se cumple, no se sabe cuál de los tres está mal: se marcan los tres.
coherencia_nox as (
    select
        estacion, fecha, estadistico,
        abs(max(valor) filter (where contaminante = 'NOx')
            - (max(valor) filter (where contaminante = 'NO')
               + max(valor) filter (where contaminante = 'NO2'))) > 2 as nox_incoherente
    from numerico
    where estadistico in ('24h', '0-8', '8-16', '16-24')
    group by all
),

-- Coherencia física 2: un promedio tiene que estar entre el mínimo y el máximo horario del día.
rango_diario as (
    select
        estacion, fecha, contaminante,
        max(valor) filter (where estadistico = 'max_1h') as maximo_1h,
        max(valor) filter (where estadistico = 'min_1h') as minimo_1h
    from numerico
    group by all
)

select
    estacion,
    fecha,
    contaminante,
    estadistico,
    valor_crudo,
    estado_valor,
    valor,
    unidad_original,
    limite_deteccion,
    -- Rangos físicamente posibles para un promedio urbano (en la unidad original).
    coalesce(valor < 0 or valor > case contaminante
        when 'NO' then 2000 when 'NO2' then 500 when 'NOx' then 2500
        when 'CO' then 50 when 'PM10' then 1000 end, false) as fuera_de_rango,
    coalesce(contaminante in ('NO', 'NO2', 'NOx') and c.nox_incoherente, false) as nox_incoherente,
    coalesce(estadistico in ('24h', '0-8', '8-16', '16-24')
        and (valor > r.maximo_1h + 1 or valor < r.minimo_1h - 1), false) as fuera_de_max_min,
    -- Concentración en masa para comparar con las guías OMS (25 °C, 1 atm).
    -- NO2 y NOx (expresado como NO2): 1,88 µg/m³ por ppb; NO: 1,23 µg/m³ por ppb;
    -- CO: 1,145 mg/m³ por ppm; PM10 ya está en µg/m³.
    valor * case contaminante
        when 'NO2' then 1.88 when 'NOx' then 1.88 when 'NO' then 1.23
        when 'CO' then 1.145 when 'PM10' then 1.0 end as valor_masa,
    case when contaminante = 'CO' then 'mg/m3' else 'ug/m3' end as unidad_masa,
    archivo_pdf
from numerico as n
left join coherencia_nox as c using (estacion, fecha, estadistico)
left join rango_diario as r using (estacion, fecha, contaminante)
