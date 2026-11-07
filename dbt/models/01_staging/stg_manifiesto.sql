-- =====================================================================================
-- 01 · STAGING: manifiesto de la extracción (un registro por PDF enlazado en la web).
-- Sirve para documentar qué archivos se procesaron, cuáles se descartaron y por qué.
-- =====================================================================================
select
    lower(replace(trim(estacion_pagina), ' ', '_'))  as id_estacion,
    lower(trim(tipo))                                as tipo_informe,      -- co, nox o pm10
    archivo,
    estacion_pdf                                     as estacion_en_encabezado,
    try_cast(anio as integer)                        as anio,
    try_cast(mes as integer)                         as mes,
    estado                                           as estado_detalle,
    -- Estado resumido: ok, ok_con_aviso, descartado o error
    case
        when estado like 'ok%' and estado like '%aviso%' then 'ok_con_aviso'
        when estado like 'ok%'                           then 'ok'
        when estado like 'descartado%'                   then 'descartado'
        when estado like 'error%'                        then 'error'
        else 'fuera_del_periodo'
    end                                              as estado,
    url_descarga
from read_csv('../data/raw/aire_publico_manifiesto.csv', header = true, all_varchar = true)
