-- 02_reglas.sql
-- Pruebas de las reglas de negocio RN-01 a RN-20 sobre las funciones, triggers y vistas.
-- Cada regla tiene al menos una prueba positiva (T-RNxx-P) y una negativa (T-RNxx-N).
-- Los datos de prueba usan identificadores 99000xx, fechas relativas a now() y una
-- transacción que se revierte al final.
--
--   psql -U imax_owner -d imax -v ON_ERROR_STOP=1 -f db/tests/02_reglas.sql

\set ON_ERROR_STOP on
\pset footer off
set client_min_messages = warning;

begin;

create temp table resultado (n serial, prueba text, esperado text, obtenido text, detalle text);

-- La sentencia debe ser rechazada (o aceptada) por la base de datos
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

-- La condición debe cumplirse
create function pg_temp.verificar(p_prueba text, p_condicion boolean, p_detalle text default null) returns void
language sql as $$
    insert into resultado (prueba, esperado, obtenido, detalle)
    values (p_prueba, 'cumple', case when coalesce(p_condicion, false) then 'cumple' else 'no cumple' end, p_detalle)
$$;

-- Datos de prueba ---------------------------------------------------------------------------

-- Las promociones existentes se desactivan para que no alteren los totales esperados
update cine.promocion set es_activa = false;

insert into cine.pais (id_pais, codigo_iso, nombre, tasa_impuesto) overriding system value values (9901, 'ZZ', 'País de prueba', 0.10);
insert into cine.ciudad (id_ciudad, id_pais, nombre) overriding system value values (9900001, 9901, 'Ciudad de prueba');
insert into cine.sede (id_sede, id_ciudad, nombre, direccion) overriding system value
    values (9900001, 9900001, 'IMAX Prueba', 'Calle de prueba 1');
insert into cine.sala (id_sala, id_sede, nombre, formato) overriding system value
    values (9900001, 9900001, 'Sala A', 'IMAX con láser'), (9900002, 9900001, 'Sala B', 'IMAX digital'),
           (9900003, 9900001, 'Sala C', 'IMAX digital');
insert into cine.zona (id_zona, id_sala, id_tipo_zona, nombre) overriding system value
    values (9900001, 9900001, (select id_tipo_zona from cine.tipo_zona where codigo = 'general'), 'Platea A'),
           (9900002, 9900002, (select id_tipo_zona from cine.tipo_zona where codigo = 'general'), 'Platea B'),
           (9900003, 9900003, (select id_tipo_zona from cine.tipo_zona where codigo = 'general'), 'Platea C');
insert into cine.asiento (id_asiento, id_zona, fila, numero) overriding system value
select 9900000 + n, 9900001, 'A', n from generate_series(1, 8) as n
union all
select 9900010 + n, 9900002, 'A', n from generate_series(1, 4) as n;
insert into cine.puerta (id_puerta, id_sala, codigo, tipo) overriding system value
    values (9900001, 9900001, 'P-PRUEBA-A', 'totem'), (9900002, 9900002, 'P-PRUEBA-B', 'manual');
insert into cine.tarifa (id_sede, id_tipo_zona, id_tipo_tarifa, tipo_dia, precio)
select 9900001, (select id_tipo_zona from cine.tipo_zona where codigo = 'general'), tt.id_tipo_tarifa, d,
       case tt.codigo when 'adulto' then 10 when 'nino' then 7 when 'estudiante' then 8 else 6 end
from cine.tipo_tarifa tt
cross join unnest(array['entre_semana', 'fin_de_semana']) as d
where not tt.es_cortesia;
insert into cine.pelicula (id_pelicula, id_clasificacion, titulo, sinopsis, duracion_min, poster_url, fecha_estreno)
overriding system value values (9900001, (select id_clasificacion from cine.clasificacion where codigo = 'TP'),
    'Película de prueba', 'Sinopsis de prueba', 100, 'prueba.jpg', current_date);

