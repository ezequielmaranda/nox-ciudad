-- =====================================================================================
-- 01 · STAGING: el CSV horario de BA Data, tipado y pasado a formato largo.
--
-- Entrada: data/raw/calidad-aire.csv (lo baja src/extract.py del portal BA Data). Viene en
--          formato ANCHO: una fila por fecha y hora, una columna por estación × contaminante
--          (CO_CENTENARIO, NO2_CENTENARIO, ...). Todo se lee como texto.
-- Grano:   fecha × hora × estación × contaminante (una fila por celda del CSV).
-- Regla:   NO se borra ninguna fila. Lo que no es un número queda clasificado en `estado_valor`
--          y las reglas de calidad se aplican en stg_aire_horario_validado.
--
-- Decisiones:
--   * UNPIVOT (SQL estándar): de ancho a largo, una columna `valor_crudo` y el nombre de la
--     columna de origen, de donde salen estación y contaminante. INCLUDE NULLS conserva las
--     celdas vacías (si no, UNPIVOT las descarta y se perderían filas).
--   * Se dejan afuera las columnas de Palermo: la estación está desactivada desde el
--     30/06/2010 y sus columnas vienen vacías (ver docs/calidad_datos.md).
--   * Fecha: viene como '12FEB2011:00:00:00' (formato SAS): strptime con %d%b%Y.
--   * Hora: 1 a 24 = hora que TERMINA (la 1 es de 00:00 a 01:00 y la 24, de 23:00 a 24:00).
--     Horas fuera de 1-24 se conservan y se marcan en el paso siguiente.
--   * 's/d', 'S/d' o celda vacía -> estado 'sin_dato', valor nulo.
--   * '<0.05', '< 0.05' (bajo el límite de detección) -> estado 'bajo_limite_deteccion' y valor
--     imputado = límite / 2 (criterio habitual: el valor real está entre 0 y el límite).
--   * Cualquier otro texto ('#REF!', 'x/d') -> estado 'invalido', valor nulo.
-- =====================================================================================
with crudo as (
    -- all_varchar: se lee todo como texto para que la conversión quede a la vista acá abajo
    select *
    from read_csv('{{ ruta("data/raw/calidad-aire.csv") }}', header = true, all_varchar = true)
),

ancho as (
    select
        cast(strptime(trim(fecha), '%d%b%Y:%H:%M:%S') as date) as fecha,
        try_cast(trim(hora) as integer)                         as hora,
        co_centenario, no2_centenario, pm10_centenario,
        co_cordoba,    no2_cordoba,    pm10_cordoba,
        co_la_boca,    no2_la_boca,    pm10_la_boca
    from crudo
),

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

clasificado as (
    select
        fecha,
        hora,
        -- 'no2_la_boca' -> contaminante 'no2', estación 'la_boca'
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
)

select
    fecha,
    hora,
    id_estacion,
    id_contaminante,
    valor_crudo,
    estado_valor,
    -- Límite de detección informado por la fuente (solo para '<x')
    case when estado_valor = 'bajo_limite_deteccion'
        then cast(trim(substr(valor_crudo, 2)) as double) end      as limite_deteccion,
    -- Valor numérico en la unidad original (ppb, ppm o µg/m³)
    case
        when estado_valor = 'valido'                then cast(valor_crudo as double)
        when estado_valor = 'bajo_limite_deteccion' then cast(trim(substr(valor_crudo, 2)) as double) / 2
    end                                                           as valor,
    estado_valor = 'bajo_limite_deteccion'                        as es_imputado
from clasificado
