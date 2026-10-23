-- 01_reglas.sql
-- Funciones de apoyo y triggers de las reglas de negocio que involucran más de una tabla:
-- no traslape de funciones, protección de salas con ventas (RN-18), emisión de boletos solo
-- con pago aprobado (RN-11), bitácoras de solo inserción y auditoría de cambios (RN-20).

-- Valor de un parámetro del sistema (RN-04, RN-05, RN-16, RN-19)
create or replace function cine.parametro(p_clave text) returns numeric
language sql stable as $$
    select valor from cine.parametro_sistema where clave = p_clave
$$;

-- La aplicación llama a esta función al inicio de cada transacción de un empleado para
-- indicar quién hace la operación y desde qué IP. Los valores duran hasta el fin de la transacción.
create or replace function cine.establecer_contexto(p_id_usuario bigint, p_ip inet) returns void
language plpgsql as $$
begin
    perform set_config('imax.id_usuario', p_id_usuario::text, true);
    perform set_config('imax.ip', p_ip::text, true);
end $$;

-- Registra una operación manual en la bitácora administrativa (RN-20). Exige el contexto.
create or replace function cine.registrar_operacion_admin(
    p_operacion text, p_entidad text, p_id_entidad text,
    p_anteriores jsonb, p_nuevos jsonb, p_motivo text
) returns void
language plpgsql security definer set search_path = cine, pg_temp as $$
declare
    v_id_usuario bigint := nullif(current_setting('imax.id_usuario', true), '')::bigint;
    v_ip         inet   := nullif(current_setting('imax.ip', true), '')::inet;
    v_id_rol     smallint;
begin
    select id_rol into v_id_rol from usuario where id_usuario = v_id_usuario;
    if v_id_rol is null or v_ip is null then
        raise exception 'Operación sin responsable: falta llamar a establecer_contexto(id_usuario, ip)';
    end if;
    insert into bitacora.admin_operacion_audit
        (id_usuario, id_rol, ip, operacion, entidad, id_entidad, valores_anteriores, valores_nuevos, motivo)
    values (v_id_usuario, v_id_rol, v_ip, p_operacion, p_entidad, p_id_entidad, p_anteriores, p_nuevos, p_motivo);
end $$;

-- Auditoría automática de cambios en las tablas de configuración (RN-20).
-- Solo registra cuando la operación trae contexto, es decir, cuando la hace un empleado
-- desde la aplicación. Las cargas de datos iniciales no lo traen.
create or replace function cine.trg_auditar_configuracion() returns trigger
language plpgsql security definer set search_path = cine, pg_temp as $$
declare
    v_anterior jsonb := case when tg_op in ('UPDATE', 'DELETE') then to_jsonb(old) end;
    v_nuevo    jsonb := case when tg_op in ('INSERT', 'UPDATE') then to_jsonb(new) end;
    v_fila     jsonb := coalesce(v_nuevo, v_anterior);
    v_operacion text := case tg_op when 'INSERT' then 'alta_' when 'UPDATE' then 'cambio_' else 'baja_' end || tg_table_name;
begin
    if nullif(current_setting('imax.id_usuario', true), '') is not null then
        perform registrar_operacion_admin(v_operacion, tg_table_name,
                coalesce(v_fila ->> ('id_' || tg_table_name), v_fila ->> 'clave'),
                v_anterior, v_nuevo, null);
    end if;
    return null;
end $$;

create trigger trg_sede_auditoria after insert or update or delete on cine.sede
    for each row execute function cine.trg_auditar_configuracion();
create trigger trg_sala_auditoria after insert or update or delete on cine.sala
    for each row execute function cine.trg_auditar_configuracion();
create trigger trg_zona_auditoria after insert or update or delete on cine.zona
    for each row execute function cine.trg_auditar_configuracion();
create trigger trg_asiento_auditoria after insert or update or delete on cine.asiento
    for each row execute function cine.trg_auditar_configuracion();
create trigger trg_pelicula_auditoria after insert or update or delete on cine.pelicula
    for each row execute function cine.trg_auditar_configuracion();
create trigger trg_funcion_auditoria after insert or update or delete on cine.funcion
    for each row execute function cine.trg_auditar_configuracion();
create trigger trg_tarifa_auditoria after insert or update or delete on cine.tarifa
    for each row execute function cine.trg_auditar_configuracion();
create trigger trg_promocion_auditoria after insert or update or delete on cine.promocion
    for each row execute function cine.trg_auditar_configuracion();
create trigger trg_parametro_auditoria after insert or update or delete on cine.parametro_sistema
    for each row execute function cine.trg_auditar_configuracion();

