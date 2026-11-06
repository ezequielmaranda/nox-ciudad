-- =====================================================================================
-- 02 · REFERENCIA OMS (formato ancho): guías de calidad del aire de la OMS 2021 y objetivos
-- intermedios (IT1 = el menos exigente … IT4 = el más exigente antes de la guía).
-- Fuente: WHO global air quality guidelines (2021), resumen ejecutivo, Tabla 0.1.
-- Los umbrales viven en data/reference/oms_2021.csv: el SQL nunca los escribe a mano,
-- siempre los trae con un JOIN.
-- =====================================================================================
select
    id_contaminante,
    contaminante,
    promedio,           -- '24h' o 'anual'
    guia_oms,
    it1,
    it2,
    it3,
    it4,
    unidad
from {{ ref('oms_2021') }}
