-- 01_restricciones.sql
-- Pruebas de las restricciones del DDL (PK, FK, UNIQUE, CHECK, NOT NULL) y de los permisos
-- de los roles. Cada caso indica si debe aceptarse o rechazarse. Todo ocurre dentro de una
-- transacción que se revierte al final, así que la base queda igual que antes.
--
--   psql -U imax_owner -d imax -v ON_ERROR_STOP=1 -f db/tests/01_restricciones.sql

\set ON_ERROR_STOP on
\pset footer off
set client_min_messages = warning;

begin;

create temp table resultado (
    n         serial,
    prueba    text,
    esperado  text,
    obtenido  text,
    detalle   text
);

-- Ejecuta una sentencia y anota si fue aceptada o rechazada
create function pg_temp.probar(p_prueba text, p_sql text, p_debe_fallar boolean) returns void
language plpgsql as $$
declare
    v_esperado text := case when p_debe_fallar then 'rechaza' else 'acepta' end;
begin
    begin
        execute p_sql;
        insert into resultado (prueba, esperado, obtenido) values (p_prueba, v_esperado, 'acepta');
    exception when others then
        insert into resultado (prueba, esperado, obtenido, detalle) values (p_prueba, v_esperado, 'rechaza', sqlerrm);
    end;
end $$;

-- Datos válidos (pruebas positivas) -------------------------------------------------
-- Se usan identificadores fijos (9800900 en adelante) para poder referirlos en las pruebas siguientes.

select pg_temp.probar('país válido',
  $q$insert into cine.pais (id_pais, codigo_iso, nombre, tasa_impuesto) overriding system value values (30900, 'ZZ', 'País de prueba', 0.13)$q$, false);
select pg_temp.probar('ciudad válida',
  $q$insert into cine.ciudad (id_ciudad, id_pais, nombre) overriding system value values (9800900, 30900, 'Ciudad de prueba')$q$, false);
select pg_temp.probar('sede válida',
  $q$insert into cine.sede (id_sede, id_ciudad, nombre, direccion) overriding system value values (9800900, 9800900, 'IMAX Prueba', 'Calle 1')$q$, false);
select pg_temp.probar('sala válida',
  $q$insert into cine.sala (id_sala, id_sede, nombre, formato) overriding system value values (9800900, 9800900, 'Sala 1', 'IMAX con láser')$q$, false);
select pg_temp.probar('zona válida',
  $q$insert into cine.zona (id_zona, id_sala, id_tipo_zona, nombre) overriding system value
     values (9800900, 9800900, (select id_tipo_zona from cine.tipo_zona where codigo = 'general'), 'Platea')$q$, false);
select pg_temp.probar('segunda sala y zona, sin funciones',
  $q$insert into cine.sala (id_sala, id_sede, nombre, formato) overriding system value values (9800901, 9800900, 'Sala 2', 'IMAX digital');
     insert into cine.zona (id_zona, id_sala, id_tipo_zona, nombre) overriding system value
     values (9800901, 9800901, (select id_tipo_zona from cine.tipo_zona where codigo = 'general'), 'Platea')$q$, false);
select pg_temp.probar('asientos válidos',
  $q$insert into cine.asiento (id_asiento, id_zona, fila, numero) overriding system value
     values (9800901, 9800900, 'A', 1), (9800902, 9800900, 'A', 2), (9800903, 9800900, 'A', 3)$q$, false);
select pg_temp.probar('puerta válida',
  $q$insert into cine.puerta (id_puerta, id_sala, codigo, tipo) overriding system value values (9800900, 9800900, 'P-900', 'totem')$q$, false);
select pg_temp.probar('película válida',
  $q$insert into cine.pelicula (id_pelicula, id_clasificacion, titulo, sinopsis, duracion_min, poster_url, fecha_estreno)
     overriding system value values (9800900, (select id_clasificacion from cine.clasificacion where codigo = 'TP'),
     'Película de prueba', 'Sinopsis', 120, 'https://ejemplo.com/poster.jpg', '2026-11-01')$q$, false);
select pg_temp.probar('función válida',
  $q$insert into cine.funcion (id_funcion, id_pelicula, id_sala, inicio, fin, idioma) overriding system value
     values (9800900, 9800900, 9800900, '2026-12-01 20:00-06', '2026-12-01 22:15-06', 'Subtitulada')$q$, false);