-- F1: en 3 días (sala A). F2: en 10 minutos (sala A, puerta abierta). F5: en 5 horas (sala B).
-- F6: en 1 hora (sala B, dentro del límite de reembolso). F7: ya pasó. F8: cancelada.
insert into cine.funcion (id_funcion, id_pelicula, id_sala, inicio, fin, idioma, estado) overriding system value values
    (9900001, 9900001, 9900001, now() + interval '3 days',     now() + interval '3 days 2 hours', 'Subtitulada', 'programada'),
    (9900002, 9900001, 9900001, now() + interval '10 minutes', now() + interval '2 hours 10 minutes', 'Subtitulada', 'programada'),
    (9900005, 9900001, 9900002, now() + interval '5 hours',    now() + interval '7 hours', 'Doblada', 'programada'),
    (9900006, 9900001, 9900002, now() + interval '1 hour',     now() + interval '3 hours', 'Doblada', 'programada'),
    (9900007, 9900001, 9900002, now() - interval '1 day',      now() - interval '22 hours', 'Doblada', 'programada'),
    (9900008, 9900001, 9900002, now() + interval '2 days',     now() + interval '2 days 2 hours', 'Doblada', 'cancelada');

insert into cine.usuario (id_usuario, id_rol, email, contrasena_hash, nombre, apellidos) overriding system value values
    (9900001, (select id_rol from cine.rol where codigo = 'cliente'),         'prueba.cliente@test.local',  'h', 'Ana', 'Prueba'),
    (9900002, (select id_rol from cine.rol where codigo = 'cliente'),         'prueba.cliente2@test.local', 'h', 'Bea', 'Prueba'),
    (9900003, (select id_rol from cine.rol where codigo = 'administrador'),   'prueba.admin@test.local',    'h', 'Carlos', 'Prueba'),
    (9900004, (select id_rol from cine.rol where codigo = 'operador_puerta'), 'prueba.puerta@test.local',   'h', 'Dora', 'Prueba');

-- RN-01 y RN-02: cartelera ------------------------------------------------------------------

select pg_temp.verificar('T-RN01-P función programada y futura aparece en la cartelera',
    exists (select 1 from cine.v_cartelera_activa where id_funcion = 9900001));
select pg_temp.verificar('T-RN01-N función pasada no aparece en la cartelera',
    not exists (select 1 from cine.v_cartelera_activa where id_funcion = 9900007));
select pg_temp.verificar('T-RN01-N función cancelada no aparece en la cartelera',
    not exists (select 1 from cine.v_cartelera_activa where id_funcion = 9900008));
select pg_temp.verificar('T-RN02-P la cartelera trae título, sinopsis, clasificación, horario y ubicación',
    exists (select 1 from cine.v_cartelera_activa
            where id_funcion = 9900001 and titulo is not null and sinopsis is not null and clasificacion is not null
              and inicio is not null and sala is not null and sede is not null and direccion is not null and ciudad is not null));
select pg_temp.probar('T-RN02-N película sin sinopsis es rechazada',
    $q$insert into cine.pelicula (id_clasificacion, titulo, sinopsis, duracion_min, poster_url, fecha_estreno)
       values (1, 'Sin sinopsis', null, 90, 'x.jpg', current_date)$q$, true);

-- No traslape de funciones en la misma sala
select pg_temp.probar('Función que se traslapa con otra de la misma sala es rechazada',
    $q$insert into cine.funcion (id_pelicula, id_sala, inicio, fin, idioma)
       values (9900001, 9900001, now() + interval '3 days 1 hour', now() + interval '3 days 3 hours', 'Doblada')$q$, true);
select pg_temp.probar('Función después de la anterior en la misma sala es aceptada',
    $q$insert into cine.funcion (id_pelicula, id_sala, inicio, fin, idioma)
       values (9900001, 9900001, now() + interval '3 days 3 hours', now() + interval '3 days 5 hours', 'Doblada')$q$, false);

-- RN-04: máximo de asientos por transacción -------------------------------------------------

select cine.bloquear_asientos(9900001, 9900001, array[9900001, 9900002, 9900003, 9900004, 9900005, 9900006]) as orden_seis \gset
select pg_temp.verificar('T-RN04-P se pueden bloquear 6 asientos', :orden_seis is not null);
select cine.liberar_asientos(:orden_seis);
select pg_temp.probar('T-RN04-N bloquear 7 asientos es rechazado',
    $q$select cine.bloquear_asientos(9900001, 9900001, array[9900001, 9900002, 9900003, 9900004, 9900005, 9900006, 9900007])$q$, true);

