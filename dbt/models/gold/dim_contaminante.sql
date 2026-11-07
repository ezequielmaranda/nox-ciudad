-- =====================================================================================
-- GOLD · DIMENSIÓN CONTAMINANTE: una fila por contaminante medido.
--
-- factor_masa: para comparar con la OMS hay que pasar de concentración en volumen (ppb, ppm)
-- a concentración en masa (µg/m³, mg/m³). A 25 °C y 1 atm un mol de gas ocupa 24,45 litros:
--     µg/m³ = ppb × peso_molecular / 24,45      (y mg/m³ = ppm × peso_molecular / 24,45)
--   NO2: 46,01 / 24,45 = 1,88    CO: 28,01 / 24,45 = 1,146
-- El PM10 ya viene en µg/m³ (factor 1).
--
-- Las unidades viven acá y no en las tablas de hechos: cada fila de la fact tiene el valor y la
-- unidad sale de esta dimensión. Las columnas técnicas del seed (promedio_fuente,
-- maximo_plausible) las usa silver y no se repiten acá.
-- =====================================================================================
select
    id_contaminante,
    codigo_fuente,
    nombre,
    unidad_medicion,
    unidad_masa,
    case
        when peso_molecular is null then 1.0
        else round(peso_molecular / {{ var('volumen_molar') }}, 4)
    end            as factor_masa,
    orden,
    descripcion
from {{ ref('contaminantes') }}
