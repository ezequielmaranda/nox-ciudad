-- =====================================================================================
-- 02 · DIMENSIÓN CALENDARIO: un registro por día del período de estudio, haya o no datos.
--
-- Es la base para detectar días faltantes: la fact se arma como calendario × estación ×
-- contaminante, así un día sin fila en la fuente aparece explícitamente (sin_fila), en lugar
-- de "desaparecer". El período sale de las variables fecha_inicio y fecha_fin (dbt_project.yml).
--
-- tipo_dia: feriado tiene prioridad (un feriado que cae sábado es 'feriado').
-- estacion_del_anio: estaciones meteorológicas del hemisferio sur (verano = dic, ene, feb).
-- generate_series es de DuckDB/PostgreSQL; en otros motores se usa un CTE recursivo.
-- =====================================================================================
with dias as (
    select cast(d as date) as fecha
    from generate_series(
        date '{{ var("fecha_inicio") }}',
        date '{{ var("fecha_fin") }}',
        interval 1 day
    ) as t(d)
),

base as (
    select
        dias.fecha,
        year(dias.fecha)                     as anio,
        month(dias.fecha)                    as mes,
        isodow(dias.fecha)                   as dia_semana,   -- 1 = lunes … 7 = domingo
        feriados.nombre                      as nombre_feriado,
        feriados.tipo                        as tipo_feriado,
        eventos.evento,
        eventos.grupo_evento
    from dias
    left join {{ ref('feriados') }} as feriados on feriados.fecha = dias.fecha
    left join {{ ref('eventos') }}  as eventos  on eventos.fecha  = dias.fecha
)

select
    fecha,
    anio,
    mes,
    case mes
        when 1 then 'enero' when 2 then 'febrero' when 3 then 'marzo' when 4 then 'abril'
        when 5 then 'mayo' when 6 then 'junio' when 7 then 'julio' when 8 then 'agosto'
        when 9 then 'septiembre' when 10 then 'octubre' when 11 then 'noviembre'
        when 12 then 'diciembre'
    end                                                        as nombre_mes,
    make_date(anio, mes, 1)                                    as anio_mes,
    case
        when mes in (12, 1, 2) then 'verano'
        when mes in (3, 4, 5)  then 'otoño'
        when mes in (6, 7, 8)  then 'invierno'
        else 'primavera'
    end                                                        as estacion_del_anio,
    case
        when mes in (12, 1, 2) then 1
        when mes in (3, 4, 5)  then 2
        when mes in (6, 7, 8)  then 3
        else 4
    end                                                        as orden_estacion_del_anio,
    dia_semana,
    case dia_semana
        when 1 then 'lunes' when 2 then 'martes' when 3 then 'miércoles' when 4 then 'jueves'
        when 5 then 'viernes' when 6 then 'sábado' when 7 then 'domingo'
    end                                                        as nombre_dia,
    -- Código sin tildes (para filtrar) y etiqueta legible (para mostrar)
    case
        when nombre_feriado is not null then 'feriado'
        when dia_semana = 6 then 'sabado'
        when dia_semana = 7 then 'domingo'
        else 'habil'
    end                                                        as tipo_dia,
    case
        when nombre_feriado is not null then 'Feriado'
        when dia_semana = 6 then 'Sábado'
        when dia_semana = 7 then 'Domingo'
        else 'Hábil'
    end                                                        as tipo_dia_etiqueta,
    case
        when nombre_feriado is not null then 4
        when dia_semana = 6 then 2
        when dia_semana = 7 then 3
        else 1
    end                                                        as orden_tipo_dia,
    nombre_feriado is not null                                 as es_feriado,
    nombre_feriado,
    tipo_feriado,
    dia_semana in (6, 7)                                       as es_fin_de_semana,
    -- Año parcial: el último año del período no llega al 31 de diciembre
    anio = year(date '{{ var("fecha_fin") }}')
        and date '{{ var("fecha_fin") }}' < make_date(anio, 12, 31) as es_anio_parcial,
    evento is not null                                         as es_dia_evento,
    evento,
    grupo_evento
from base
