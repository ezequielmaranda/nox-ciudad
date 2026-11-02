-- Silver: usos por línea y día del universo "colectivos que circulan por CABA",
-- sumando las distintas etiquetas y operadores de una misma línea.
-- Grano: fecha × número de línea.
select
    fecha,
    linea_num,
    bool_or(es_linea_solo_caba) as es_linea_solo_caba,
    sum(usos) as usos,
    string_agg(distinct linea_original, ' | ') as etiquetas
from {{ ref('silver_sube') }}
where es_colectivo_caba
group by fecha, linea_num
