-- =====================================================================================
-- 01 · STAGING: reglas de validación física sobre cada valor de stg_aire.
--
-- Grano: el mismo de stg_aire (una fila por celda de los PDF). Ninguna fila se borra: cada
-- regla es una columna booleana (flag) y `motivo_invalido` dice por qué un valor no se usa.
--
-- Reglas (las tolerancias y máximos físicos salen de data/reference/contaminantes.csv):
--   1. fuera_de_rango       valor negativo o por encima de un máximo físicamente posible.
--   2. valor_trabado        los 6 estadísticos del día son idénticos (máximo horario = mínimo
--                           horario = promedios): el analizador no varió en 24 h, imposible en
--                           una ciudad. Aparece en el NO del día 8 de varios meses.
--   3. cero_sin_respaldo    un promedio en 0 con máximo horario 0 o faltante (planilla vacía).
--   4. fuera_de_max_min     un promedio (24 h o bloque) fuera del rango [mínimo, máximo] horario.
--   5. promedio_incoherente el promedio de 24 h no coincide con el promedio de los 3 bloques de 8 h.
--   6. no/no2_mayor_que_nox NO > NOx o NO2 > NOx: imposible, porque NOx = NO + NO2.
--   7. nox_incoherente      |NOx − (NO + NO2)| > tolerancia de redondeo.
--
-- Qué se descarta: las reglas 1 a 5 invalidan el valor del contaminante; la 6 invalida al
-- contaminante que supera al NOx; la 7 invalida NO y NOx pero NO al NO2. Motivo: en esos días
-- el NO2 pasa sus propios controles (reglas 4 y 5) y la evidencia apunta a la columna de NO
-- (reglas 2 y 6). Así no se pierden días de NO2, que es el contaminante principal del análisis.
-- =====================================================================================
with base as (
    select * from {{ ref('stg_aire') }}
),

contaminantes as (
    select id_contaminante, tolerancia_coherencia, maximo_fisico
    from {{ ref('contaminantes') }}
),

-- Los 6 estadísticos de cada estación × día × contaminante en una sola fila, para poder
-- compararlos entre sí. FILTER es SQL estándar (en motores sin FILTER: MAX(CASE WHEN ...)).
dia as (
    select
        id_estacion,
        fecha,
        id_contaminante,
        max(valor) filter (where estadistico = '24h')    as v_24h,
        max(valor) filter (where estadistico = '0-8')    as v_0_8,
        max(valor) filter (where estadistico = '8-16')   as v_8_16,
        max(valor) filter (where estadistico = '16-24')  as v_16_24,
        max(valor) filter (where estadistico = 'max_1h') as v_max_1h,
        max(valor) filter (where estadistico = 'min_1h') as v_min_1h,
        count(*) filter (where estado_valor = 'valido')  as n_valores_validos,
        count(distinct valor) filter (where estado_valor = 'valido') as n_valores_distintos
    from base
    group by id_estacion, fecha, id_contaminante
),

-- NO, NO2 y NOx del mismo día y estadístico en una fila, para chequear NOx = NO + NO2.
nox as (
    select
        id_estacion,
        fecha,
        estadistico,
        max(valor) filter (where id_contaminante = 'no')  as v_no,
        max(valor) filter (where id_contaminante = 'no2') as v_no2,
        max(valor) filter (where id_contaminante = 'nox') as v_nox
    from base
    where id_contaminante in ('no', 'no2', 'nox')
      and estadistico in ('24h', '0-8', '8-16', '16-24')
    group by id_estacion, fecha, estadistico
),

flags as (
    select
        b.*,
        b.estadistico in ('24h', '0-8', '8-16', '16-24') as es_promedio,

        coalesce(b.valor < 0 or b.valor > c.maximo_fisico, false)            as fuera_de_rango,

        coalesce(d.n_valores_validos = 6 and d.n_valores_distintos = 1, false) as valor_trabado,

        coalesce(b.estadistico in ('24h', '0-8', '8-16', '16-24')
                 and b.valor = 0 and coalesce(d.v_max_1h, 0) = 0, false)     as cero_sin_respaldo,

        coalesce(b.estadistico in ('24h', '0-8', '8-16', '16-24')
                 and (b.valor > d.v_max_1h + c.tolerancia_coherencia
                      or b.valor < d.v_min_1h - c.tolerancia_coherencia), false) as fuera_de_max_min,

        coalesce(b.estadistico in ('24h', '0-8', '8-16', '16-24')
                 and abs(d.v_24h - (d.v_0_8 + d.v_8_16 + d.v_16_24) / 3)
                     > c.tolerancia_coherencia, false)                       as promedio_incoherente,

        coalesce(n.v_no > n.v_nox, false)                                    as no_mayor_que_nox,
        coalesce(n.v_no2 > n.v_nox, false)                                   as no2_mayor_que_nox,
        coalesce(abs(n.v_nox - (n.v_no + n.v_no2)) > 2, false)               as nox_incoherente
    from base as b
    left join contaminantes as c using (id_contaminante)
    left join dia as d using (id_estacion, fecha, id_contaminante)
    -- el chequeo de NOx solo aplica a las filas de NO, NO2 y NOx
    left join nox as n
        on  b.id_contaminante in ('no', 'no2', 'nox')
        and n.id_estacion = b.id_estacion
        and n.fecha = b.fecha
        and n.estadistico = b.estadistico
),

motivo as (
    select
        *,
        -- Primer motivo que aplica, en orden de gravedad. Nulo = valor válido.
        case
            when estado_valor = 'sin_dato'                    then 'sin_dato_fuente'
            when estado_valor = 'invalido'                    then 'texto_invalido'
            when fuera_de_rango                               then 'fuera_de_rango'
            when valor_trabado                                then 'valor_trabado'
            when cero_sin_respaldo                            then 'cero_sin_respaldo'
            when fuera_de_max_min                             then 'fuera_de_max_min'
            when promedio_incoherente                         then 'promedio_incoherente'
            when (id_contaminante = 'no'  and no_mayor_que_nox)
              or (id_contaminante = 'no2' and no2_mayor_que_nox) then 'mayor_que_nox'
            when id_contaminante in ('no', 'nox') and nox_incoherente then 'nox_incoherente'
        end as motivo_invalido
    from flags
)

select
    *,
    motivo_invalido is null as es_valido
from motivo
