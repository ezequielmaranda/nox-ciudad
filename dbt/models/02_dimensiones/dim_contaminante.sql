-- =====================================================================================
-- 02 · DIMENSIÓN CONTAMINANTE: una fila por contaminante medido.
--
-- factor_masa: para comparar con la OMS hay que pasar de concentración en volumen (ppb, ppm)
-- a concentración en masa (µg/m³, mg/m³). A 25 °C y 1 atm un mol de gas ocupa 24,45 litros:
--     µg/m³ = ppb × peso_molecular / 24,45      (y mg/m³ = ppm × peso_molecular / 24,45)
--   NO2: 46,01 / 24,45 = 1,88    CO: 28,01 / 24,45 = 1,146    NO: 30,01 / 24,45 = 1,23
-- El NOx se expresa "como NO2" (convención). El PM10 ya viene en µg/m³ (factor 1).
-- =====================================================================================
with guias as (
    select
        id_contaminante,
        bool_or(promedio = '24h')   as tiene_guia_24h,
        bool_or(promedio = 'anual') as tiene_guia_anual
    from {{ ref('oms_2021') }}
    group by id_contaminante
)

select
    c.id_contaminante,
    c.codigo_fuente,
    c.nombre,
    c.unidad_medicion,
    c.unidad_masa,
    c.peso_molecular,
    case
        when c.peso_molecular is null then 1.0
        else round(c.peso_molecular / {{ var('volumen_molar') }}, 4)
    end                                        as factor_masa,
    c.tolerancia_coherencia,
    c.maximo_fisico,
    coalesce(g.tiene_guia_24h, false)          as tiene_guia_24h,
    coalesce(g.tiene_guia_anual, false)        as tiene_guia_anual,
    c.orden,
    c.descripcion
from {{ ref('contaminantes') }} as c
left join guias as g using (id_contaminante)
