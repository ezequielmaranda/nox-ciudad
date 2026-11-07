-- =====================================================================================
-- 01 · STAGING: reglas de validación sobre cada valor horario de stg_aire_horario.
--
-- Grano: el mismo de stg_aire_horario. Ninguna fila se borra: cada regla es una columna
-- booleana (flag) y `motivo_invalido` dice por qué un valor no se usa (nulo = válido).
--
-- Reglas (en orden de prioridad para `motivo_invalido`):
--   1. hora_invalida   la hora no está entre 1 y 24 (el CSV trae algunas horas 0 y filas con
--                      "horas" 26 a 96, vacías). La hora 0 no coincide ni con la hora 24 del día
--                      anterior ni con la 1 del mismo día: es ambigua y no se usa.
--   2. sin_dato_fuente la fuente dice 's/d' o deja la celda vacía.
--   3. texto_invalido  un texto que no es número ni código conocido ('#REF!', 'x/d').
--   4. fuera_de_rango  valor negativo o mayor al máximo plausible del contaminante
--                      (data/reference/contaminantes.csv). Ej.: NO2 = -2 ppb; CO = 23 ppm en La
--                      Boca con las horas vecinas en 0,8 ppm.
--   5. fila_en_cero    todas las mediciones de esa fecha y hora valen 0: es una planilla vacía
--                      cargada con ceros, no aire limpio (todas las estaciones a la vez).
--   6. valor_trabado   NO2 idéntico durante `horas_valor_trabado` horas seguidas o más: un
--                      analizador que no varía ni 1 ppb en medio día está trabado. Solo para el
--                      NO2: CO y PM10 son promedios móviles y es normal que repitan valores.
-- =====================================================================================
with base as (
    select * from {{ ref('stg_aire_horario') }}
),

contaminantes as (
    select id_contaminante, maximo_plausible
    from {{ ref('contaminantes') }}
),

-- Regla 5: cuántos valores numéricos tiene cada fecha × hora y cuántos son cero
fila as (
    select
        fecha,
        hora,
        count(*) filter (where estado_valor = 'valido')              as n_numericos,
        count(*) filter (where estado_valor = 'valido' and valor = 0) as n_ceros
    from base
    group by fecha, hora
),

-- Regla 6: "islas" de valores iguales consecutivos (técnica gaps-and-islands). La diferencia
-- entre el número de fila general y el número de fila dentro de cada valor es constante
-- mientras el valor se repite seguido: esa diferencia identifica la racha.
no2_ordenado as (
    select
        fecha, hora, id_estacion, id_contaminante, valor,
        row_number() over (partition by id_estacion order by fecha, hora)
      - row_number() over (partition by id_estacion, valor order by fecha, hora) as isla
    from base
    where id_contaminante = 'no2'
      and estado_valor = 'valido'
      and hora between 1 and 24
),

rachas as (
    select
        fecha, hora, id_estacion, id_contaminante,
        count(*) over (partition by id_estacion, valor, isla) as horas_iguales_seguidas
    from no2_ordenado
),

flags as (
    select
        b.*,
        c.maximo_plausible,
        coalesce(b.hora not between 1 and 24, true)                            as hora_invalida,
        coalesce(b.valor < 0 or b.valor > c.maximo_plausible, false)           as fuera_de_rango,
        coalesce(b.estado_valor = 'valido' and f.n_numericos >= 2
                 and f.n_ceros = f.n_numericos, false)                          as fila_en_cero,
        coalesce(r.horas_iguales_seguidas >= {{ var('horas_valor_trabado') }}, false) as valor_trabado,
        r.horas_iguales_seguidas
    from base as b
    left join contaminantes as c using (id_contaminante)
    left join fila as f using (fecha, hora)
    left join rachas as r using (fecha, hora, id_estacion, id_contaminante)
),

motivo as (
    select
        *,
        case
            when hora_invalida             then 'hora_invalida'
            when estado_valor = 'sin_dato' then 'sin_dato_fuente'
            when estado_valor = 'invalido' then 'texto_invalido'
            when fuera_de_rango            then 'fuera_de_rango'
            when fila_en_cero              then 'fila_en_cero'
            when valor_trabado             then 'valor_trabado'
        end as motivo_invalido
    from flags
)

select
    fecha,
    hora,
    id_estacion,
    id_contaminante,
    valor_crudo,
    estado_valor,
    limite_deteccion,
    valor,
    es_imputado,
    hora_invalida,
    fuera_de_rango,
    fila_en_cero,
    valor_trabado,
    horas_iguales_seguidas,
    motivo_invalido,
    motivo_invalido is null as es_valido
from motivo
