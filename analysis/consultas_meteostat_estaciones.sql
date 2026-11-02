select *
from stations
where id = '02956';

select *
from identifiers;

select *
from inventory
where station = '02956';

select *
from names
where name like 'Bue%'; -- station_id = '87585' - Buenos Aires Observatorio

select *
from names
where name like 'Aer%'; -- station_id = '87582' - Aeroparque Bs. As. Aerodrome