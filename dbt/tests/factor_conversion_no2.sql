-- El factor de conversión del NO2 tiene que ser ≈ 1,88 µg/m³ por ppb (25 °C, 1 atm) y el del
-- CO ≈ 1,145 mg/m³ por ppm. Además, en la fact valor_masa / valor tiene que dar ese factor.
select 'dim_contaminante' as donde, id_contaminante, factor_masa as factor
from {{ ref('dim_contaminante') }}
where (id_contaminante = 'no2' and abs(factor_masa - 1.88) > 0.01)
   or (id_contaminante = 'co'  and abs(factor_masa - 1.145) > 0.005)
union all
select 'fact_medicion_diaria', id_contaminante, valor_masa / valor
from {{ ref('fact_medicion_diaria') }}
where id_contaminante = 'no2' and tiene_dato and valor > 0
  and abs(valor_masa / valor - 1.88) > 0.01
