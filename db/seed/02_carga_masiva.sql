-- 02_carga_masiva.sql
-- Carga masiva con generate_series para que las tablas tengan millones de filas y los planes
-- de EXPLAIN ANALYZE sean representativos. Todo se genera con SQL por conjuntos.
-- La escala por defecto (60 sedes, 90 días) está limitada por el espacio en disco del equipo
-- de desarrollo; con más espacio se puede subir, por ejemplo -v salas=300 -v dias=180.
-- Escala (se puede cambiar con -v al ejecutar psql):
--   salas         cantidad de sedes sintéticas, con una sala de 300 asientos cada una
--   dias          días de historia hacia atrás (más 7 días de funciones futuras)
--   max_asientos  asientos vendidos por función: al azar entre 0 y este valor

\if :{?salas}
\else
    \set salas 60
\endif
\if :{?dias}
\else
    \set dias 90
\endif
\if :{?max_asientos}
\else
    \set max_asientos 16
\endif

\echo 'Sedes, salas, zonas, asientos y puertas...'

insert into cine.sede (id_ciudad, nombre, direccion)
select ci.id_ciudad, 'IMAX Sede ' || lpad(i::text, 3, '0'), 'Dirección de la sede ' || i
from generate_series(1, :salas) as i
join (select id_ciudad, row_number() over (order by id_ciudad) - 1 as k, count(*) over () as total
      from cine.ciudad) as ci on ci.k = i % ci.total;

insert into cine.sala (id_sede, nombre, formato)
select id_sede, 'Sala IMAX 1', case when id_sede % 2 = 0 then 'IMAX con láser' else 'IMAX digital' end
from cine.sede
where nombre like 'IMAX Sede %';

create temp table sala_carga as
select s.id_sala, s.id_sede
from cine.sala s
join cine.sede se on se.id_sede = s.id_sede
where se.nombre like 'IMAX Sede %';

insert into cine.zona (id_sala, id_tipo_zona, nombre)
select s.id_sala, tz.id_tipo_zona, tz.nombre
from sala_carga s
cross join cine.tipo_zona tz;

-- 15 filas de 20 asientos: A-F general, G-L preferencial, M-O VIP
insert into cine.asiento (id_zona, fila, numero)
select z.id_zona, f.fila, n
from cine.zona z
join sala_carga s on s.id_sala = z.id_sala
join cine.tipo_zona tz on tz.id_tipo_zona = z.id_tipo_zona
join (values ('A', 'general'), ('B', 'general'), ('C', 'general'), ('D', 'general'), ('E', 'general'), ('F', 'general'),
             ('G', 'preferencial'), ('H', 'preferencial'), ('I', 'preferencial'), ('J', 'preferencial'),
             ('K', 'preferencial'), ('L', 'preferencial'), ('M', 'vip'), ('N', 'vip'), ('O', 'vip')) as f (fila, tipo)
     on f.tipo = tz.codigo
cross join generate_series(1, 20) as n;

insert into cine.puerta (id_sala, codigo, tipo)
select id_sala, 'P-' || id_sala || '-1', 'totem' from sala_carga;

insert into cine.tarifa (id_sede, id_tipo_zona, id_tipo_tarifa, tipo_dia, precio)
select s.id_sede, tz.id_tipo_zona, tt.id_tipo_tarifa, d.tipo_dia,
       round(b.base
             * case tz.codigo when 'general' then 1 when 'preferencial' then 1.25 else 1.6 end
             * case tt.codigo when 'adulto' then 1 when 'nino' then 0.7 when 'tercera_edad' then 0.6 else 0.8 end
             * case d.tipo_dia when 'fin_de_semana' then 1.15 else 1 end, 2)
from sala_carga s
join cine.sede se on se.id_sede = s.id_sede
join cine.ciudad ci on ci.id_ciudad = se.id_ciudad
join cine.pais pa on pa.id_pais = ci.id_pais
join (values ('CR', 8.00), ('MX', 7.00), ('US', 18.00), ('ES', 12.00)) as b (pais, base) on b.pais = pa.codigo_iso
cross join cine.tipo_zona tz
cross join cine.tipo_tarifa tt
cross join (values ('entre_semana'), ('fin_de_semana')) as d (tipo_dia)
where not tt.es_cortesia;

\echo 'Usuarios sintéticos...'

insert into cine.usuario (id_rol, email, contrasena_hash, nombre, apellidos)
select (select id_rol from cine.rol where codigo = 'cliente'),
       'cliente' || lpad(i::text, 6, '0') || '@demo.local', 'sin-acceso', 'Cliente', 'Sintético ' || i
