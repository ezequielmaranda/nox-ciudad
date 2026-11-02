-- Bronze: los CSV anuales de SUBE (transacciones por línea y día), tal cual, todo como texto.
-- Los baja extract/sube_descarga.py a data/raw/sube/.
select
    DIA_TRANSPORTE as dia_transporte,
    NOMBRE_EMPRESA as nombre_empresa,
    LINEA as linea,
    AMBA as amba,
    TIPO_TRANSPORTE as tipo_transporte,
    JURISDICCION as jurisdiccion,
    PROVINCIA as provincia,
    MUNICIPIO as municipio,
    CANTIDAD as cantidad,
    DATO_PRELIMINAR as dato_preliminar,
    filename as archivo,
    current_timestamp as fecha_carga
from read_csv(
    '{{ ruta("data/raw/sube/dat-ab-usos-*.csv") }}',
    header = true,
    all_varchar = true,
    filename = true,
    union_by_name = true
)
