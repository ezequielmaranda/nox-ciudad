-- =====================================================================================
-- 01 · STAGING: el CSV crudo de la extracción, tipado y normalizado.
--
-- Entrada: data/raw/aire_publico.csv (lo genera src/extract.py a partir de los PDF de la APrA).
--          Viene todo como texto: valores con coma decimal y códigos especiales.
-- Grano:   estación × fecha × contaminante × estadístico (una fila por celda de los PDF).
-- Regla:   NO se borra ninguna fila. Lo que no es un número queda clasificado en `estado_valor`.
--
-- Decisiones:
--   * Identificadores en snake_case y sin tildes ('LA BOCA' -> 'la_boca', 'NOx' -> 'nox').
--   * Coma decimal -> punto ('0,2' -> 0.2).
--   * 's/d' y 'DND' (sin dato / dato no disponible)  -> estado 'sin_dato', valor nulo.
--   * '<4', '<0,5' (bajo el límite de detección)     -> estado 'bajo_limite_deteccion' y valor
--     imputado = límite / 2 (criterio habitual en calidad del aire: el valor real está entre 0 y
--     el límite; descartarlo sesgaría los promedios hacia arriba).
--   * Cualquier otro texto (p. ej. 'Lunes')          -> estado 'invalido', valor nulo.
-- =====================================================================================
with crudo as (
    -- all_varchar: se lee todo como texto para que la conversión quede a la vista acá abajo
    select *
    from read_csv('../data/raw/aire_publico.csv', header = true, all_varchar = true)
),

normalizado as (
    select
        lower(replace(trim(estacion), ' ', '_'))  as id_estacion,
        try_cast(fecha as date)                  as fecha,          -- nulo si la fecha viniera mal
        lower(trim(contaminante))                as id_contaminante,
        trim(estadistico)                        as estadistico,
        trim(valor_crudo)                        as valor_crudo,
        trim(unidad)                             as unidad,
        trim(archivo)                            as archivo_pdf
    from crudo
),

clasificado as (
    select
        *,
        case
            when lower(valor_crudo) in ('s/d', 'dnd')                     then 'sin_dato'
            when valor_crudo like '<%'                                    then 'bajo_limite_deteccion'
            when regexp_matches(valor_crudo, '^-?[0-9]+(,[0-9]+)?$')      then 'valido'
            else 'invalido'
        end as estado_valor
    from normalizado
)

select
    id_estacion,
    fecha,
    id_contaminante,
    estadistico,
    valor_crudo,
    estado_valor,
    -- Límite de detección informado por la fuente (solo para '<x')
    case when estado_valor = 'bajo_limite_deteccion'
        then cast(replace(substr(valor_crudo, 2), ',', '.') as double) end as limite_deteccion,
    -- Valor numérico en la unidad original (ppb, ppm o µg/m³)
    case
        when estado_valor = 'valido'
            then cast(replace(valor_crudo, ',', '.') as double)
        when estado_valor = 'bajo_limite_deteccion'
            then cast(replace(substr(valor_crudo, 2), ',', '.') as double) / 2
    end as valor,
    estado_valor = 'bajo_limite_deteccion' as es_imputado,
    unidad,
    archivo_pdf
from clasificado
