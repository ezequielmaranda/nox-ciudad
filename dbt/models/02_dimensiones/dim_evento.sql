-- =====================================================================================
-- 02 · DIMENSIÓN EVENTO: días de paro de transporte del período (contexto para leer la serie).
-- No es parte de la pregunta: sirve para explicar días atípicos (p. ej. un paro de colectivos
-- baja el NO2 de las avenidas). Fuente: notas de prensa (columna fuente_prensa).
-- =====================================================================================
select
    fecha,
    evento,
    grupo_evento,
    case grupo_evento
        when 'sin_colectivos' then 'Paro de colectivos'
        when 'trenes_subte'   then 'Paro de trenes o subte (colectivos funcionando)'
    end as grupo_evento_etiqueta,
    fuente_prensa
from {{ ref('eventos') }}