select pg_temp.probar('tarifa válida',
  $q$insert into cine.tarifa (id_sede, id_tipo_zona, id_tipo_tarifa, tipo_dia, precio) values (9800900,
     (select id_tipo_zona from cine.tipo_zona where codigo = 'general'),
     (select id_tipo_tarifa from cine.tipo_tarifa where codigo = 'adulto'), 'entre_semana', 10.00)$q$, false);
select pg_temp.probar('promoción 2x1 válida',
  $q$insert into cine.promocion (codigo, nombre, tipo, dia_semana, vigente_desde, vigente_hasta)
     values ('P2X1-PRUEBA', '2x1 los martes', '2x1', 2, '2026-01-01', '2026-12-31')$q$, false);
select pg_temp.probar('usuario cliente válido',
  $q$insert into cine.usuario (id_usuario, id_rol, email, contrasena_hash, nombre, apellidos) overriding system value
     values (9800900, (select id_rol from cine.rol where codigo = 'cliente'), 'cliente@prueba.com', 'hash', 'Ana', 'Prueba')$q$, false);
select pg_temp.probar('usuario administrador válido',
  $q$insert into cine.usuario (id_usuario, id_rol, email, contrasena_hash, nombre, apellidos) overriding system value
     values (9800901, (select id_rol from cine.rol where codigo = 'administrador'), 'admin@prueba.com', 'hash', 'Luis', 'Prueba')$q$, false);
select pg_temp.probar('orden en línea con total coherente',
  $q$insert into cine.orden (id_orden, id_funcion, canal, id_usuario_cliente, subtotal, descuento, cargo_servicio, impuesto, total)
     overriding system value values (9800900, 9800900, 'en_linea', 9800900, 20.00, 0, 3.00, 2.60, 25.60)$q$, false);
select pg_temp.probar('líneas de la orden',
  $q$insert into cine.orden_detalle (id_orden, id_asiento, id_tipo_tarifa, precio_unitario)
     values (9800900, 9800901, (select id_tipo_tarifa from cine.tipo_tarifa where codigo = 'adulto'), 10.00),
            (9800900, 9800902, (select id_tipo_tarifa from cine.tipo_tarifa where codigo = 'adulto'), 10.00)$q$, false);
select pg_temp.probar('bloqueo temporal de un asiento',
  $q$insert into cine.ocupacion_asiento (id_funcion, id_asiento, id_orden, id_usuario, estado, expira_en)
     values (9800900, 9800901, 9800900, 9800900, 'bloqueado', now() + interval '2 minutes')$q$, false);

-- Doble venta (RN-05, RN-12) -----------------------------------------------------------

select pg_temp.probar('segundo bloqueo del mismo asiento en la misma función',
  $q$insert into cine.ocupacion_asiento (id_funcion, id_asiento, id_orden, id_usuario, estado, expira_en)
     values (9800900, 9800901, 9800900, 9800901, 'bloqueado', now() + interval '2 minutes')$q$, true);
select pg_temp.probar('el bloqueo pasa a vendido',
  $q$update cine.ocupacion_asiento set estado = 'vendido', expira_en = null where id_funcion = 9800900 and id_asiento = 9800901$q$, false);
select pg_temp.probar('venta de un asiento ya vendido',
  $q$insert into cine.ocupacion_asiento (id_funcion, id_asiento, id_orden, id_usuario, estado)
     values (9800900, 9800901, 9800900, 9800901, 'vendido')$q$, true);

-- Pago (RN-09, RN-10) --------------------------------------------------------------------

select pg_temp.probar('pago rechazado con motivo',
  $q$insert into cine.pago (id_orden, id_metodo_pago, monto, estado, motivo_rechazo, ultimos4, marca)
     values (9800900, (select id_metodo_pago from cine.metodo_pago where codigo = 'tarjeta_credito'), 25.60, 'rechazado', 'Fondos insuficientes', '0002', 'visa')$q$, false);
select pg_temp.probar('pago aprobado con tarjeta',
  $q$insert into cine.pago (id_pago, id_orden, id_metodo_pago, monto, estado, token_pasarela, codigo_autorizacion, ultimos4, marca)
     overriding system value values (9800900, 9800900, (select id_metodo_pago from cine.metodo_pago where codigo = 'tarjeta_credito'),
     25.60, 'aprobado', 'tok_prueba', 'AUT123', '4242', 'visa')$q$, false);
select pg_temp.probar('la orden pasa a pagada',
  $q$update cine.orden set estado = 'pagada', pagada_en = now() where id_orden = 9800900$q$, false);
select pg_temp.probar('segundo pago aprobado de la misma orden',
  $q$insert into cine.pago (id_orden, id_metodo_pago, monto, estado, codigo_autorizacion)
     values (9800900, (select id_metodo_pago from cine.metodo_pago where codigo = 'paypal'), 25.60, 'aprobado', 'AUT999')$q$, true);
