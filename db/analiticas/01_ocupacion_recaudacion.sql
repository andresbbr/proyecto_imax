-- 01_ocupacion_recaudacion.sql
-- Ocupación y recaudación por función: porcentaje de asientos vendidos frente a la
-- capacidad de la sala e ingresos totales de una función específica.
--
--   docker exec imax_db psql -U imax_owner -d imax -v id_funcion=123 -f /db/analiticas/01_ocupacion_recaudacion.sql
--
-- Sin -v id_funcion se usa la función ya realizada con más boletos vendidos.

\if :{?id_funcion}
\else
    select b.id_funcion
    from cine.boleto b
    join cine.funcion f on f.id_funcion = b.id_funcion
    where f.inicio < now() and b.estado = 'vigente'
    group by b.id_funcion
    order by count(*) desc, b.id_funcion
    limit 1 \gset
\endif

select f.id_funcion,
       p.titulo,
       se.nombre as sede,
       s.nombre as sala,
       f.inicio,
       cap.capacidad,
       ven.vendidos,
       round(100.0 * ven.vendidos / cap.capacidad, 2) as porcentaje_ocupacion,
       ing.ventas - ing.reembolsos as ingresos_totales
from cine.funcion f
join cine.pelicula p on p.id_pelicula = f.id_pelicula
join cine.sala s on s.id_sala = f.id_sala
join cine.sede se on se.id_sede = s.id_sede
cross join lateral (
    select count(*) as capacidad
    from cine.asiento a
    join cine.zona z on z.id_zona = a.id_zona
    where z.id_sala = f.id_sala and a.es_habilitado
) as cap
cross join lateral (
    select count(*) as vendidos
    from cine.boleto b
    where b.id_funcion = f.id_funcion and b.estado = 'vigente'
) as ven
cross join lateral (
    select coalesce((select sum(o.total) from cine.orden o
                     where o.id_funcion = f.id_funcion and o.estado = 'pagada'), 0) as ventas,
           coalesce((select sum(r.monto) from cine.reembolso r
                     join cine.boleto b on b.id_boleto = r.id_boleto
                     where b.id_funcion = f.id_funcion), 0) as reembolsos
) as ing
where f.id_funcion = :id_funcion;