-- RN-05 y RN-03: bloqueo temporal y mapa en tiempo real -------------------------------------

select cine.bloquear_asientos(9900001, 9900001, array[9900001, 9900002]) as orden_1 \gset
select pg_temp.verificar('T-RN05-P el bloqueo vence 2 minutos después',
    (select bool_and(expira_en = now() + interval '2 minutes') from cine.ocupacion_asiento where id_orden = :orden_1));
select coalesce(cine.bloquear_asientos(9900001, 9900002, array[9900002, 9900003])::text, 'nulo') as orden_colision \gset
select pg_temp.verificar('T-RN05-N otro usuario no puede bloquear un asiento ya bloqueado', :'orden_colision' = 'nulo');
select pg_temp.verificar('T-RN05-N la colisión queda en la bitácora de asientos',
    exists (select 1 from bitacora.asiento_auditoria_log
            where id_funcion = 9900001 and id_asiento = 9900002 and id_usuario = 9900002 and evento = 'colision'));
select pg_temp.verificar('T-RN03-P el mapa muestra el asiento bloqueado',
    (select estado from cine.v_mapa_asientos where id_funcion = 9900001 and id_asiento = 9900002) = 'bloqueado');

-- El bloqueo vence: el asiento vuelve a estar disponible y otro usuario lo puede tomar
update cine.ocupacion_asiento set expira_en = now() - interval '1 second' where id_orden = :orden_1;
select pg_temp.verificar('T-RN03-N un bloqueo vencido se muestra disponible antes del barrido',
    (select estado from cine.v_mapa_asientos where id_funcion = 9900001 and id_asiento = 9900002) = 'disponible');
select cine.bloquear_asientos(9900001, 9900002, array[9900002, 9900003]) as orden_2 \gset
select pg_temp.verificar('T-RN05-P al vencer el bloqueo, otro usuario puede tomar el asiento', :orden_2 is not null);
select pg_temp.verificar('T-RN05-P la orden vencida queda expirada',
    (select estado from cine.orden where id_orden = :orden_1) = 'expirada');
select pg_temp.verificar('T-RN05-P la liberación por vencimiento queda en la bitácora',
    exists (select 1 from bitacora.asiento_auditoria_log where id_orden = :orden_1 and evento = 'liberacion_expiracion'));
update cine.ocupacion_asiento set expira_en = now() - interval '1 second' where id_orden = :orden_2;
select pg_temp.verificar('T-RN05-P el barrido periódico libera los bloqueos vencidos', cine.liberar_bloqueos_expirados() >= 2);

-- RN-07 y RN-08: promociones y total -------------------------------------------------------

insert into cine.promocion (codigo, nombre, tipo, id_tipo_tarifa, dia_semana, vigente_desde, vigente_hasta)
values ('PRUEBA2X1', '2x1 de prueba', '2x1', (select id_tipo_tarifa from cine.tipo_tarifa where codigo = 'adulto'),
        extract(isodow from now() + interval '3 days')::int, current_date, current_date + 30);

select cine.bloquear_asientos(9900001, 9900001, array[9900004, 9900005]) as orden_promo \gset
select pg_temp.verificar('T-RN07-P el 2x1 descuenta una de dos entradas de adulto',
    (select descuento from cine.orden where id_orden = :orden_promo) = 10.00);
select pg_temp.verificar('T-RN08-P total = tarifas - descuentos + cargo por servicio + impuesto',
    (select subtotal = 20 and descuento = 10 and cargo_servicio = 3.00 and impuesto = 1.30 and total = 14.30
       from cine.orden where id_orden = :orden_promo));
select pg_temp.probar('T-RN08-N un total incoherente es rechazado',
    format('update cine.orden set total = total + 1 where id_orden = %s', :orden_promo), true);
select cine.liberar_asientos(:orden_promo);
select cine.bloquear_asientos(9900001, 9900001, array[9900006]) as orden_una \gset
select pg_temp.verificar('T-RN07-N con una sola entrada el 2x1 no aplica',
    (select descuento from cine.orden where id_orden = :orden_una) = 0);