select pg_temp.probar('pago aprobado sin código de autorización',
  $q$insert into cine.pago (id_orden, id_metodo_pago, monto, estado)
     values (9800900, (select id_metodo_pago from cine.metodo_pago where codigo = 'paypal'), 25.60, 'aprobado')$q$, true);
select pg_temp.probar('pago rechazado sin motivo',
  $q$insert into cine.pago (id_orden, id_metodo_pago, monto, estado)
     values (9800900, (select id_metodo_pago from cine.metodo_pago where codigo = 'paypal'), 25.60, 'rechazado')$q$, true);
select pg_temp.probar('últimos 4 dígitos con letras',
  $q$insert into cine.pago (id_orden, id_metodo_pago, monto, estado, motivo_rechazo, ultimos4, marca)
     values (9800900, 1, 25.60, 'rechazado', 'x', '42AB', 'visa')$q$, true);
select pg_temp.probar('últimos 4 dígitos sin marca',
  $q$insert into cine.pago (id_orden, id_metodo_pago, monto, estado, motivo_rechazo, ultimos4)
     values (9800900, 1, 25.60, 'rechazado', 'x', '4242')$q$, true);
select pg_temp.probar('pago con monto cero',
  $q$insert into cine.pago (id_orden, id_metodo_pago, monto, estado, motivo_rechazo) values (9800900, 1, 0, 'rechazado', 'x')$q$, true);

-- Boletos (RN-12) y check-in (RN-14) ----------------------------------------------------

select pg_temp.probar('boleto válido',
  $q$insert into cine.boleto (id_boleto, id_orden, id_asiento, id_funcion, codigo_qr) overriding system value
     values (9800900, 9800900, 9800901, 9800900, 'QR-PRUEBA-1')$q$, false);
select pg_temp.probar('boleto con QR repetido',
  $q$insert into cine.boleto (id_orden, id_asiento, id_funcion, codigo_qr) values (9800900, 9800902, 9800900, 'QR-PRUEBA-1')$q$, true);
select pg_temp.probar('boleto sin línea de orden',
  $q$insert into cine.boleto (id_orden, id_asiento, id_funcion, codigo_qr) values (9800900, 9800903, 9800900, 'QR-PRUEBA-3')$q$, true);
select pg_temp.probar('otra orden pagada para el mismo asiento',
  $q$insert into cine.orden (id_orden, id_funcion, canal, id_usuario_cliente, estado, subtotal, total, pagada_en) overriding system value
     values (9800901, 9800900, 'en_linea', 9800900, 'pagada', 10.00, 10.00, now());
     insert into cine.orden_detalle (id_orden, id_asiento, id_tipo_tarifa, precio_unitario) values (9800901, 9800901, 1, 10.00);
     insert into cine.pago (id_orden, id_metodo_pago, monto, estado, codigo_autorizacion) values (9800901, 3, 10.00, 'aprobado', 'AUT901')$q$, false);
select pg_temp.probar('segundo boleto vigente del mismo asiento y función',
  $q$insert into cine.boleto (id_orden, id_asiento, id_funcion, codigo_qr) values (9800901, 9800901, 9800900, 'QR-PRUEBA-2')$q$, true);
select pg_temp.probar('estado de boleto inválido',
  $q$update cine.boleto set estado = 'usado' where id_boleto = 9800900$q$, true);
select pg_temp.probar('primer ingreso del boleto',
  $q$insert into cine.checkin (id_boleto, id_puerta) values (9800900, 9800900)$q$, false);
select pg_temp.probar('segundo ingreso del mismo boleto',
  $q$insert into cine.checkin (id_boleto, id_puerta) values (9800900, 9800900)$q$, true);
select pg_temp.probar('reembolso válido',
  $q$insert into cine.reembolso (id_boleto, id_pago, id_usuario_autoriza, tipo, monto, motivo)
     values (9800900, 9800900, 9800901, 'forzado', 12.80, 'Prueba')$q$, false);
select pg_temp.probar('segundo reembolso del mismo boleto',
  $q$insert into cine.reembolso (id_boleto, id_pago, id_usuario_autoriza, tipo, monto, motivo)
     values (9800900, 9800900, 9800901, 'politica', 12.80, 'Prueba')$q$, true);
