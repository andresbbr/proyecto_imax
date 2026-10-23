-- 03_metodos_pago.sql
-- Métodos de pago preferidos: porcentaje de pagos aprobados (y del monto cobrado) por
-- cada método o pasarela.
--
--   docker exec imax_db psql -U imax_owner -d imax -f /db/analiticas/03_metodos_pago.sql

select m.nombre as metodo_pago,
       count(*) as pagos,
       round(100.0 * count(*) / sum(count(*)) over (), 2) as porcentaje_pagos,
       sum(p.monto) as monto,
       round(100.0 * sum(p.monto) / sum(sum(p.monto)) over (), 2) as porcentaje_monto
from cine.pago p
join cine.metodo_pago m on m.id_metodo_pago = p.id_metodo_pago
where p.estado = 'aprobado'
group by m.id_metodo_pago, m.nombre
order by pagos desc;
