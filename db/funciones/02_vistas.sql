-- 02_vistas.sql
-- Vistas de consulta para la aplicación.

-- RN-01 y RN-02: solo funciones programadas con inicio futuro, con todos los datos
-- obligatorios de la película y la ubicación exacta de la sala.
create or replace view cine.v_cartelera_activa as
select f.id_funcion,
       f.inicio,
       f.fin,
       f.idioma,
       p.id_pelicula,
       p.titulo,
       p.sinopsis,
       p.duracion_min,
       p.poster_url,
       c.codigo as clasificacion,
       c.edad_minima,
       (select string_agg(g.nombre, ', ' order by g.nombre)
          from cine.pelicula_genero pg
          join cine.genero g on g.id_genero = pg.id_genero
         where pg.id_pelicula = p.id_pelicula) as generos,
       s.id_sala,
       s.nombre as sala,
       s.formato,
       se.id_sede,
       se.nombre as sede,
       se.direccion,
       ci.id_ciudad,
       ci.nombre as ciudad,
       pa.id_pais,
       pa.nombre as pais
from cine.funcion f
join cine.pelicula p on p.id_pelicula = f.id_pelicula
join cine.clasificacion c on c.id_clasificacion = p.id_clasificacion
join cine.sala s on s.id_sala = f.id_sala
join cine.sede se on se.id_sede = s.id_sede
join cine.ciudad ci on ci.id_ciudad = se.id_ciudad
join cine.pais pa on pa.id_pais = ci.id_pais
where f.estado = 'programada'
  and f.inicio > now()
  and p.es_activa
  and s.es_activa
  and se.es_activa;

-- RN-03: estado de cada asiento de la sala en cada función. Un bloqueo vencido se muestra
-- como disponible aunque el barrido todavía no lo haya borrado.
create or replace view cine.v_mapa_asientos as
select f.id_funcion,
       a.id_asiento,
       z.id_zona,
       z.nombre as zona,
       tz.codigo as tipo_zona,
       a.fila,
       a.numero,
       case
           when not a.es_habilitado then 'no_disponible'
           when o.estado = 'vendido' then 'ocupado'
           when o.estado = 'reservado' then 'reservado'
           when o.estado = 'bloqueado' and o.expira_en > now() then 'bloqueado'
           else 'disponible'
       end as estado,
       case when o.estado = 'bloqueado' and o.expira_en > now() then o.id_orden end as id_orden_bloqueo,
       case when o.estado = 'bloqueado' and o.expira_en > now() then o.expira_en end as expira_en
from cine.funcion f
join cine.zona z on z.id_sala = f.id_sala
join cine.tipo_zona tz on tz.id_tipo_zona = z.id_tipo_zona
join cine.asiento a on a.id_zona = z.id_zona
left join cine.ocupacion_asiento o on o.id_funcion = f.id_funcion and o.id_asiento = a.id_asiento;

-- RN-13: entradas compradas en línea por cada cliente. La aplicación filtra por el usuario
-- que inició sesión.
create or replace view cine.v_mis_entradas as
select o.id_usuario_cliente as id_usuario,
       b.id_boleto,
       b.codigo_qr,
       case when ch.id_boleto is not null then 'utilizada' else b.estado end as estado,
       o.id_orden,
       f.id_funcion,
       f.inicio,
       p.titulo,
       s.nombre as sala,
       se.nombre as sede,
       se.direccion,
       z.nombre as zona,
       a.fila,
       a.numero,
       tt.nombre as tipo_tarifa,
       d.precio_unitario - d.descuento as precio,
       b.emitido_en
from cine.boleto b
join cine.orden o on o.id_orden = b.id_orden
join cine.orden_detalle d on d.id_orden = b.id_orden and d.id_asiento = b.id_asiento
join cine.tipo_tarifa tt on tt.id_tipo_tarifa = d.id_tipo_tarifa
join cine.funcion f on f.id_funcion = b.id_funcion
join cine.pelicula p on p.id_pelicula = f.id_pelicula
join cine.sala s on s.id_sala = f.id_sala
join cine.sede se on se.id_sede = s.id_sede
join cine.asiento a on a.id_asiento = b.id_asiento
join cine.zona z on z.id_zona = a.id_zona
left join cine.checkin ch on ch.id_boleto = b.id_boleto
where o.id_usuario_cliente is not null;
