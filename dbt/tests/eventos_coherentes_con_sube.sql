-- El seed de eventos tiene que ser coherente con lo que muestran los datos de SUBE:
-- en los paros "sin_colectivos" paró más de la mitad de las líneas de colectivo; en los "trenes_subte"
-- los colectivos funcionaron (casi ninguna línea parada) y el tren o el subte tuvo menos del 30% de sus viajes.
-- Si alguien agrega un evento mal clasificado, el build falla.
select e.fecha, e.evento, e.grupo, s.pct_lineas_paradas_ponderado
from {{ ref('eventos') }} as e
join {{ ref('gold_sube_diario') }} as s using (fecha)
where (e.grupo = 'sin_colectivos' and s.pct_lineas_paradas_ponderado < 50)
   or (e.grupo = 'trenes_subte' and (s.pct_lineas_paradas_ponderado > 5
                                      or least(s.ratio_tren, s.ratio_subte) >= 0.3))
   or s.pct_lineas_paradas_ponderado is null  -- un evento tiene que caer en un día con dosis medible
