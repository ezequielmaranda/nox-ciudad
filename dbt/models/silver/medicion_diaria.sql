-- =====================================================================================
-- SILVER · de valores horarios a un valor diario por estación × contaminante.
--
-- Grano: fecha × estación × contaminante, para TODA la serie y solo los días que aparecen en
-- la fuente. La fact de gold lo recorta al período de estudio y le agrega los días faltantes;
-- los indicadores anuales (gold.agg_anual) usan la serie entera para el contexto 2010-2025.
--
-- El valor diario es el promedio de 24 h (de 00 a 24), el que compara la guía OMS. Como cada
-- contaminante se publica con un promedio distinto, se arma distinto:
--   NO2  (promedio horario)   promedio de las horas válidas del día, solo si hay al menos
--                             `horas_minimas_dia` (18 de 24 = 75%). Es el criterio de la UE
--                             (Directiva 2008/50/CE, Anexo XI) para pasar de horas a día.
--   PM10 (móvil de 24 h)      el valor de la hora 24: el promedio móvil que cierra el día ya
--                             es el promedio de 00 a 24.
--   CO   (móvil de 8 h)       promedio de los valores de las horas 8, 16 y 24: son los tres
--                             bloques de 8 h del día y su promedio es el de 24 h. Hacen falta
--                             los tres.
-- Se verificó contra los informes mensuales en PDF de la APrA: el valor diario así calculado
-- coincide con el publicado en 94% a 98% de los días (docs/calidad_datos.md §2.5).
-- El valor queda en la unidad original (ppb, ppm o µg/m³); la conversión a la unidad de la
-- OMS se hace en gold.
-- =====================================================================================
with horario as (
    select *
    from {{ ref('medicion_horaria') }}
    where hora between 1 and 24
),

dia as (
    select
        fecha,
        id_estacion,
        id_contaminante,
        count(*)                                                   as n_horas_fila,
        count(*) filter (where es_valido)                          as n_horas_validas,
        count(*) filter (where estado_valor = 'sin_dato')          as n_horas_sin_dato,
        avg(valor) filter (where es_valido)                        as promedio_horas_validas,
        max(valor) filter (where es_valido and hora = 8)           as valor_hora_8,
        max(valor) filter (where es_valido and hora = 16)          as valor_hora_16,
        max(valor) filter (where es_valido and hora = 24)          as valor_hora_24,
        coalesce(bool_or(es_valido and es_imputado), false)        as tiene_imputados
    from horario
    group by fecha, id_estacion, id_contaminante
),

calculado as (
    select
        d.*,
        case c.promedio_fuente
            when 'horario'   then case when d.n_horas_validas >= {{ var('horas_minimas_dia') }}
                                       then round(d.promedio_horas_validas, 2) end
            when 'movil_24h' then d.valor_hora_24
            when 'movil_8h'  then round((d.valor_hora_8 + d.valor_hora_16 + d.valor_hora_24) / 3, 3)
        end as valor_diario
    from dia as d
    join {{ ref('contaminantes') }} as c using (id_contaminante)
)

select
    fecha,
    id_estacion,
    id_contaminante,
    n_horas_validas,
    valor_diario,
    valor_diario is not null                                      as tiene_dato,
    case
        when valor_diario is not null                              then null
        when n_horas_validas = 0 and n_horas_sin_dato = n_horas_fila then 'sin_dato_fuente'
        else 'incompleto'
    end                                                           as motivo_sin_dato,
    valor_diario is not null and tiene_imputados                  as es_imputado
from calculado