from generate_series(1, 50000) as i;

insert into cine.usuario (id_rol, email, contrasena_hash, nombre, apellidos)
select (select id_rol from cine.rol where codigo = 'administrador'),
       'admin' || lpad(i::text, 2, '0') || '@demo.local', 'sin-acceso', 'Administrador', 'Sintético ' || i
from generate_series(1, 9) as i;

\echo 'Funciones: 5 por sala y día...'

insert into cine.funcion (id_pelicula, id_sala, inicio, fin, idioma)
select p.id_pelicula, h.id_sala, h.inicio, h.inicio + make_interval(mins => p.duracion_min + 15),
       case when h.n % 3 = 0 then 'Doblada' else 'Original subtitulada' end
from (
    select s.id_sala, ((current_date + d) || ' ' || hora || ' -06')::timestamptz as inicio,
           s.id_sala + d * 5 + k as n
    from sala_carga s
    cross join generate_series(-:dias, 6) as d
    cross join unnest(array['10:00', '13:00', '16:00', '19:00', '22:00']) with ordinality as x (hora, k)
) as h
join (select id_pelicula, duracion_min, row_number() over (order by id_pelicula) - 1 as k, count(*) over () as total
      from cine.pelicula) as p on p.k = mod(mod(h.n, p.total) + p.total, p.total);  -- n puede ser negativo

\echo 'Ventas: asientos vendidos por función...'

create temp table asiento_sala as
select z.id_sala, a.id_asiento, z.id_tipo_zona,
       row_number() over (partition by z.id_sala order by a.id_asiento) - 1 as pos,
       count(*) over (partition by z.id_sala) as total
from cine.asiento a
join cine.zona z on z.id_zona = a.id_zona
join sala_carga s on s.id_sala = z.id_sala;

-- Asientos vendidos: n al azar por función, consecutivos desde una posición al azar.
-- Cada orden lleva 2 asientos.
create temp table venta as
select f.id_funcion, f.id_sala, f.inicio, a.id_asiento, a.id_tipo_zona, (g + 1) / 2 as grupo,
       case when r < 0.70 then 'adulto' when r < 0.82 then 'estudiante' when r < 0.92 then 'nino' else 'tercera_edad' end as tipo
from (select f.id_funcion, f.id_sala, f.inicio,
             floor(random() * (:max_asientos + 1))::int as n, floor(random() * 300)::int as desde
      from cine.funcion f
      join sala_carga s on s.id_sala = f.id_sala) as f
cross join lateral generate_series(1, f.n) as g
join asiento_sala a on a.id_sala = f.id_sala and a.pos = (f.desde + g) % a.total
cross join lateral (select random() as r) as x;

analyze venta;

create temp table orden_carga as
select (select coalesce(max(id_orden), 0) from cine.orden) + row_number() over (order by id_funcion, grupo) as id_orden,
       id_funcion, grupo, inicio,
       case when random() < 0.85 then 'en_linea' else 'taquilla' end as canal,
       least(now(), inicio) - random() * interval '7 days' as pagada_en
from (select distinct id_funcion, grupo, inicio from venta) as v;

analyze orden_carga;

create temp table linea as
select v.id_funcion, v.id_asiento, v.inicio, o.id_orden, tt.id_tipo_tarifa, t.precio, pa.tasa_impuesto
from venta v
join orden_carga o on o.id_funcion = v.id_funcion and o.grupo = v.grupo
join sala_carga s on s.id_sala = v.id_sala
join cine.sede se on se.id_sede = s.id_sede
join cine.ciudad ci on ci.id_ciudad = se.id_ciudad
join cine.pais pa on pa.id_pais = ci.id_pais
join cine.tipo_tarifa tt on tt.codigo = v.tipo
join cine.tarifa t on t.id_sede = s.id_sede and t.id_tipo_zona = v.id_tipo_zona and t.id_tipo_tarifa = tt.id_tipo_tarifa
                  and t.tipo_dia = case when extract(isodow from v.inicio) in (6, 7) then 'fin_de_semana' else 'entre_semana' end;

create index on orden_carga (id_orden);
create index on linea (id_orden, id_asiento);
analyze orden_carga;
analyze linea;

\echo 'Órdenes y líneas...'

insert into cine.orden (id_orden, id_funcion, canal, id_usuario_cliente, id_usuario_vendedor, estado,
                        subtotal, descuento, cargo_servicio, impuesto, total, creado_en, pagada_en)
