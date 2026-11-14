-- =====================================================================================
-- GOLD · HECHOS: fact_medicion_diaria, el centro del modelo estrella.
--
-- Grano: fecha × estación × contaminante (formato LARGO), con el promedio de 24 h de
-- silver.medicion_diaria comparado con la guía OMS de 24 h.
--
-- Se arma como GRILLA COMPLETA: calendario × estaciones × contaminantes (1.004 días × 3 × 3 =
-- 9.036 filas) y se le pega lo medido con LEFT JOIN. Así cada combinación existe y se
-- distingue por qué falta un dato (motivo_sin_dato):
--   'sin_fila'        la fuente no tiene ninguna hora de ese día
--   'sin_dato_fuente' la fuente tiene el día, pero todas las horas dicen 's/d'
--   'incompleto'      hay horas válidas pero no alcanzan (NO2 con menos de 18 horas; PM10 sin
--                     la hora 24; CO sin alguna de las horas 8, 16 o 24) o las descartó una
--                     regla de calidad
-- Las columnas de valor y de comparación con la guía solo se llenan cuando tiene_dato.
--
-- nivel_oms: el escalón más exigente cuyo umbral de 24 h el valor NO supera.
--   AQG = cumple la guía · IT4 … IT1 = cumple solo un objetivo intermedio · '> IT1' = no cumple
--   ni el menos exigente. Un umbral vacío (NULL) hace falsa la comparación y se saltea.
--
-- es_outlier: valor > Q3 + 3·IQR de su estación × contaminante. Se MARCA, no se borra: un pico
-- de contaminación real es justamente lo que la guía de 24 h quiere detectar.
--
-- Las unidades no se repiten acá: `valor` está en dim_contaminante.unidad_medicion y `valor_masa`
-- en dim_contaminante.unidad_masa. La guía de 24 h, en gold.guia_oms.
--
-- Por qué formato largo y no ancho (una columna por contaminante): el JOIN con la OMS es por
-- contaminante, en Power BI un solo segmentador elige el contaminante y agregar uno nuevo no
-- cambia la estructura. Ver docs/modelo_datos.md.
-- =====================================================================================
with grilla as (
    select
        cal.fecha,
        est.id_estacion,
        con.id_contaminante,
        con.factor_masa
    from {{ ref('dim_calendario') }}         as cal
    cross join {{ ref('dim_estacion') }}     as est
    cross join {{ ref('dim_contaminante') }} as con
),

guia as (
    select id_contaminante, guia_oms, it1, it2, it3, it4
    from {{ ref('oms_2021') }}
    where promedio = '24h'
),

unido as (
    select
        g.fecha,
        g.id_estacion,
        g.id_contaminante,
        coalesce(d.n_horas_validas, 0)                                as n_horas_validas,
        coalesce(d.tiene_dato, false)                                 as tiene_dato,
        case when d.id_estacion is null then 'sin_fila'
             else d.motivo_sin_dato end                               as motivo_sin_dato,
        d.valor_diario                                                as valor,
        round(d.valor_diario * g.factor_masa, 3)                      as valor_masa
    from grilla as g
    left join {{ ref('medicion_diaria') }} as d
        on  d.id_estacion     = g.id_estacion
        and d.fecha           = g.fecha
        and d.id_contaminante = g.id_contaminante
),

comparado as (
    select
        u.*,
        u.valor_masa > o.guia_oms                      as supera_guia,
        case
            when u.valor_masa is null       then null
            when u.valor_masa <= o.guia_oms then 'AQG'
            when u.valor_masa <= o.it4      then 'IT4'
            when u.valor_masa <= o.it3      then 'IT3'
            when u.valor_masa <= o.it2      then 'IT2'
            when u.valor_masa <= o.it1      then 'IT1'
            else '> IT1'
        end                                            as nivel_oms,
        -- Mismo escalón en número, para ordenar: 1 = cumple la guía … 6 = no cumple ni el IT1
        case
            when u.valor_masa is null       then null
            when u.valor_masa <= o.guia_oms then 1
            when u.valor_masa <= o.it4      then 2
            when u.valor_masa <= o.it3      then 3
            when u.valor_masa <= o.it2      then 4
            when u.valor_masa <= o.it1      then 5
            else 6
        end                                            as orden_nivel_oms
    from unido as u
    left join guia as o using (id_contaminante)
),

-- Cuartiles por estación × contaminante, solo con valores válidos.
-- quantile_cont = percentile_cont(...) WITHIN GROUP (ORDER BY ...) del estándar SQL.
cuartiles as (
    select
        id_estacion,
        id_contaminante,
        quantile_cont(valor, 0.25) as q1,
        quantile_cont(valor, 0.75) as q3
    from comparado
    where tiene_dato
    group by id_estacion, id_contaminante
)

select
    c.fecha,
    c.id_estacion,
    c.id_contaminante,
    c.n_horas_validas,
    c.tiene_dato,
    c.motivo_sin_dato,
    c.valor,
    c.valor_masa,
    c.supera_guia,
    c.nivel_oms,
    c.orden_nivel_oms,
    coalesce(c.tiene_dato and c.valor > q.q3 + {{ var('factor_iqr') }} * (q.q3 - q.q1), false) as es_outlier
from comparado as c
left join cuartiles as q using (id_estacion, id_contaminante)