select cine.liberar_asientos(:orden_una);
update cine.promocion set es_activa = false where codigo = 'PRUEBA2X1';

-- RN-10, RN-09 y RN-11: pago rechazado y aprobado ----------------------------------------------

select cine.bloquear_asientos(9900001, 9900001, array[9900007]) as orden_rechazo \gset
select cine.procesar_pago(:orden_rechazo, 'tarjeta_debito', '0002', 'visa') as respuesta_rechazo \gset
select pg_temp.verificar('T-RN10-P el pago rechazado cancela la orden', :'respuesta_rechazo' like 'rechazado%'
       and (select estado from cine.orden where id_orden = :orden_rechazo) = 'rechazada');
select pg_temp.verificar('T-RN10-P el pago rechazado libera el asiento de inmediato',
    (select estado from cine.v_mapa_asientos where id_funcion = 9900001 and id_asiento = 9900007) = 'disponible'
    and exists (select 1 from bitacora.asiento_auditoria_log where id_orden = :orden_rechazo and evento = 'liberacion_rechazo'));
select pg_temp.verificar('T-RN10-P el intento rechazado queda registrado sin cobro',
    exists (select 1 from cine.pago where id_orden = :orden_rechazo and estado = 'rechazado' and codigo_autorizacion is null)
    and exists (select 1 from bitacora.transaccion_log where id_orden = :orden_rechazo and evento = 'pago_rechazado'));
select pg_temp.verificar('T-RN11-N sin pago aprobado no se emite ningún boleto',
    not exists (select 1 from cine.boleto where id_orden = :orden_rechazo));

select cine.bloquear_asientos(9900001, 9900001, array[9900008]) as orden_pendiente \gset
select pg_temp.probar('T-RN11-N un boleto de una orden pendiente es rechazado',
    format($q$insert into cine.boleto (id_orden, id_asiento, id_funcion, codigo_qr) values (%s, 9900008, 9900001, 'QR-PRUEBA')$q$,
           :orden_pendiente), true);

-- Compra aprobada en F2 (en 10 minutos): un adulto y un niño
select cine.bloquear_asientos(9900002, 9900001, array[9900001, 9900002]) as orden_ok \gset
select cine.elegir_tarifa(:orden_ok, 9900002, 'nino');
select cine.procesar_pago(:orden_ok, 'tarjeta_credito', '4242', 'visa') as respuesta_ok \gset
select pg_temp.verificar('T-RN10-N con el pago aprobado los asientos quedan vendidos', :'respuesta_ok' = 'aprobado'
       and (select count(*) from cine.ocupacion_asiento where id_orden = :orden_ok and estado = 'vendido') = 2);
select pg_temp.verificar('T-RN11-P el pago aprobado emite un boleto con QR por asiento',
    (select count(*) from cine.boleto where id_orden = :orden_ok and codigo_qr is not null) = 2);
select pg_temp.verificar('T-RN09-P del pago solo se guardan el token, los últimos 4 dígitos y la marca',
    exists (select 1 from cine.pago where id_orden = :orden_ok and estado = 'aprobado'
            and token_pasarela is not null and ultimos4 = '4242' and marca = 'visa'));
select pg_temp.verificar('T-RN09-N no existe ninguna columna para el número de tarjeta ni el código de verificación',
    not exists (select 1 from information_schema.columns
                where table_schema in ('cine', 'bitacora')
                  and (column_name ilike '%pan%' or column_name ilike '%cvv%' or column_name ilike '%cvc%'
                       or column_name ilike '%numero_tarjeta%' or column_name ilike '%card%')));
select pg_temp.probar('T-RN09-N un número de tarjeta en lugar de los últimos 4 dígitos es rechazado',
    format($q$insert into cine.pago (id_orden, id_metodo_pago, monto, estado, motivo_rechazo, ultimos4, marca)
              values (%s, 1, 10, 'rechazado', 'x', '4242424242424242', 'visa')$q$, :orden_ok), true);

-- RN-12 y RN-13: identificador único y entradas del cliente ------------------------------------

