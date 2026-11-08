-- =====================================================================================
-- GOLD · GUÍAS OMS 2021: una fila por contaminante × período de promedio × nivel.
--
-- La guía (AQG) es el nivel sin riesgo apreciable; los objetivos intermedios (IT4 el más
-- exigente … IT1 el menos exigente) miden el avance hacia la guía. Fuente: WHO global air
-- quality guidelines (2021), resumen ejecutivo, Tabla 0.1 (data/reference/oms_2021.csv).
-- Los umbrales nunca se escriben a mano en el SQL: siempre salen de esta tabla o de la seed.
--
-- La seed viene en formato ancho (una columna por nivel); acá se pasa a formato largo con
-- UNPIVOT (SQL estándar), que es cómo se usa en el notebook y en Looker Studio (una línea de
-- referencia por nivel). Los niveles vacíos (NULL) no generan fila.
-- =====================================================================================
with largo as (
    select *
    from {{ ref('oms_2021') }}
    unpivot (umbral for nivel_columna in (guia_oms, it4, it3, it2, it1))
)

select
    id_contaminante,
    promedio,                                                                 -- '24h' o 'anual'
    case nivel_columna when 'guia_oms' then 'AQG' else upper(nivel_columna) end as nivel,
    -- 1 = más exigente (guía) … 5 = menos exigente (IT1)
    case nivel_columna
        when 'guia_oms' then 1 when 'it4' then 2 when 'it3' then 3
        when 'it2' then 4 when 'it1' then 5
    end                                                                       as orden_exigencia,
    umbral,
    unidad
from largo
