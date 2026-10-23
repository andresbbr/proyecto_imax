-- 05_administracion.sql
-- Operaciones manuales del administrador: anulaciones y reembolsos, cancelación de una
-- función, cortesías, cambios de asiento y reservas. Todas exigen haber llamado antes a
-- establecer_contexto y quedan en bitacora.admin_operacion_audit (RN-20).

-- Responsable de la operación en curso
create or replace function cine.usuario_en_contexto() returns bigint
language plpgsql stable as $$
declare
    v_id bigint := nullif(current_setting('imax.id_usuario', true), '')::bigint;
begin
    if v_id is null then
        raise exception 'Operación sin responsable: falta llamar a establecer_contexto(id_usuario, ip)';
    end if;
    return v_id;
end $$;

-- RN-19: anula un boleto, devuelve su importe y libera el asiento.
--   politica             solo hasta 2 horas antes del inicio de la función
--   forzado              sin límite de tiempo (decisión del administrador)
--   cancelacion_funcion  la función se canceló
create or replace function cine.anular_boleto(p_id_boleto bigint, p_motivo text, p_tipo text default 'politica')
returns numeric
language plpgsql security definer set search_path = cine, pg_temp as $$
declare
    v_admin   bigint := usuario_en_contexto();
    v_boleto  boleto%rowtype;
    v_inicio  timestamptz;
    v_limite  interval := make_interval(hours => parametro('horas_limite_reembolso')::int);
    v_monto   numeric(12,2);
    v_id_pago bigint;
begin
    if p_tipo not in ('politica', 'forzado', 'cancelacion_funcion') then
        raise exception 'Tipo de anulación desconocido: %', p_tipo;
    end if;
    select * into v_boleto from boleto where id_boleto = p_id_boleto for update;
    if not found or v_boleto.estado <> 'vigente' then
        raise exception 'El boleto no existe o ya está anulado';
    end if;
    if exists (select 1 from checkin where id_boleto = p_id_boleto) then
        raise exception 'La entrada ya fue utilizada';
    end if;

    select inicio into v_inicio from funcion where id_funcion = v_boleto.id_funcion;
    if p_tipo = 'politica' and now() > v_inicio - v_limite then
        raise exception 'Fuera de la política de reembolso: solo hasta % horas antes de la función (RN-19)',
                        parametro('horas_limite_reembolso');
    end if;

    -- Importe de la línea con su parte del impuesto
    select round((d.precio_unitario - d.descuento) * (1 + pa.tasa_impuesto), 2) into v_monto
    from orden_detalle d
    join funcion f on f.id_funcion = v_boleto.id_funcion
    join sala s on s.id_sala = f.id_sala
    join sede se on se.id_sede = s.id_sede
    join ciudad ci on ci.id_ciudad = se.id_ciudad
    join pais pa on pa.id_pais = ci.id_pais
    where d.id_orden = v_boleto.id_orden and d.id_asiento = v_boleto.id_asiento;

    select id_pago into v_id_pago from pago where id_orden = v_boleto.id_orden and estado = 'aprobado';

    update boleto set estado = 'anulado' where id_boleto = p_id_boleto;
    delete from ocupacion_asiento where id_funcion = v_boleto.id_funcion and id_asiento = v_boleto.id_asiento;
    insert into bitacora.asiento_auditoria_log (id_funcion, id_asiento, id_orden, id_usuario, evento)
    values (v_boleto.id_funcion, v_boleto.id_asiento, v_boleto.id_orden, v_admin, 'liberacion_reembolso');

    -- Las cortesías no tienen pago: se anulan sin reembolso
    if v_monto > 0 and v_id_pago is not null then
        insert into reembolso (id_boleto, id_pago, id_usuario_autoriza, tipo, monto, motivo)
        values (p_id_boleto, v_id_pago, v_admin, p_tipo, v_monto, p_motivo);
        insert into bitacora.transaccion_log (id_orden, id_pago, id_boleto, evento, monto, detalle)
        values (v_boleto.id_orden, v_id_pago, p_id_boleto, 'reembolso', v_monto, jsonb_build_object('tipo', p_tipo));
    else
        v_monto := 0;
    end if;

    perform registrar_operacion_admin(
        case p_tipo when 'forzado' then 'reembolso_forzado' when 'cancelacion_funcion' then 'reembolso_cancelacion' else 'reembolso' end,
        'boleto', p_id_boleto::text, to_jsonb(v_boleto),
        jsonb_build_object('estado', 'anulado', 'monto_reembolsado', v_monto), p_motivo);
    return v_monto;