-- Una sala no puede tener dos funciones programadas que se traslapen.
-- Se buscan solo funciones del día anterior en adelante (ninguna dura más de un día).
create or replace function cine.trg_funcion_sin_traslape() returns trigger
language plpgsql as $$
begin
    if new.estado = 'programada' and exists (
        select 1
        from cine.funcion f
        where f.id_sala = new.id_sala
          and f.estado = 'programada'
          and f.id_funcion <> new.id_funcion
          and f.inicio > new.inicio - interval '1 day'
          and f.inicio < new.fin
          and f.fin > new.inicio
    ) then
        raise exception 'La sala ya tiene una función programada que se traslapa con ese horario';
    end if;
    return new;
end $$;

create trigger trg_funcion_sin_traslape before insert or update of id_sala, inicio, fin, estado on cine.funcion
    for each row execute function cine.trg_funcion_sin_traslape();

-- RN-18: una sala tiene ventas activas si hay asientos vendidos, reservados o bloqueados
-- (sin vencer) en alguna de sus funciones programadas que aún no terminan.
create or replace function cine.sala_tiene_ventas(p_id_sala integer) returns boolean
language sql stable as $$
    select exists (
        select 1
        from cine.funcion f
        join cine.ocupacion_asiento o on o.id_funcion = f.id_funcion
        where f.id_sala = p_id_sala
          and f.estado = 'programada'
          and f.fin > now()
          and (o.estado in ('vendido', 'reservado') or o.expira_en > now())
    )
$$;

create or replace function cine.trg_proteger_distribucion() returns trigger
language plpgsql as $$
declare
    v_salas integer[];
begin
    if tg_table_name = 'sala' then
        v_salas := array[old.id_sala];
    elsif tg_table_name = 'zona' then
        v_salas := array[old.id_sala, new.id_sala];
    else  -- asiento
        select array_agg(z.id_sala) into v_salas
        from cine.zona z
        where z.id_zona in (old.id_zona, new.id_zona);
    end if;

    if exists (select 1 from unnest(v_salas) as s where s is not null and cine.sala_tiene_ventas(s)) then
        raise exception 'No se puede modificar la distribución de la sala: tiene entradas vendidas o reservadas en funciones programadas (RN-18)';
    end if;
    return case when tg_op = 'DELETE' then old else new end;
end $$;

create trigger trg_sala_proteger before delete or update of id_sede, es_activa on cine.sala
    for each row execute function cine.trg_proteger_distribucion();
create trigger trg_zona_proteger before insert or update or delete on cine.zona
    for each row execute function cine.trg_proteger_distribucion();
create trigger trg_asiento_proteger before insert or update or delete on cine.asiento
    for each row execute function cine.trg_proteger_distribucion();

-- RN-11: un boleto solo se emite si su orden está pagada con un pago aprobado
-- (o es una cortesía de total 0) y corresponde a la función de la orden.
create or replace function cine.trg_boleto_solo_pagado() returns trigger
language plpgsql as $$
begin
    if not exists (
        select 1
        from cine.orden o
        where o.id_orden = new.id_orden
          and o.id_funcion = new.id_funcion
          and o.estado = 'pagada'
          and (o.total = 0 or exists (select 1 from cine.pago p where p.id_orden = o.id_orden and p.estado = 'aprobado'))
    ) then
        raise exception 'No se puede emitir un boleto sin un pago aprobado de su orden (RN-11)';
    end if;
    return new;
end $$;

create trigger trg_boleto_solo_pagado before insert on cine.boleto
    for each row execute function cine.trg_boleto_solo_pagado();

-- Las bitácoras son de solo inserción, incluso para el dueño del esquema (RN-20)
create or replace function bitacora.trg_solo_insercion() returns trigger
language plpgsql as $$
begin
    raise exception 'La bitácora % no se puede modificar ni borrar', tg_table_name;
end $$;

create trigger trg_transaccion_log_solo_insercion before update or delete on bitacora.transaccion_log
    for each row execute function bitacora.trg_solo_insercion();
create trigger trg_asiento_auditoria_log_solo_insercion before update or delete on bitacora.asiento_auditoria_log
    for each row execute function bitacora.trg_solo_insercion();
create trigger trg_acceso_puerta_log_solo_insercion before update or delete on bitacora.acceso_puerta_log
    for each row execute function bitacora.trg_solo_insercion();
create trigger trg_admin_operacion_audit_solo_insercion before update or delete on bitacora.admin_operacion_audit
    for each row execute function bitacora.trg_solo_insercion();
