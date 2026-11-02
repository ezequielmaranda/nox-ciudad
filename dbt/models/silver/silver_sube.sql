-- Silver: SUBE tipado, con el número de línea normalizado y la marca de universo CABA.
-- Grano: fecha × empresa × etiqueta de línea × tipo de transporte (como viene de la fuente).
--
-- Por qué hace falta normalizar: la misma línea cambia de etiqueta en el tiempo
-- ("LINEA 12" -> "CABA_LINEA_12"; "CABA_LINEA_25" -> "CABA_LINEA_025" al cambiar de operador;
-- espacios como "CABA_LINEA_ 42"). La clave estable es el número del final.
with base as (
    select
        cast(substr(dia_transporte, 1, 10) as date) as fecha,
        trim(nombre_empresa) as empresa,
        linea as linea_original,
        try_cast(regexp_extract(trim(linea), '([0-9]+)\s*$', 1) as integer) as linea_num,
        amba = 'SI' as es_amba,
        tipo_transporte,
        jurisdiccion,
        provincia,
        municipio,
        try_cast(cantidad as bigint) as usos,
        dato_preliminar = 'SI' as es_dato_preliminar
    from {{ ref('bronze_sube') }}
),

-- Las 31 líneas que circulan solo por CABA: las que en algún momento figuran con jurisdicción C.A.B.A
-- (se traspasaron de Nación a la Ciudad el 20/01/2025).
lineas_solo_caba as (
    select distinct linea_num
    from base
    where jurisdiccion = 'C.A.B.A' and tipo_transporte = 'COLECTIVO'
)

select
    base.*,
    -- Universo de análisis: colectivos del AMBA que circulan por CABA. Son las líneas 1 a 199 de
    -- jurisdicción nacional (interjurisdiccionales) o de la Ciudad. Se incluyen las etiquetas
    -- "CABA_..." aunque tengan la jurisdicción mal cargada. No se usa PROVINCIA = 'BUENOS AIRES':
    -- eso excluye justamente a CABA. Las líneas 8012-8188 (mayo 2024) quedan afuera por número.
    (
        base.tipo_transporte = 'COLECTIVO'
        and base.es_amba
        and base.linea_num < 200
        and (base.jurisdiccion in ('NACIONAL', 'C.A.B.A') or base.linea_original like 'CABA_%')
    ) as es_colectivo_caba,
    base.linea_num in (select linea_num from lineas_solo_caba) as es_linea_solo_caba
from base
