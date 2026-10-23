-- 04_acceso.sql
-- Control de acceso en puerta. Cada escaneo queda en bitacora.acceso_puerta_log.

-- Valida un QR en una puerta (RN-14, RN-15, RN-16, RN-06). El ingreso exitoso inserta el
-- check-in; como su PK es el boleto, un segundo ingreso del mismo boleto es imposible.
create or replace function cine.validar_entrada(
    p_codigo_qr text, p_id_puerta integer, p_id_usuario_operador bigint default null,
    out resultado text, out mensaje text
)
language plpgsql security definer set search_path = cine, pg_temp as $$
declare
    v_boleto      boleto%rowtype;
    v_funcion     funcion%rowtype;
    v_sala_puerta integer;
    v_en_curso    bigint;
    v_antes       interval := make_interval(mins => parametro('minutos_antes_ingreso')::int);
    v_despues     interval := make_interval(mins => parametro('minutos_despues_ingreso')::int);
    v_documento   boolean;
begin
    select id_sala into v_sala_puerta from puerta where id_puerta = p_id_puerta and es_activa;
    if not found then
        raise exception 'Puerta desconocida o inactiva';
    end if;

    -- Función que se está recibiendo en esa sala en este momento
    select id_funcion into v_en_curso
    from funcion
    where id_sala = v_sala_puerta
      and estado = 'programada'
      and now() between inicio - v_antes and inicio + v_despues
    order by inicio
    limit 1;

    select * into v_boleto from boleto where codigo_qr = p_codigo_qr;
    if not found then
        resultado := 'inexistente';
        mensaje := 'Entrada no válida';
    elsif v_boleto.estado = 'anulado' then
        resultado := 'anulado';
        mensaje := 'Entrada anulada';
    elsif exists (select 1 from checkin where id_boleto = v_boleto.id_boleto) then
        resultado := 'duplicado';
        mensaje := 'Entrada ya utilizada';
    else
        select * into v_funcion from funcion where id_funcion = v_boleto.id_funcion;
        if v_funcion.id_sala <> v_sala_puerta or (v_en_curso is not null and v_en_curso <> v_funcion.id_funcion) then
            resultado := 'otra_funcion';
            mensaje := 'La entrada es de otra función o sala';
        elsif now() < v_funcion.inicio - v_antes or now() > v_funcion.inicio + v_despues then
            resultado := 'fuera_de_horario';
            mensaje := 'Fuera del horario de ingreso';
        else
            begin
                insert into checkin (id_boleto, id_puerta, id_usuario_operador)
                values (v_boleto.id_boleto, p_id_puerta, p_id_usuario_operador);

                select tt.requiere_validacion_documento into v_documento
                from orden_detalle d
                join tipo_tarifa tt on tt.id_tipo_tarifa = d.id_tipo_tarifa
                where d.id_orden = v_boleto.id_orden and d.id_asiento = v_boleto.id_asiento;

                resultado := 'exitoso';
                mensaje := case when v_documento then 'Acceso permitido. Validar documento de la tarifa especial'
                                else 'Acceso permitido' end;
            exception when unique_violation then
                -- Otro escaneo del mismo boleto se registró al mismo tiempo
                resultado := 'duplicado';
                mensaje := 'Entrada ya utilizada';
            end;
        end if;
    end if;

    insert into bitacora.acceso_puerta_log
        (codigo_qr_leido, id_boleto, id_puerta, id_funcion_en_curso, id_usuario_operador, resultado, mensaje)
    values (p_codigo_qr, v_boleto.id_boleto, p_id_puerta, v_en_curso, p_id_usuario_operador, resultado, mensaje);
end $$;

-- RN-06: el operador registra que no se presentó el documento de una tarifa especial
-- (o cualquier otra incidencia en puerta).
create or replace function cine.registrar_incidencia(
    p_codigo_qr text, p_id_puerta integer, p_id_usuario_operador bigint, p_detalle text
) returns void
language plpgsql security definer set search_path = cine, pg_temp as $$
begin
    insert into bitacora.acceso_puerta_log (codigo_qr_leido, id_boleto, id_puerta, id_usuario_operador, resultado, mensaje)
    select p_codigo_qr, b.id_boleto, p_id_puerta, p_id_usuario_operador, 'incidencia_documento', p_detalle
    from (select 1) x
    left join boleto b on b.codigo_qr = p_codigo_qr;
end $$;
