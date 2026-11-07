-- =====================================================================================
-- 03 · HECHOS: fact_medicion_diaria, el centro del modelo estrella.
--
-- Grano: fecha × estación × contaminante (formato LARGO). El valor es el promedio de 24 h,
-- que es el que compara la guía OMS; cómo se arma desde los datos horarios está en
-- stg_aire_diario.
--
-- Se arma como GRILLA COMPLETA: calendario × estaciones × contaminantes (1.004 días × 3 × 3 =
-- 9.036 filas) y se le pega lo medido con LEFT JOIN. Así cada combinación existe y se
-- distingue por qué falta un dato (motivo_sin_dato):
--   'sin_fila'        la fuente no tiene ninguna hora de ese día
--   'sin_dato_fuente' la fuente tiene el día, pero todas las horas dicen 's/d'
--   'incompleto'      hay horas válidas pero no alcanzan (NO2 con menos de 18 horas; PM10 sin
--                     la hora 24; CO sin alguna de las horas 8, 16 o 24) o las descartó una
--                     regla de calidad
-- `valor` y `valor_masa` solo se llenan cuando tiene_dato.
--
-- es_outlier: valor > Q3 + 3·IQR de su estación × contaminante. Se MARCA, no se borra: un pico
-- de contaminación real es justamente lo que la guía de 24 h quiere detectar.
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
        con.unidad_medicion,
        con.unidad_masa,
        con.factor_masa
    from {{ ref('dim_calendario') }}         as cal
    cross join {{ ref('dim_estacion') }}     as est
    cross join {{ ref('dim_contaminante') }} as con
),

unido as (
    select
        g.fecha,
        g.id_estacion,
        g.id_contaminante,
        coalesce(d.n_horas_validas, 0)                                as n_horas_validas,
        d.id_estacion is not null                                     as tiene_fila,
        coalesce(d.tiene_dato, false)                                 as tiene_dato,
        case when d.id_estacion is null then 'sin_fila'
             else d.motivo_sin_dato end                               as motivo_sin_dato,
        d.valor_diario                                                as valor,
        g.unidad_medicion                                             as unidad,
        round(d.valor_diario * g.factor_masa, 3)                      as valor_masa,
        g.unidad_masa,
        coalesce(d.es_imputado, false)                                as es_imputado
    from grilla as g
    left join {{ ref('stg_aire_diario') }} as d
        on  d.id_estacion     = g.id_estacion
        and d.fecha           = g.fecha
        and d.id_contaminante = g.id_contaminante
),

-- Cuartiles por estación × contaminante, solo con valores válidos.
-- quantile_cont = percentile_cont(...) WITHIN GROUP (ORDER BY ...) del estándar SQL.
cuartiles as (
    select
        id_estacion,
        id_contaminante,
        quantile_cont(valor, 0.25) as q1,
        quantile_cont(valor, 0.75) as q3
    from unido
    where tiene_dato
    group by id_estacion, id_contaminante
)

select
    u.fecha,
    u.id_estacion,
    u.id_contaminante,
    u.n_horas_validas,
    u.tiene_fila,
    u.tiene_dato,
    u.motivo_sin_dato,
    u.valor,
    u.unidad,
    u.valor_masa,
    u.unidad_masa,
    u.es_imputado,
    coalesce(u.tiene_dato and u.valor > c.q3 + {{ var('factor_iqr') }} * (c.q3 - c.q1), false) as es_outlier,
    round(c.q3 + {{ var('factor_iqr') }} * (c.q3 - c.q1), 3)                                   as umbral_outlier
from unido as u
left join cuartiles as c using (id_estacion, id_contaminante)