overriding system value
select o.id_orden, o.id_funcion, o.canal,
       case when o.canal = 'en_linea' then c.primero + floor(random() * 50000)::bigint end,
       case when o.canal = 'taquilla' then c.taquillero end,
       'pagada', l.subtotal, 0, l.cargo, round((l.subtotal + l.cargo) * l.tasa, 2),
       l.subtotal + l.cargo + round((l.subtotal + l.cargo) * l.tasa, 2),
       o.pagada_en - interval '3 minutes', o.pagada_en
from orden_carga o
join (select x.id_orden, x.subtotal, x.tasa,
             case when oc.canal = 'en_linea' then cine.parametro('cargo_servicio') * x.boletos else 0 end as cargo
      from (select id_orden, sum(precio) as subtotal, max(tasa_impuesto) as tasa, count(*) as boletos
            from linea group by id_orden) as x
      join orden_carga oc on oc.id_orden = x.id_orden) as l on l.id_orden = o.id_orden
cross join (select (select min(id_usuario) from cine.usuario where email like 'cliente%@demo.local') as primero,
                   (select id_usuario from cine.usuario where email = 'taquilla@imax.demo') as taquillero) as c;

select setval(pg_get_serial_sequence('cine.orden', 'id_orden'), (select max(id_orden) from cine.orden));

insert into cine.orden_detalle (id_orden, id_asiento, id_tipo_tarifa, precio_unitario)
select id_orden, id_asiento, id_tipo_tarifa, precio from linea;

\echo 'Pagos...'

-- 13 % de las órdenes tuvo un intento rechazado antes del aprobado
insert into cine.pago (id_orden, id_metodo_pago, monto, estado, token_pasarela, motivo_rechazo, ultimos4, marca,
                       solicitado_en, respondido_en)
select o.id_orden, (select id_metodo_pago from cine.metodo_pago where codigo = 'tarjeta_credito'), o.total, 'rechazado',
       'tok_' || md5(o.id_orden::text || 'r'), 'Fondos insuficientes', '0002', 'visa',
       o.pagada_en - interval '5 minutes', o.pagada_en - interval '4 minutes'
from cine.orden o
join orden_carga c on c.id_orden = o.id_orden
where random() < 0.13;

insert into cine.pago (id_orden, id_metodo_pago, monto, estado, token_pasarela, codigo_autorizacion, ultimos4, marca,
                       solicitado_en, respondido_en)
select x.id_orden, m.id_metodo_pago, x.total, 'aprobado', 'tok_' || md5(x.id_orden::text),
       upper(substr(md5(x.id_orden::text || 'a'), 1, 8)),
       case when m.es_tarjeta then lpad((1000 + floor(random() * 8999))::int::text, 4, '0') end,
       case when m.es_tarjeta then (array['visa', 'mastercard', 'amex'])[1 + floor(random() * 3)::int] end,
       x.pagada_en - interval '1 minute', x.pagada_en
from (select o.id_orden, o.total, o.pagada_en, random() as r
      from cine.orden o
      join orden_carga c on c.id_orden = o.id_orden) as x
join cine.metodo_pago m on m.codigo = case when x.r < 0.45 then 'tarjeta_credito'
                                           when x.r < 0.70 then 'tarjeta_debito'
                                           when x.r < 0.85 then 'paypal'
                                           when x.r < 0.95 then 'billetera_digital'
                                           else 'transferencia' end;

\echo 'Boletos, reembolsos, ocupación y check-in...'

-- 1 % de los boletos se anuló con reembolso
insert into cine.boleto (id_orden, id_asiento, id_funcion, codigo_qr, estado, emitido_en)
select l.id_orden, l.id_asiento, l.id_funcion, upper(replace(gen_random_uuid()::text, '-', '')),
       case when random() < 0.01 then 'anulado' else 'vigente' end, o.pagada_en
from linea l
join orden_carga o on o.id_orden = l.id_orden;

insert into cine.reembolso (id_boleto, id_pago, id_usuario_autoriza, tipo, monto, motivo, creado_en)
select b.id_boleto, p.id_pago, (select id_usuario from cine.usuario where email = 'admin@imax.demo'), 'politica',
       round(d.precio_unitario * (1 + l.tasa_impuesto), 2), 'Solicitud del cliente', b.emitido_en + interval '1 hour'
from cine.boleto b
join linea l on l.id_orden = b.id_orden and l.id_asiento = b.id_asiento
join cine.orden_detalle d on d.id_orden = b.id_orden and d.id_asiento = b.id_asiento
join cine.pago p on p.id_orden = b.id_orden and p.estado = 'aprobado'
where b.estado = 'anulado';

