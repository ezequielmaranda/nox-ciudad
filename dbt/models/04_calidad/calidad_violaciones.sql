-- =====================================================================================
-- 04 · CALIDAD: listado de cada valor horario del período de estudio que viola una regla de
-- validación (una fila por regla; un mismo valor puede violar más de una). Todos quedan fuera
-- del análisis. No incluye los 's/d' (falta de dato, no error) ni las horas inválidas vacías.
-- =====================================================================================
with v as (
    select *
    from {{ ref('stg_aire_horario_validado') }}
    where fecha between '{{ var("fecha_inicio") }}' and '{{ var("fecha_fin") }}'
),

reglas as (
    select *, 'hora_invalida' as regla from v where hora_invalida and estado_valor <> 'sin_dato'
    union all
    select *, 'texto_invalido' from v where estado_valor = 'invalido'
    union all
    select *, 'fuera_de_rango' from v where fuera_de_rango
    union all
    select *, 'fila_en_cero' from v where fila_en_cero
    union all
    select *, 'valor_trabado' from v where valor_trabado
)

select
    fecha,
    hora,
    id_estacion,
    id_contaminante,
    valor_crudo,
    regla,
    motivo_invalido
from reglas