select pg_temp.probar('boleto anulado libera el asiento para un boleto nuevo',
  $q$update cine.boleto set estado = 'anulado' where id_boleto = 9800900;
     insert into cine.boleto (id_orden, id_asiento, id_funcion, codigo_qr) values (9800901, 9800901, 9800900, 'QR-PRUEBA-4')$q$, false);

-- CHECK y NOT NULL ----------------------------------------------------------------------

select pg_temp.probar('tasa de impuesto mayor a 1',
  $q$insert into cine.pais (codigo_iso, nombre, tasa_impuesto) values ('ZY', 'Otro país', 1.5)$q$, true);
select pg_temp.probar('asiento con número 0',
  $q$insert into cine.asiento (id_zona, fila, numero) values (9800901, 'B', 0)$q$, true);
select pg_temp.probar('asiento repetido en la zona',
  $q$insert into cine.asiento (id_zona, fila, numero) values (9800901, 'A', 1), (9800901, 'A', 1)$q$, true);
select pg_temp.probar('película sin sinopsis (RN-02)',
  $q$insert into cine.pelicula (id_clasificacion, titulo, sinopsis, duracion_min, poster_url, fecha_estreno)
     values (1, 'Sin sinopsis', null, 100, 'x', '2026-11-01')$q$, true);
select pg_temp.probar('película con duración 0',
  $q$insert into cine.pelicula (id_clasificacion, titulo, sinopsis, duracion_min, poster_url, fecha_estreno)
     values (1, 'Duración cero', 'x', 0, 'x', '2026-11-01')$q$, true);
select pg_temp.probar('función que termina antes de empezar',
  $q$insert into cine.funcion (id_pelicula, id_sala, inicio, fin, idioma) values (9800900, 9800900, '2026-12-02 20:00-06', '2026-12-02 19:00-06', 'Doblada')$q$, true);
select pg_temp.probar('función con estado inválido',
  $q$insert into cine.funcion (id_pelicula, id_sala, inicio, fin, idioma, estado)
     values (9800900, 9800900, '2026-12-03 20:00-06', '2026-12-03 22:00-06', 'Doblada', 'suspendida')$q$, true);
select pg_temp.probar('función en una sala inexistente (FK)',
  $q$insert into cine.funcion (id_pelicula, id_sala, inicio, fin, idioma) values (9800900, 999999, '2026-12-04 20:00-06', '2026-12-04 22:00-06', 'Doblada')$q$, true);
select pg_temp.probar('tarifa con precio negativo',
  $q$insert into cine.tarifa (id_sede, id_tipo_zona, id_tipo_tarifa, tipo_dia, precio) values (9800900, 1, 2, 'entre_semana', -1)$q$, true);
select pg_temp.probar('tarifa repetida',
  $q$insert into cine.tarifa (id_sede, id_tipo_zona, id_tipo_tarifa, tipo_dia, precio) values (9800900,
     (select id_tipo_zona from cine.tipo_zona where codigo = 'general'),
     (select id_tipo_tarifa from cine.tipo_tarifa where codigo = 'adulto'), 'entre_semana', 12.00)$q$, true);
select pg_temp.probar('promoción 2x1 con porcentaje',
  $q$insert into cine.promocion (codigo, nombre, tipo, porcentaje, vigente_desde, vigente_hasta)
     values ('MAL', 'Mal definida', '2x1', 50, '2026-01-01', '2026-12-31')$q$, true);
select pg_temp.probar('orden con total incoherente (RN-08)',
  $q$insert into cine.orden (id_funcion, canal, id_usuario_cliente, subtotal, cargo_servicio, impuesto, total)
     values (9800900, 'en_linea', 9800900, 20.00, 3.00, 2.60, 30.00)$q$, true);
select pg_temp.probar('orden con descuento mayor al subtotal',
  $q$insert into cine.orden (id_funcion, canal, id_usuario_cliente, subtotal, descuento, total)
     values (9800900, 'en_linea', 9800900, 10.00, 15.00, -5.00)$q$, true);
select pg_temp.probar('orden en línea sin cliente',
  $q$insert into cine.orden (id_funcion, canal) values (9800900, 'en_linea')$q$, true);
select pg_temp.probar('orden pagada sin fecha de pago',
  $q$insert into cine.orden (id_funcion, canal, id_usuario_cliente, estado) values (9800900, 'en_linea', 9800900, 'pagada')$q$, true);
select pg_temp.probar('línea con descuento mayor al precio',
  $q$insert into cine.orden_detalle (id_orden, id_asiento, id_tipo_tarifa, precio_unitario, descuento) values (9800901, 9800903, 1, 10.00, 12.00)$q$, true);