select pg_temp.verificar('T-RN12-P cada boleto tiene un QR distinto de 32 caracteres',
    (select count(distinct codigo_qr) = 2 and min(length(codigo_qr)) = 32 from cine.boleto where id_orden = :orden_ok));
select coalesce(cine.bloquear_asientos(9900002, 9900002, array[9900001])::text, 'nulo') as orden_revendida \gset
select pg_temp.verificar('T-RN12-N un asiento vendido no se puede volver a bloquear ni vender', :'orden_revendida' = 'nulo');
select pg_temp.verificar('T-RN13-P el cliente ve sus entradas en su perfil',
    (select count(*) from cine.v_mis_entradas where id_usuario = 9900001 and id_orden = :orden_ok) = 2);
select pg_temp.verificar('T-RN13-N otro cliente no ve esas entradas',
    not exists (select 1 from cine.v_mis_entradas where id_usuario = 9900002 and id_orden = :orden_ok));

-- RN-14, RN-06, RN-15 y RN-16: control de acceso en puerta ---------------------------------------

select codigo_qr as qr_adulto from cine.boleto where id_orden = :orden_ok and id_asiento = 9900001 \gset
select codigo_qr as qr_nino from cine.boleto where id_orden = :orden_ok and id_asiento = 9900002 \gset

select resultado as r1, mensaje as m1 from cine.validar_entrada(:'qr_adulto', 9900001, 9900004) \gset
select pg_temp.verificar('T-RN14-P el primer escaneo permite el ingreso', :'r1' = 'exitoso', :'m1');
select pg_temp.verificar('T-RN16-P dentro de la ventana de ingreso (10 minutos antes) se acepta', :'r1' = 'exitoso');
select pg_temp.verificar('T-RN06-N una tarifa de adulto no pide documento', :'m1' = 'Acceso permitido');
select resultado as r2, mensaje as m2 from cine.validar_entrada(:'qr_adulto', 9900001, 9900004) \gset
select pg_temp.verificar('T-RN14-N el segundo escaneo responde "Entrada ya utilizada"',
    :'r2' = 'duplicado' and :'m2' = 'Entrada ya utilizada', :'m2');
select pg_temp.verificar('T-RN14-N el intento duplicado queda en la bitácora de puerta',
    exists (select 1 from bitacora.acceso_puerta_log where codigo_qr_leido = :'qr_adulto' and resultado = 'duplicado'));

select resultado as r3, mensaje as m3 from cine.validar_entrada(:'qr_nino', 9900002, 9900004) \gset
select pg_temp.verificar('T-RN15-N una entrada de otra sala o función es rechazada', :'r3' = 'otra_funcion', :'m3');
select resultado as r4, mensaje as m4 from cine.validar_entrada(:'qr_nino', 9900001, 9900004) \gset
select pg_temp.verificar('T-RN15-P la misma entrada en su sala y función es aceptada', :'r4' = 'exitoso', :'m4');
select pg_temp.verificar('T-RN06-P una tarifa de niño pide validar el documento', :'m4' like '%Validar documento%', :'m4');
select cine.registrar_incidencia(:'qr_nino', 9900001, 9900004, 'No presentó documento de la tarifa especial');
select pg_temp.verificar('T-RN06-P la incidencia de documento queda registrada',
    exists (select 1 from bitacora.acceso_puerta_log where codigo_qr_leido = :'qr_nino' and resultado = 'incidencia_documento'));

select cine.bloquear_asientos(9900005, 9900001, array[9900011]) as orden_f5 \gset
select cine.procesar_pago(:orden_f5, 'paypal');
select codigo_qr as qr_f5 from cine.boleto where id_orden = :orden_f5 \gset
select resultado as r5, mensaje as m5 from cine.validar_entrada(:'qr_f5', 9900002, 9900004) \gset
select pg_temp.verificar('T-RN16-N una entrada fuera de la ventana de ingreso es rechazada', :'r5' = 'fuera_de_horario', :'m5');
select resultado as r6 from cine.validar_entrada('NO-EXISTE', 9900001, 9900004) \gset
select pg_temp.verificar('Un código que no existe es rechazado', :'r6' = 'inexistente');

-- RN-17: permisos por rol --------------------------------------------------------------------

