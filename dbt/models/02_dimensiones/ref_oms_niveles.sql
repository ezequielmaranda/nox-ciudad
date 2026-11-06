-- =====================================================================================
-- 02 · REFERENCIA OMS (formato largo): una fila por contaminante × promedio × nivel.
--
-- Es la misma tabla ref_oms "despivotada" (UNPIVOT: columnas -> filas). En formato largo es
-- fácil dibujar las líneas de referencia en los gráficos (una por nivel) y filtrarlas en
-- Power BI. UNPIVOT es de DuckDB (también SQL Server/Oracle); en otros motores se escribe
-- como cinco SELECT unidos con UNION ALL. Los niveles vacíos (NULL) no generan fila.
-- =====================================================================================
with largo as (
    unpivot {{ ref('ref_oms') }}
    on guia_oms, it4, it3, it2, it1
    into name nivel_columna value umbral
)

select
    id_contaminante,
    contaminante,
    promedio,
    case nivel_columna when 'guia_oms' then 'AQG' else upper(nivel_columna) end as nivel,
    case nivel_columna
        when 'guia_oms' then 'Guía OMS'
        else 'Objetivo intermedio ' || upper(nivel_columna)
    end                                                                       as nivel_etiqueta,
    -- 1 = más exigente (guía) … 5 = menos exigente (IT1)
    case nivel_columna
        when 'guia_oms' then 1 when 'it4' then 2 when 'it3' then 3
        when 'it2' then 4 when 'it1' then 5
    end                                                                       as orden_exigencia,
    umbral,
    unidad
from largo