select pg_temp.probar('bloqueo sin fecha de expiración',
  $q$insert into cine.ocupacion_asiento (id_funcion, id_asiento, id_orden, id_usuario, estado) values (9800900, 9800903, 9800901, 9800900, 'bloqueado')$q$, true);
select pg_temp.probar('venta sin orden',
  $q$insert into cine.ocupacion_asiento (id_funcion, id_asiento, id_usuario, estado) values (9800900, 9800903, 9800900, 'vendido')$q$, true);
select pg_temp.probar('reserva administrativa sin orden',
  $q$insert into cine.ocupacion_asiento (id_funcion, id_asiento, id_usuario, estado) values (9800900, 9800903, 9800901, 'reservado')$q$, false);
select pg_temp.probar('correo sin arroba',
  $q$insert into cine.usuario (id_rol, email, contrasena_hash, nombre, apellidos) values (1, 'correo-invalido', 'h', 'X', 'Y')$q$, true);
select pg_temp.probar('evento de bitácora inválido',
  $q$insert into bitacora.transaccion_log (id_orden, evento) values (9800900, 'pago_dudoso')$q$, true);
select pg_temp.probar('evento de bitácora válido en su partición mensual',
  $q$insert into bitacora.transaccion_log (id_orden, evento, monto, ocurrido_en) values (9800900, 'pago_aprobado', 25.60, '2026-10-15')$q$, false);

-- Permisos de los roles (RN-17, RN-20) ---------------------------------------------------

-- Ningún rol de la aplicación puede modificar ni borrar las bitácoras
insert into resultado (prueba, esperado, obtenido)
select format('%s sin %s en bitacora.%s', r, p, t), 'sin permiso',
       case when has_table_privilege(r, 'bitacora.' || t, p) then 'con permiso' else 'sin permiso' end
from unnest(array['rol_cliente', 'rol_taquillero', 'rol_operador_puerta', 'rol_contador', 'rol_administrador']) as r,
     unnest(array['UPDATE', 'DELETE']) as p,
     unnest(array['transaccion_log', 'asiento_auditoria_log', 'acceso_puerta_log', 'admin_operacion_audit']) as t;

-- Taquillero y cliente no configuran salas ni precios; el administrador sí
insert into resultado (prueba, esperado, obtenido)
select format('%s %s %s en %s', r, case when e then 'con' else 'sin' end, p, t),
       case when e then 'con permiso' else 'sin permiso' end,
       case when has_table_privilege(r, t, p) then 'con permiso' else 'sin permiso' end
from (values
    ('rol_cliente',         'cine.tarifa',  'UPDATE', false),
    ('rol_cliente',         'cine.sala',    'INSERT', false),
    ('rol_taquillero',      'cine.tarifa',  'UPDATE', false),
    ('rol_taquillero',      'cine.sala',    'UPDATE', false),
    ('rol_taquillero',      'cine.funcion', 'INSERT', false),
    ('rol_operador_puerta', 'cine.pago',    'SELECT', false),
    ('rol_cliente',         'cine.usuario', 'SELECT', false),
    ('rol_cliente',         'cine.funcion', 'SELECT', true),
    ('rol_contador',        'cine.pago',    'SELECT', true),
    ('rol_contador',        'cine.tarifa',  'UPDATE', false),
    ('rol_administrador',   'cine.tarifa',  'UPDATE', true),
    ('rol_administrador',   'cine.sala',    'INSERT', true),
    ('rol_administrador',   'bitacora.admin_operacion_audit', 'SELECT', true)
) as caso (r, t, p, e);

-- Intento real: el administrador tiene lectura de las bitácoras, pero no puede modificarlas
set local role rol_administrador;
do $$
begin
    update bitacora.transaccion_log set monto = 0;
    raise exception 'FALLO: rol_administrador pudo modificar transaccion_log';
exception when insufficient_privilege then
    raise warning 'OK: rol_administrador no puede modificar transaccion_log (%)', sqlerrm;
end $$;
reset role;

-- Resumen ---------------------------------------------------------------------------------

select n, prueba, esperado, obtenido,
       case when esperado = obtenido then 'OK' else 'FALLO' end as resultado,
       left(coalesce(detalle, ''), 70) as detalle
from resultado order by n;

select count(*) as pruebas,
       count(*) filter (where esperado = obtenido) as correctas,
       count(*) filter (where esperado <> obtenido) as fallidas
from resultado;

do $$
begin
    if exists (select 1 from resultado where esperado <> obtenido) then
        raise exception 'Hay pruebas fallidas';
    end if;
end $$;

rollback;