-- Los asientos vendidos de funciones futuras quedan en el inventario
insert into cine.ocupacion_asiento (id_funcion, id_asiento, id_orden, id_usuario, estado, creado_en)
select b.id_funcion, b.id_asiento, b.id_orden, coalesce(o.id_usuario_cliente, o.id_usuario_vendedor), 'vendido', b.emitido_en
from cine.boleto b
join cine.orden o on o.id_orden = b.id_orden
join orden_carga c on c.id_orden = b.id_orden
where b.estado = 'vigente' and c.inicio > now();

-- El 95 % de los boletos de funciones pasadas ingresó por la puerta de su sala
insert into cine.checkin (id_boleto, id_puerta, validado_en)
select b.id_boleto, pu.id_puerta, c.inicio - random() * interval '25 minutes'
from cine.boleto b
join orden_carga c on c.id_orden = b.id_orden
join cine.funcion f on f.id_funcion = b.id_funcion
join cine.puerta pu on pu.id_sala = f.id_sala
where b.estado = 'vigente' and c.inicio < now() and random() < 0.95;

\echo 'Bitácoras...'

insert into bitacora.transaccion_log (ocurrido_en, id_orden, id_pago, evento, monto, impuesto, detalle)
select p.respondido_en, p.id_orden, p.id_pago,
       case p.estado when 'aprobado' then 'pago_aprobado' else 'pago_rechazado' end,
       p.monto, o.impuesto, jsonb_build_object('metodo', m.codigo)
from cine.pago p
join orden_carga c on c.id_orden = p.id_orden
join cine.orden o on o.id_orden = p.id_orden
join cine.metodo_pago m on m.id_metodo_pago = p.id_metodo_pago;

insert into bitacora.transaccion_log (ocurrido_en, id_orden, evento, detalle)
select c.pagada_en, c.id_orden, 'boletos_emitidos', jsonb_build_object('boletos', count(*))
from orden_carga c
join linea l on l.id_orden = c.id_orden
group by c.id_orden, c.pagada_en;

insert into bitacora.asiento_auditoria_log (ocurrido_en, id_funcion, id_asiento, id_orden, id_usuario, evento)
select b.emitido_en, b.id_funcion, b.id_asiento, b.id_orden, coalesce(o.id_usuario_cliente, o.id_usuario_vendedor), 'compra'
from cine.boleto b
join cine.orden o on o.id_orden = b.id_orden
join orden_carga c on c.id_orden = b.id_orden;

insert into bitacora.acceso_puerta_log (ocurrido_en, codigo_qr_leido, id_boleto, id_puerta, id_funcion_en_curso, resultado, mensaje)
select ch.validado_en, b.codigo_qr, b.id_boleto, ch.id_puerta, b.id_funcion, 'exitoso', 'Acceso permitido'
from cine.checkin ch
join cine.boleto b on b.id_boleto = ch.id_boleto
join orden_carga c on c.id_orden = b.id_orden;

-- 3 % de los ingresos tuvo un segundo escaneo rechazado
insert into bitacora.acceso_puerta_log (ocurrido_en, codigo_qr_leido, id_boleto, id_puerta, id_funcion_en_curso, resultado, mensaje)
select ch.validado_en + interval '2 minutes', b.codigo_qr, b.id_boleto, ch.id_puerta, b.id_funcion, 'duplicado', 'Entrada ya utilizada'
from cine.checkin ch
join cine.boleto b on b.id_boleto = ch.id_boleto
join orden_carga c on c.id_orden = b.id_orden
where random() < 0.03;

-- Operaciones manuales de los administradores en el período
insert into bitacora.admin_operacion_audit (ocurrido_en, id_usuario, id_rol, ip, operacion, entidad, id_entidad, motivo)
select now() - random() * make_interval(days => :dias), a.id_usuario, a.id_rol,
       ('10.0.' || floor(random() * 255)::int || '.' || (1 + floor(random() * 254)::int))::inet,
       op.operacion, op.entidad, floor(random() * 100000)::int::text, 'Operación de la carga masiva'
from generate_series(1, 20000) as i
cross join lateral (select id_usuario, id_rol from cine.usuario
                    where id_rol = (select id_rol from cine.rol where codigo = 'administrador')
                    order by random() + i * 0 limit 1) as a
cross join lateral (select * from (values ('cortesia', 'boleto'), ('reembolso_forzado', 'boleto'),
                                          ('cambio_asiento', 'boleto'), ('cambio_tarifa', 'tarifa'),
                                          ('cambio_funcion', 'funcion'), ('alta_funcion', 'funcion')) as v (operacion, entidad)
                    order by random() + i * 0 limit 1) as op;

\echo 'Actualizando estadísticas...'
analyze;