end $$;

-- Cancela una función: libera los bloqueos, cancela las órdenes pendientes y reembolsa
-- todos los boletos vigentes. Devuelve la cantidad de boletos reembolsados.
create or replace function cine.cancelar_funcion(p_id_funcion bigint, p_motivo text) returns integer
language plpgsql security definer set search_path = cine, pg_temp as $$
declare
    v_boleto    bigint;
    v_anulados  integer := 0;
begin
    perform usuario_en_contexto();
    update funcion set estado = 'cancelada' where id_funcion = p_id_funcion and estado = 'programada';
    if not found then
        raise exception 'La función no existe o ya está cancelada';
    end if;

    delete from ocupacion_asiento where id_funcion = p_id_funcion and estado in ('bloqueado', 'reservado');
    update orden set estado = 'cancelada' where id_funcion = p_id_funcion and estado = 'pendiente';

    for v_boleto in
        select b.id_boleto from boleto b
        where b.id_funcion = p_id_funcion and b.estado = 'vigente'
          and not exists (select 1 from checkin c where c.id_boleto = b.id_boleto)
    loop
        perform anular_boleto(v_boleto, p_motivo, 'cancelacion_funcion');
        v_anulados := v_anulados + 1;
    end loop;
    return v_anulados;
end $$;

-- Cortesía: entrada gratuita otorgada por el administrador a un cliente (RN-20)
create or replace function cine.otorgar_cortesia(
    p_id_funcion bigint, p_id_asiento integer, p_id_usuario_cliente bigint, p_motivo text
) returns bigint
language plpgsql security definer set search_path = cine, pg_temp as $$
declare
    v_id_orden  bigint;
    v_id_boleto bigint;
begin
    perform usuario_en_contexto();
    v_id_orden := bloquear_asientos(p_id_funcion, p_id_usuario_cliente, array[p_id_asiento], 'en_linea');
    if v_id_orden is null then
        raise exception 'El asiento no está disponible';
    end if;

    update orden_detalle set id_tipo_tarifa = (select id_tipo_tarifa from tipo_tarifa where codigo = 'cortesia')
    where id_orden = v_id_orden;
    perform calcular_total(v_id_orden);

    update ocupacion_asiento set estado = 'vendido', expira_en = null where id_orden = v_id_orden;
    update orden set estado = 'pagada', pagada_en = now() where id_orden = v_id_orden;
    perform emitir_boletos(v_id_orden);
    select id_boleto into v_id_boleto from boleto where id_orden = v_id_orden;

    insert into bitacora.asiento_auditoria_log (id_funcion, id_asiento, id_orden, id_usuario, evento, detalle)
    values (p_id_funcion, p_id_asiento, v_id_orden, p_id_usuario_cliente, 'compra', '{"cortesia": true}');
    perform registrar_operacion_admin('cortesia', 'boleto', v_id_boleto::text, null,
        jsonb_build_object('id_funcion', p_id_funcion, 'id_asiento', p_id_asiento, 'id_usuario_cliente', p_id_usuario_cliente),
        p_motivo);
    return v_id_boleto;
end $$;

-- Cambio manual de asiento de un boleto vigente, dentro de la misma función (RN-20)
create or replace function cine.cambiar_asiento(p_id_boleto bigint, p_id_asiento_nuevo integer, p_motivo text)
returns void
language plpgsql security definer set search_path = cine, pg_temp as $$
declare
    v_admin   bigint := usuario_en_contexto();
    v_boleto  boleto%rowtype;
    v_funcion funcion%rowtype;
    v_ocupa   ocupacion_asiento%rowtype;
