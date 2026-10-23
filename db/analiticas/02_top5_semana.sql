-- 02_top5_semana.sql
-- Top de funciones más demandadas: las 5 películas con más boletos vendidos en la
-- última semana a nivel global. Se cuentan los boletos vigentes emitidos en los últimos
-- 7 días (un boleto se emite en el momento en que se aprueba el pago).
--
--   docker exec imax_db psql -U imax_owner -d imax -f /db/analiticas/02_top5_semana.sql

select p.titulo,
       count(*) as boletos_vendidos
from cine.boleto b
join cine.funcion f on f.id_funcion = b.id_funcion
join cine.pelicula p on p.id_pelicula = f.id_pelicula
where b.estado = 'vigente'
  and b.emitido_en >= now() - interval '7 days'
group by p.id_pelicula, p.titulo
order by boletos_vendidos desc, p.titulo
limit 5;
