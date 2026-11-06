-- =====================================================================================
-- 04 · CALIDAD: estado de cada PDF de la extracción (procesado, con aviso o descartado).
-- =====================================================================================
select
    id_estacion,
    tipo_informe,
    anio,
    mes,
    archivo,
    estado,
    estado_detalle,
    estacion_en_encabezado
from {{ ref('stg_manifiesto') }}