begin
    select * into v_boleto from boleto where id_boleto = p_id_boleto for update;
    if not found or v_boleto.estado <> 'vigente' or exists (select 1 from checkin where id_boleto = p_id_boleto) then
        raise exception 'Solo se puede cambiar el asiento de un boleto vigente que no ha ingresado';
    end if;
    select * into v_funcion from funcion where id_funcion = v_boleto.id_funcion;
    if v_funcion.estado <> 'programada' or v_funcion.inicio <= now() then
        raise exception 'La función ya empezó o no está programada';
    end if;
    if not exists (select 1 from asiento a join zona z on z.id_zona = a.id_zona
                   where a.id_asiento = p_id_asiento_nuevo and z.id_sala = v_funcion.id_sala and a.es_habilitado) then
        raise exception 'El asiento nuevo no pertenece a la sala de la función o no está habilitado';
    end if;

    select * into v_ocupa from ocupacion_asiento where id_funcion = v_boleto.id_funcion and id_asiento = v_boleto.id_asiento;
    perform liberar_bloqueos_expirados(v_boleto.id_funcion, array[p_id_asiento_nuevo]);
    begin
        insert into ocupacion_asiento (id_funcion, id_asiento, id_orden, id_usuario, estado)
        values (v_boleto.id_funcion, p_id_asiento_nuevo, v_boleto.id_orden, v_ocupa.id_usuario, 'vendido');
    exception when unique_violation then
        raise exception 'El asiento nuevo no está disponible';
    end;
    delete from ocupacion_asiento where id_funcion = v_boleto.id_funcion and id_asiento = v_boleto.id_asiento;

    -- La línea de la orden cambia de asiento y el boleto la sigue (on update cascade)
    update orden_detalle set id_asiento = p_id_asiento_nuevo
    where id_orden = v_boleto.id_orden and id_asiento = v_boleto.id_asiento;

    insert into bitacora.asiento_auditoria_log (id_funcion, id_asiento, id_orden, id_usuario, evento, detalle)
    values (v_boleto.id_funcion, v_boleto.id_asiento, v_boleto.id_orden, v_admin, 'liberacion_usuario', '{"cambio_asiento": true}'),
           (v_boleto.id_funcion, p_id_asiento_nuevo, v_boleto.id_orden, v_admin, 'compra', '{"cambio_asiento": true}');
    perform registrar_operacion_admin('cambio_asiento', 'boleto', p_id_boleto::text,
        jsonb_build_object('id_asiento', v_boleto.id_asiento), jsonb_build_object('id_asiento', p_id_asiento_nuevo), p_motivo);
end $$;

-- Reserva administrativa de un asiento (prensa, mantenimiento): se muestra como "reservado"
create or replace function cine.reservar_asiento(p_id_funcion bigint, p_id_asiento integer, p_motivo text)
returns void
language plpgsql security definer set search_path = cine, pg_temp as $$
declare
    v_admin bigint := usuario_en_contexto();
begin
    perform liberar_bloqueos_expirados(p_id_funcion, array[p_id_asiento]);
    begin
        insert into ocupacion_asiento (id_funcion, id_asiento, id_usuario, estado)
        values (p_id_funcion, p_id_asiento, v_admin, 'reservado');
    exception when unique_violation then
        raise exception 'El asiento no está disponible';
    end;
    insert into bitacora.asiento_auditoria_log (id_funcion, id_asiento, id_usuario, evento)
    values (p_id_funcion, p_id_asiento, v_admin, 'reserva');
    perform registrar_operacion_admin('reserva_asiento', 'ocupacion_asiento', p_id_funcion || '-' || p_id_asiento,
        null, jsonb_build_object('estado', 'reservado'), p_motivo);
end $$;

-- Libera una reserva administrativa
create or replace function cine.liberar_reserva(p_id_funcion bigint, p_id_asiento integer, p_motivo text)
returns void
language plpgsql security definer set search_path = cine, pg_temp as $$
declare
    v_admin bigint := usuario_en_contexto();
begin
    delete from ocupacion_asiento where id_funcion = p_id_funcion and id_asiento = p_id_asiento and estado = 'reservado';
    if not found then
        raise exception 'El asiento no tiene una reserva administrativa';
    end if;
    insert into bitacora.asiento_auditoria_log (id_funcion, id_asiento, id_usuario, evento)
    values (p_id_funcion, p_id_asiento, v_admin, 'liberacion_usuario');
    perform registrar_operacion_admin('liberar_reserva', 'ocupacion_asiento', p_id_funcion || '-' || p_id_asiento,
        jsonb_build_object('estado', 'reservado'), null, p_motivo);
end $$;
