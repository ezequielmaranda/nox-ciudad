-- =====================================================================================
-- SILVER · valores horarios limpios: tipados, en formato largo y con las reglas de calidad.
--
-- Grano: fecha × hora × estación × contaminante (una fila por celda del CSV). Toda la serie
-- (2009 en adelante). NO se borra ninguna fila: lo que no se usa queda con es_valido = false
-- y el motivo en `motivo_invalido`.
--
-- Pasos:
--   1. De ancho a largo con UNPIVOT (SQL estándar). INCLUDE NULLS conserva las celdas vacías
--      (si no, se perderían filas). Se dejan afuera las columnas de Palermo: la estación está
--      desactivada desde el 30/06/2010 y sus columnas vienen vacías.
--   2. Tipos: la fecha viene como '12FEB2011:00:00:00' (formato SAS) -> strptime con %d%b%Y.
--      Hora 1 a 24 = hora que TERMINA (la 1 es de 00:00 a 01:00 y la 24, de 23:00 a 24:00).
--   3. Clasificación del texto:
--        's/d', 'S/d' o vacío       -> sin_dato, valor nulo
--        '<0.05', '< 0.05'           -> bajo el límite de detección: valor = límite / 2
--                                       (el valor real está entre 0 y el límite)
--        otro texto ('#REF!', 'x/d') -> invalido, valor nulo
--   4. Reglas (en orden de prioridad para `motivo_invalido`):
--        hora_invalida   hora fuera de 1-24 (el CSV trae algunas horas 0, que no coinciden ni
--                        con la 24 del día anterior ni con la 1, y filas vacías con "horas" >24)
--        sin_dato_fuente la fuente dice 's/d' o deja la celda vacía
--        texto_invalido  un texto que no es número ni código conocido
--        fuera_de_rango  negativo o mayor al máximo plausible (data/reference/contaminantes.csv)
--        fila_en_cero    todas las mediciones de esa fecha y hora valen 0: es una planilla
--                        vacía cargada con ceros, no aire limpio
--        valor_trabado   NO2 idéntico `horas_valor_trabado` horas seguidas o más (analizador
--                        trabado). Solo NO2: CO y PM10 son promedios móviles y repiten valores.
-- =====================================================================================
with ancho as (
    select
        cast(strptime(trim(fecha), '%d%b%Y:%H:%M:%S') as date) as fecha,
        try_cast(trim(hora) as integer)                         as hora,
        co_centenario, no2_centenario, pm10_centenario,
        co_cordoba,    no2_cordoba,    pm10_cordoba,
        co_la_boca,    no2_la_boca,    pm10_la_boca
    from {{ ref('calidad_aire') }}
),

-- 1. De ancho a largo
largo as (
    select *
    from ancho
    unpivot include nulls (
        valor_crudo for columna in (
            co_centenario, no2_centenario, pm10_centenario,
            co_cordoba,    no2_cordoba,    pm10_cordoba,
            co_la_boca,    no2_la_boca,    pm10_la_boca
        )
    )
),

-- 3. Clasificación del texto ('no2_la_boca' -> contaminante 'no2', estación 'la_boca')
clasificado as (
    select
        fecha,
        hora,
        substr(lower(columna), strpos(lower(columna), '_') + 1)   as id_estacion,
        split_part(lower(columna), '_', 1)                        as id_contaminante,
        trim(valor_crudo)                                         as valor_crudo,
        case
            when valor_crudo is null or trim(valor_crudo) = ''
              or lower(trim(valor_crudo)) = 's/d'                 then 'sin_dato'
            when trim(valor_crudo) like '<%'                      then 'bajo_limite_deteccion'
            when regexp_matches(trim(valor_crudo), '^-?[0-9]+(\.[0-9]+)?$') then 'valido'
            else 'invalido'
        end                                                       as estado_valor
    from largo
),

tipado as (
    select
        *,
        case
            when estado_valor = 'valido'                then cast(valor_crudo as double)
            when estado_valor = 'bajo_limite_deteccion' then cast(trim(substr(valor_crudo, 2)) as double) / 2
        end                                                       as valor
    from clasificado
),

-- 4. Regla fila_en_cero: cuántos valores numéricos tiene cada fecha × hora y cuántos son cero
fila as (
    select
        fecha,
        hora,
        count(*) filter (where estado_valor = 'valido')               as n_numericos,
        count(*) filter (where estado_valor = 'valido' and valor = 0) as n_ceros
    from tipado
    group by fecha, hora
),

-- 4. Regla valor_trabado: "islas" de valores iguales consecutivos (técnica gaps-and-islands).
-- La diferencia entre el número de fila general y el número de fila dentro de cada valor es
-- constante mientras el valor se repite seguido: esa diferencia identifica la racha.
no2_ordenado as (
    select
        fecha, hora, id_estacion, valor,
        row_number() over (partition by id_estacion order by fecha, hora)
      - row_number() over (partition by id_estacion, valor order by fecha, hora) as isla
    from tipado
    where id_contaminante = 'no2'
      and estado_valor = 'valido'
      and hora between 1 and 24
),

rachas_no2 as (
    select
        fecha, hora, id_estacion,
        'no2' as id_contaminante,
        count(*) over (partition by id_estacion, valor, isla) as horas_iguales_seguidas
    from no2_ordenado
),

reglas as (
    select
        t.*,
        coalesce(t.hora not between 1 and 24, true)                           as hora_invalida,
        coalesce(t.valor < 0 or t.valor > c.maximo_plausible, false)          as fuera_de_rango,
        coalesce(t.estado_valor = 'valido' and f.n_numericos >= 2
                 and f.n_ceros = f.n_numericos, false)                         as fila_en_cero,
        coalesce(r.horas_iguales_seguidas >= {{ var('horas_valor_trabado') }}, false) as valor_trabado
    from tipado as t
    left join {{ ref('contaminantes') }} as c using (id_contaminante)
    left join fila as f using (fecha, hora)
    left join rachas_no2 as r using (fecha, hora, id_estacion, id_contaminante)
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
    from reglas
)

select
    fecha,
    hora,
    id_estacion,
    id_contaminante,
    valor_crudo,
    estado_valor,
    valor,
    motivo_invalido,
    motivo_invalido is null as es_valido
from motivo