select pg_temp.verificar('T-RN17-P el operador de puerta puede validar entradas',
    has_function_privilege('rol_operador_puerta', 'cine.validar_entrada(text, integer, bigint)', 'EXECUTE'));
select pg_temp.verificar('T-RN17-P el cliente y el taquillero pueden comprar',
    has_function_privilege('rol_cliente', 'cine.bloquear_asientos(bigint, bigint, integer[], text)', 'EXECUTE')
    and has_function_privilege('rol_taquillero', 'cine.procesar_pago(bigint, text, text, text)', 'EXECUTE'));
select pg_temp.verificar('T-RN17-N el cliente no puede anular boletos ni validar entradas',
    not has_function_privilege('rol_cliente', 'cine.anular_boleto(bigint, text, text)', 'EXECUTE')
    and not has_function_privilege('rol_cliente', 'cine.validar_entrada(text, integer, bigint)', 'EXECUTE'));
select pg_temp.verificar('T-RN17-N el taquillero no puede otorgar cortesías, cambiar asientos ni modificar precios',
    not has_function_privilege('rol_taquillero', 'cine.otorgar_cortesia(bigint, integer, bigint, text)', 'EXECUTE')
    and not has_function_privilege('rol_taquillero', 'cine.cambiar_asiento(bigint, integer, text)', 'EXECUTE')
    and not has_table_privilege('rol_taquillero', 'cine.tarifa', 'UPDATE'));
select pg_temp.verificar('T-RN17-N el operador de puerta no puede vender',
    not has_function_privilege('rol_operador_puerta', 'cine.procesar_pago(bigint, text, text, text)', 'EXECUTE'));

-- RN-18: salas con ventas activas -------------------------------------------------------------

select pg_temp.probar('T-RN18-N no se puede borrar un asiento de una sala con ventas',
    $q$delete from cine.asiento where id_asiento = 9900008$q$, true);
select pg_temp.probar('T-RN18-N no se pueden agregar asientos a una sala con ventas',
    $q$insert into cine.asiento (id_zona, fila, numero) values (9900001, 'B', 1)$q$, true);
select pg_temp.probar('T-RN18-N no se puede desactivar una sala con ventas',
    $q$update cine.sala set es_activa = false where id_sala = 9900001$q$, true);
select pg_temp.probar('T-RN18-P una sala sin ventas sí se puede modificar',
    $q$insert into cine.asiento (id_zona, fila, numero) values (9900003, 'A', 1);
       delete from cine.asiento where id_zona = 9900003$q$, false);

-- RN-19 y RN-20: anulaciones, reembolsos y auditoría ---------------------------------------------

select pg_temp.probar('T-RN20-N una operación manual sin responsable es rechazada',
    $q$select cine.otorgar_cortesia(9900001, 9900003, 9900001, 'Sin contexto')$q$, true);

select cine.establecer_contexto(9900003, '192.168.1.10');

select cine.bloquear_asientos(9900001, 9900001, array[9900006]) as orden_f1 \gset
select cine.procesar_pago(:orden_f1, 'tarjeta_credito', '4242', 'mastercard');
select id_boleto as boleto_f1 from cine.boleto where id_orden = :orden_f1 \gset
select cine.anular_boleto(:boleto_f1, 'El cliente no puede asistir', 'politica') as monto_f1 \gset
select pg_temp.verificar('T-RN19-P reembolso por política hasta 2 horas antes de la función',
    :monto_f1 = 11.00 and exists (select 1 from cine.reembolso where id_boleto = :boleto_f1 and tipo = 'politica' and monto = 11.00));
select pg_temp.verificar('T-RN19-P el reembolso libera el asiento para la venta',
    (select estado from cine.boleto where id_boleto = :boleto_f1) = 'anulado'
    and (select estado from cine.v_mapa_asientos where id_funcion = 9900001 and id_asiento = 9900006) = 'disponible');

select cine.bloquear_asientos(9900006, 9900001, array[9900012]) as orden_f6 \gset
select cine.procesar_pago(:orden_f6, 'tarjeta_credito', '4242', 'visa');
select id_boleto as boleto_f6 from cine.boleto where id_orden = :orden_f6 \gset
select pg_temp.probar('T-RN19-N reembolso por política a menos de 2 horas de la función es rechazado',
    format($q$select cine.anular_boleto(%s, 'Tarde', 'politica')$q$, :boleto_f6), true);
