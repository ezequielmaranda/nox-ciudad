-- El cociente NOx/CO tiene que ser positivo. Un 0 o un negativo indica un valor imposible
-- que se filtró a gold (como el NOx 8-16 = 0 de La Boca del 29/02/2024 antes de los controles).
select estacion, fecha, nox_816_ppb, co_816_ppm, nox_co_816
from {{ ref('gold_aire_diario') }}
where nox_co_816 <= 0
