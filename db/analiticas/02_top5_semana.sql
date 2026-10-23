-- 02_top5_semana.sql
-- Top de funciones más demandadas: las 5 películas con más boletos vendidos en la
-- última semana a nivel global.
--
--   docker exec imax_db psql -U imax_owner -d imax -f /db/analiticas/02_top5_semana.sql

select p.titulo,
       count(*) as boletos_vendidos,
       sum(d.precio_unitario - d.descuento) as recaudacion_tarifas
from cine.orden o
join cine.boleto b on b.id_orden = o.id_orden and b.estado = 'vigente'
join cine.orden_detalle d on d.id_orden = b.id_orden and d.id_asiento = b.id_asiento
join cine.funcion f on f.id_funcion = o.id_funcion
join cine.pelicula p on p.id_pelicula = f.id_pelicula
where o.estado = 'pagada'
  and o.pagada_en >= now() - interval '7 days'
group by p.id_pelicula, p.titulo
order by boletos_vendidos desc, p.titulo
limit 5;