select cine.anular_boleto(:boleto_f6, 'Autorizado por gerencia', 'forzado');
select pg_temp.verificar('T-RN19-P el administrador puede forzar el reembolso',
    exists (select 1 from cine.reembolso where id_boleto = :boleto_f6 and tipo = 'forzado'));
select pg_temp.verificar('T-RN20-P el reembolso forzado queda auditado con fecha, IP, rol y usuario',
    exists (select 1 from bitacora.admin_operacion_audit
            where operacion = 'reembolso_forzado' and id_entidad = :'boleto_f6' and id_usuario = 9900003
              and id_rol = (select id_rol from cine.rol where codigo = 'administrador')
              and ip = '192.168.1.10' and ocurrido_en = now()));

select cine.otorgar_cortesia(9900001, 9900003, 9900001, 'Invitación de prensa') as boleto_cortesia \gset
select pg_temp.verificar('T-RN20-P la cortesía emite un boleto sin pago y queda auditada',
    (select o.total from cine.boleto b join cine.orden o on o.id_orden = b.id_orden where b.id_boleto = :boleto_cortesia) = 0
    and exists (select 1 from bitacora.admin_operacion_audit where operacion = 'cortesia' and id_entidad = :'boleto_cortesia'));
select cine.cambiar_asiento(:boleto_cortesia, 9900004, 'Cambio solicitado por el invitado');
select pg_temp.verificar('T-RN20-P el cambio manual de asiento mueve el boleto y queda auditado',
    (select id_asiento from cine.boleto where id_boleto = :boleto_cortesia) = 9900004
    and (select estado from cine.v_mapa_asientos where id_funcion = 9900001 and id_asiento = 9900003) = 'disponible'
    and exists (select 1 from bitacora.admin_operacion_audit where operacion = 'cambio_asiento' and id_entidad = :'boleto_cortesia'
                and valores_anteriores ->> 'id_asiento' = '9900003' and valores_nuevos ->> 'id_asiento' = '9900004'));

update cine.tarifa set precio = 12.00
where id_sede = 9900001 and tipo_dia = 'entre_semana'
  and id_tipo_tarifa = (select id_tipo_tarifa from cine.tipo_tarifa where codigo = 'adulto');
select pg_temp.verificar('T-RN20-P el cambio de precio queda auditado con el valor anterior y el nuevo',
    exists (select 1 from bitacora.admin_operacion_audit
            where operacion = 'cambio_tarifa' and id_usuario = 9900003
              and (valores_anteriores ->> 'precio')::numeric = 10 and (valores_nuevos ->> 'precio')::numeric = 12));
select pg_temp.probar('T-RN20-N la bitácora de auditoría no se puede modificar',
    $q$update bitacora.admin_operacion_audit set motivo = 'alterado' where id_usuario = 9900003$q$, true);
select pg_temp.probar('T-RN20-N la bitácora de auditoría no se puede borrar',
    $q$delete from bitacora.admin_operacion_audit where id_usuario = 9900003$q$, true);

-- Resumen -------------------------------------------------------------------------------------

select n, prueba, esperado, obtenido,
       case when esperado = obtenido then 'OK' else 'FALLO' end as resultado,
       left(coalesce(detalle, ''), 60) as detalle
from resultado order by n;

select count(*) as pruebas,
       count(*) filter (where esperado = obtenido) as correctas,
       count(*) filter (where esperado <> obtenido) as fallidas
from resultado;

select string_agg(rn, ', ' order by rn) as rn_sin_positiva_y_negativa
from (select 'RN-' || lpad(i::text, 2, '0') as rn from generate_series(1, 20) as i) as r
where not exists (select 1 from resultado where prueba like 'T-' || replace(rn, '-', '') || '-P%')
   or not exists (select 1 from resultado where prueba like 'T-' || replace(rn, '-', '') || '-N%');

do $$
begin
    if exists (select 1 from resultado where esperado <> obtenido) then
        raise exception 'Hay pruebas fallidas';
    end if;
end $$;

rollback;
