-- =====================================================================================
-- 04 · CALIDAD: valores diarios atípicos marcados en la fact (Q3 + 3·IQR), con contexto para
-- revisarlos a mano: tipo de día, evento, cuántas veces el umbral y la mediana de la serie.
-- Ninguno se borra; la revisión manual está en docs/calidad_datos.md.
-- =====================================================================================
with medianas as (
    select id_estacion, id_contaminante, median(valor) as mediana
    from {{ ref('fact_medicion_diaria') }}
    where tiene_dato
    group by id_estacion, id_contaminante
)

select
    f.fecha,
    f.id_estacion,
    f.id_contaminante,
    f.valor,
    f.unidad,
    f.umbral_outlier,
    m.mediana,
    round(f.valor / nullif(m.mediana, 0), 1) as veces_mediana,
    c.nombre_dia,
    c.tipo_dia,
    c.evento
from {{ ref('fact_medicion_diaria') }} as f
join medianas as m using (id_estacion, id_contaminante)
join {{ ref('dim_calendario') }} as c using (fecha)
where f.es_outlier
