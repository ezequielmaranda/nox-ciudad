{{ config(severity = 'warn') }}
-- Coherencia física: NOx = NO + NO2. Con valores publicados redondeados a enteros,
-- se tolera una diferencia de hasta 2 ppb. Las filas que devuelve son casos a revisar.
with v as (
    select estacion, fecha, estadistico,
        max(valor) filter (where contaminante = 'NO')  as no_,
        max(valor) filter (where contaminante = 'NO2') as no2,
        max(valor) filter (where contaminante = 'NOx') as nox
    from {{ ref('silver_aire') }}
    where estado_valor = 'valido' and estadistico in ('24h', '0-8', '8-16', '16-24')
    group by all
)
select *, nox - (no_ + no2) as diferencia
from v
where abs(nox - (no_ + no2)) > 2
