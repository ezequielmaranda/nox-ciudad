-- =====================================================================================
-- 03 · HECHOS: fact_medicion_diaria, el centro del modelo estrella.
--
-- Grano: fecha × estación × contaminante × ventana   (formato LARGO)
--   ventana '24h'  = promedio diario (es el que compara la OMS)
--   ventana '8-16' = promedio de 8 a 16 h (horario de actividad; contexto para tipo de día)
--
-- Se arma como GRILLA COMPLETA: calendario × estaciones × contaminantes × ventanas
-- (1.004 días × 3 × 5 × 2 = 30.120 filas) y se le pega lo medido con LEFT JOIN. Así cada
-- combinación existe y se distingue:
--   tiene_fila = false  -> la fuente no publicó ese día (mes sin PDF, tabla incompleta)
--   tiene_fila = true y tiene_dato = false -> hubo fila pero el valor no sirve
--                                            (s/d, texto, o lo descartó una regla de calidad)
--   tiene_dato = true   -> valor válido; `valor` y `valor_masa` solo se llenan en este caso
--
-- es_outlier: valor > Q3 + 3·IQR de su estación × contaminante × ventana. Se MARCA, no se
-- borra: un pico de contaminación real es justamente lo que la guía de 24 h quiere detectar.
--
-- Por qué formato largo y no ancho (una columna por contaminante): el JOIN con la tabla de la
-- OMS es por contaminante, en Power BI un solo segmentador elige el contaminante y agregar
-- uno nuevo no cambia la estructura. Ver docs/modelo_datos.md.
-- =====================================================================================
with grilla as (
    select
        cal.fecha,
        est.id_estacion,
        con.id_contaminante,
        ven.ventana,
        con.unidad_medicion,
        con.unidad_masa,
        con.factor_masa
    from {{ ref('dim_calendario') }}        as cal
    cross join {{ ref('dim_estacion') }}    as est
    cross join {{ ref('dim_contaminante') }} as con
    cross join (values ('24h'), ('8-16')) as ven(ventana)
),

medido as (
    select
        id_estacion,
        fecha,
        id_contaminante,
        estadistico as ventana,
        valor_crudo,
        estado_valor,
        valor,
        es_imputado,
        es_valido,
        motivo_invalido,
        archivo_pdf
    from {{ ref('stg_aire_validado') }}
    where estadistico in ('24h', '8-16')
),

unido as (
    select
        g.fecha,
        g.id_estacion,
        g.id_contaminante,
        g.ventana,
        m.valor_crudo,
        coalesce(m.estado_valor, 'sin_fila')                         as estado_valor,
        m.id_estacion is not null                                    as tiene_fila,
        coalesce(m.es_valido, false)                                 as tiene_dato,
        case when m.id_estacion is null then 'sin_fila'
             else m.motivo_invalido end                              as motivo_sin_dato,
        case when m.es_valido then m.valor end                       as valor,
        g.unidad_medicion                                            as unidad,
        case when m.es_valido then round(m.valor * g.factor_masa, 3) end as valor_masa,
        g.unidad_masa,
        coalesce(m.es_valido and m.es_imputado, false)               as es_imputado,
        m.archivo_pdf
    from grilla as g
    left join medido as m
        on  m.id_estacion     = g.id_estacion
        and m.fecha           = g.fecha
        and m.id_contaminante = g.id_contaminante
        and m.ventana         = g.ventana
),

-- Cuartiles por estación × contaminante × ventana, solo con valores válidos.
-- quantile_cont = percentile_cont(...) WITHIN GROUP (ORDER BY ...) del estándar SQL.
cuartiles as (
    select
        id_estacion,
        id_contaminante,
        ventana,
        quantile_cont(valor, 0.25) as q1,
        quantile_cont(valor, 0.75) as q3
    from unido
    where tiene_dato
    group by id_estacion, id_contaminante, ventana
)

select
    u.fecha,
    u.id_estacion,
    u.id_contaminante,
    u.ventana,
    u.valor_crudo,
    u.estado_valor,
    u.tiene_fila,
    u.tiene_dato,
    u.motivo_sin_dato,
    u.valor,
    u.unidad,
    u.valor_masa,
    u.unidad_masa,
    u.es_imputado,
    coalesce(u.tiene_dato and u.valor > c.q3 + {{ var('factor_iqr') }} * (c.q3 - c.q1), false) as es_outlier,
    round(c.q3 + {{ var('factor_iqr') }} * (c.q3 - c.q1), 3)                                   as umbral_outlier,
    u.archivo_pdf
from unido as u
left join cuartiles as c using (id_estacion, id_contaminante, ventana)
