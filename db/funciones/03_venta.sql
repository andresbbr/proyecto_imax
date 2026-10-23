-- 03_venta.sql
-- Flujo de compra: bloqueo temporal de asientos, elección de tarifas, cálculo del total,
-- pago simulado y emisión de boletos. Las funciones son security definer: corren con los
-- permisos del dueño del esquema y los roles solo reciben permiso para ejecutarlas.

-- RN-05: libera los bloqueos vencidos (todos, o solo los de ciertos asientos de una función)
-- y marca como expiradas las órdenes pendientes que se quedaron sin asientos.
create or replace function cine.liberar_bloqueos_expirados(
    p_id_funcion bigint default null, p_asientos integer[] default null
) returns integer
language plpgsql security definer set search_path = cine, pg_temp as $$
declare
    v_liberados integer;
    v_ordenes   bigint[];
begin
    with borrados as (
        delete from ocupacion_asiento
        where estado = 'bloqueado'
          and expira_en <= now()
          and (p_id_funcion is null or id_funcion = p_id_funcion)
          and (p_asientos is null or id_asiento = any (p_asientos))
        returning id_funcion, id_asiento, id_orden, id_usuario
    ), registro as (
        insert into bitacora.asiento_auditoria_log (id_funcion, id_asiento, id_orden, id_usuario, evento)
        select id_funcion, id_asiento, id_orden, id_usuario, 'liberacion_expiracion' from borrados
    )
    select count(*), array_agg(distinct id_orden) into v_liberados, v_ordenes from borrados;

    update orden o
    set estado = 'expirada'
    where o.id_orden = any (v_ordenes)
      and o.estado = 'pendiente'
      and not exists (select 1 from ocupacion_asiento x where x.id_orden = o.id_orden);

    return v_liberados;
end $$;

-- Recalcula los precios, la promoción, el cargo por servicio, el impuesto y el total de una
-- orden pendiente (RN-07, RN-08). Devuelve el total.
create or replace function cine.calcular_total(p_id_orden bigint) returns numeric
language plpgsql security definer set search_path = cine, pg_temp as $$
declare
    v_orden     orden%rowtype;
    v_inicio    timestamptz;
    v_id_sede   integer;
    v_tasa      numeric;
    v_dia       integer;
    v_tipo_dia  text;
    v_promo     promocion%rowtype;
    v_subtotal  numeric(12,2);
    v_descuento numeric(12,2);
    v_cargo     numeric(12,2);
    v_impuesto  numeric(12,2);
    v_boletos   integer;
begin
    select * into v_orden from orden where id_orden = p_id_orden;
    if not found or v_orden.estado <> 'pendiente' then
        raise exception 'Solo se puede calcular el total de una orden pendiente';
    end if;

    select f.inicio, s.id_sede, pa.tasa_impuesto into v_inicio, v_id_sede, v_tasa
    from funcion f
    join sala s on s.id_sala = f.id_sala
    join sede se on se.id_sede = s.id_sede
    join ciudad ci on ci.id_ciudad = se.id_ciudad
    join pais pa on pa.id_pais = ci.id_pais
    where f.id_funcion = v_orden.id_funcion;

    v_dia := extract(isodow from v_inicio);
    v_tipo_dia := case when v_dia in (6, 7) then 'fin_de_semana' else 'entre_semana' end;

    -- 1. Precio de cada línea según la matriz de tarifas (la cortesía vale 0)
    if exists (
        select 1
        from orden_detalle d
        join tipo_tarifa tt on tt.id_tipo_tarifa = d.id_tipo_tarifa
        join asiento a on a.id_asiento = d.id_asiento
        join zona z on z.id_zona = a.id_zona
        left join tarifa t on t.id_sede = v_id_sede and t.id_tipo_zona = z.id_tipo_zona
                          and t.id_tipo_tarifa = d.id_tipo_tarifa and t.tipo_dia = v_tipo_dia
        where d.id_orden = p_id_orden and not tt.es_cortesia and t.id_tarifa is null
    ) then
        raise exception 'No hay una tarifa definida para alguno de los asientos o tipos de entrada';
    end if;

    update orden_detalle d
    set precio_unitario = (
            select case when tt.es_cortesia then 0 else t.precio end
            from asiento a
            join zona z on z.id_zona = a.id_zona
            join tipo_tarifa tt on tt.id_tipo_tarifa = d.id_tipo_tarifa
            left join tarifa t on t.id_sede = v_id_sede and t.id_tipo_zona = z.id_tipo_zona
                              and t.id_tipo_tarifa = d.id_tipo_tarifa and t.tipo_dia = v_tipo_dia
            where a.id_asiento = d.id_asiento),
        descuento = 0,
        id_promocion = null
    where d.id_orden = p_id_orden;

    -- 2. Primera promoción vigente que aplica a la fecha y a los tipos de entrada de la orden
    select * into v_promo
    from promocion pr
    where pr.es_activa
      and v_inicio::date between pr.vigente_desde and pr.vigente_hasta
      and (pr.dia_semana is null or pr.dia_semana = v_dia)
      and (pr.id_tipo_tarifa is null or exists (
              select 1 from orden_detalle d where d.id_orden = p_id_orden and d.id_tipo_tarifa = pr.id_tipo_tarifa))
    order by pr.id_promocion
    limit 1;

    if found and v_promo.tipo = 'porcentaje' then
        update orden_detalle
        set descuento = round(precio_unitario * v_promo.porcentaje / 100, 2),
            id_promocion = v_promo.id_promocion
        where id_orden = p_id_orden
          and (v_promo.id_tipo_tarifa is null or id_tipo_tarifa = v_promo.id_tipo_tarifa);
    elsif found and v_promo.tipo = '2x1' then
        -- Por cada par de entradas de la misma categoría, la más barata del par es gratis
        update orden_detalle d
        set descuento = d.precio_unitario,
            id_promocion = v_promo.id_promocion
        from (select id_asiento,
                     row_number() over (partition by id_tipo_tarifa order by precio_unitario desc, id_asiento) as n
              from orden_detalle
              where id_orden = p_id_orden
                and (v_promo.id_tipo_tarifa is null or id_tipo_tarifa = v_promo.id_tipo_tarifa)) x
        where d.id_orden = p_id_orden
          and d.id_asiento = x.id_asiento
          and x.n % 2 = 0;
    end if;

    -- 3. Totales: tarifas - descuentos + cargo por servicio (solo en línea) + impuesto del país
    select coalesce(sum(precio_unitario), 0), coalesce(sum(descuento), 0), count(*)
    into v_subtotal, v_descuento, v_boletos
    from orden_detalle
    where id_orden = p_id_orden;

    v_cargo := case when v_orden.canal = 'en_linea' and v_subtotal > v_descuento
                    then parametro('cargo_servicio') * v_boletos else 0 end;
    v_impuesto := round((v_subtotal - v_descuento + v_cargo) * v_tasa, 2);

    update orden
    set subtotal = v_subtotal,
        descuento = v_descuento,
        cargo_servicio = v_cargo,
        impuesto = v_impuesto,
        total = v_subtotal - v_descuento + v_cargo + v_impuesto
    where id_orden = p_id_orden;

    return v_subtotal - v_descuento + v_cargo + v_impuesto;
end $$;

-- Bloquea temporalmente los asientos elegidos y crea la orden pendiente (RN-04, RN-05).
-- Si otro usuario ya tiene alguno de esos asientos, la PK de ocupacion_asiento rechaza la
-- inserción: se deshace la orden, se registra la colisión y la función devuelve nulo.
create or replace function cine.bloquear_asientos(
    p_id_funcion bigint, p_id_usuario bigint, p_asientos integer[], p_canal text default 'en_linea'
) returns bigint
language plpgsql security definer set search_path = cine, pg_temp as $$
declare
    v_funcion  funcion%rowtype;
    v_cantidad integer := coalesce(array_length(p_asientos, 1), 0);
    v_maximo   integer := parametro('max_asientos_por_orden');
    v_minutos  integer := parametro('minutos_bloqueo');
    v_id_orden bigint;
begin
    select * into v_funcion from funcion where id_funcion = p_id_funcion;
    if not found or v_funcion.estado <> 'programada' or v_funcion.inicio <= now() then
        raise exception 'La función no está disponible para la venta';
    end if;
    if v_cantidad = 0 then
        raise exception 'Debe elegir al menos un asiento';
    end if;
    if v_cantidad > v_maximo then
        raise exception 'Se pueden comprar como máximo % asientos por transacción (RN-04)', v_maximo;
    end if;
    if (select count(distinct x) from unnest(p_asientos) as x) <> v_cantidad then
        raise exception 'Hay asientos repetidos en la selección';
    end if;
    if (select count(*)
        from asiento a
        join zona z on z.id_zona = a.id_zona
        where a.id_asiento = any (p_asientos) and z.id_sala = v_funcion.id_sala and a.es_habilitado) <> v_cantidad then
        raise exception 'Algún asiento no pertenece a la sala de la función o no está habilitado';
    end if;

    -- Los bloqueos vencidos de estos asientos se liberan dentro de la misma transacción
    perform liberar_bloqueos_expirados(p_id_funcion, p_asientos);

    begin
        insert into orden (id_funcion, canal, id_usuario_cliente, id_usuario_vendedor)
        values (p_id_funcion, p_canal,
                case when p_canal = 'en_linea' then p_id_usuario end,
                case when p_canal = 'taquilla' then p_id_usuario end)
        returning id_orden into v_id_orden;

        insert into ocupacion_asiento (id_funcion, id_asiento, id_orden, id_usuario, estado, expira_en)
        select p_id_funcion, x, v_id_orden, p_id_usuario, 'bloqueado', now() + make_interval(mins => v_minutos)
        from unnest(p_asientos) as x;
    exception when unique_violation then
        insert into bitacora.asiento_auditoria_log (id_funcion, id_asiento, id_usuario, evento)
        select p_id_funcion, x, p_id_usuario, 'colision' from unnest(p_asientos) as x;
        return null;
    end;

    -- Las líneas empiezan con tarifa adulto; el cliente puede cambiarla con elegir_tarifa
    insert into orden_detalle (id_orden, id_asiento, id_tipo_tarifa, precio_unitario)
    select v_id_orden, x, (select id_tipo_tarifa from tipo_tarifa where codigo = 'adulto'), 0
    from unnest(p_asientos) as x;
    perform calcular_total(v_id_orden);

    insert into bitacora.asiento_auditoria_log (id_funcion, id_asiento, id_orden, id_usuario, evento)
    select p_id_funcion, x, v_id_orden, p_id_usuario, 'bloqueo' from unnest(p_asientos) as x;
    insert into bitacora.transaccion_log (id_orden, evento, monto, impuesto)
    select id_orden, 'orden_creada', total, impuesto from orden where id_orden = v_id_orden;

    return v_id_orden;
end $$;

-- Cambia el tipo de entrada (adulto, niño, tercera edad, estudiante) de un asiento de la orden
create or replace function cine.elegir_tarifa(p_id_orden bigint, p_id_asiento integer, p_codigo_tarifa text)
returns numeric
language plpgsql security definer set search_path = cine, pg_temp as $$
declare
    v_tipo tipo_tarifa%rowtype;
begin
    select * into v_tipo from tipo_tarifa where codigo = p_codigo_tarifa;
    if not found then
        raise exception 'Tipo de entrada desconocido: %', p_codigo_tarifa;
    end if;
    if v_tipo.es_cortesia then
        raise exception 'Las cortesías solo las otorga un administrador';
    end if;
    update orden_detalle set id_tipo_tarifa = v_tipo.id_tipo_tarifa
    where id_orden = p_id_orden and id_asiento = p_id_asiento;
    if not found then
        raise exception 'El asiento no pertenece a la orden';
    end if;
    return calcular_total(p_id_orden);
end $$;

-- El cliente abandona la compra: se liberan sus bloqueos y la orden queda cancelada
create or replace function cine.liberar_asientos(p_id_orden bigint) returns integer
language plpgsql security definer set search_path = cine, pg_temp as $$
declare
    v_liberados integer;
begin
    with borrados as (
        delete from ocupacion_asiento where id_orden = p_id_orden and estado = 'bloqueado'
        returning id_funcion, id_asiento, id_orden, id_usuario
    ), registro as (
        insert into bitacora.asiento_auditoria_log (id_funcion, id_asiento, id_orden, id_usuario, evento)
        select id_funcion, id_asiento, id_orden, id_usuario, 'liberacion_usuario' from borrados
    )
    select count(*) into v_liberados from borrados;

    update orden set estado = 'cancelada' where id_orden = p_id_orden and estado = 'pendiente';
    return v_liberados;
end $$;

-- RN-11 y RN-12: emite un boleto con QR único por cada línea de una orden pagada.
-- Solo la llaman procesar_pago y otorgar_cortesia.
create or replace function cine.emitir_boletos(p_id_orden bigint) returns integer
language plpgsql security definer set search_path = cine, pg_temp as $$
declare
    v_emitidos integer;
begin
    insert into boleto (id_orden, id_asiento, id_funcion, codigo_qr)
    select d.id_orden, d.id_asiento, o.id_funcion, upper(replace(gen_random_uuid()::text, '-', ''))
    from orden_detalle d
    join orden o on o.id_orden = d.id_orden
    where d.id_orden = p_id_orden;
    get diagnostics v_emitidos = row_count;

    insert into bitacora.transaccion_log (id_orden, evento, detalle)
    values (p_id_orden, 'boletos_emitidos', jsonb_build_object('boletos', v_emitidos));
    return v_emitidos;
end $$;

-- Pago simulado (RN-09, RN-10, RN-11). La pasarela rechaza las tarjetas que terminan en 0002
-- y las órdenes cuyo bloqueo ya venció. Aprobado: asientos vendidos y boletos emitidos.
-- Rechazado: se registra el intento y los asientos se liberan de inmediato.
create or replace function cine.procesar_pago(
    p_id_orden bigint, p_codigo_metodo text, p_ultimos4 text default null, p_marca text default null
) returns text
language plpgsql security definer set search_path = cine, pg_temp as $$
declare
    v_orden    orden%rowtype;
    v_metodo   metodo_pago%rowtype;
    v_ultimos4 text := p_ultimos4;
    v_marca    text := p_marca;
    v_motivo   text;
    v_id_pago  bigint;
begin
    select * into v_orden from orden where id_orden = p_id_orden for update;
    if not found or v_orden.estado <> 'pendiente' then
        raise exception 'La orden no está pendiente de pago';
    end if;
    if v_orden.total <= 0 then
        raise exception 'La orden no tiene monto a pagar';
    end if;
    select * into v_metodo from metodo_pago where codigo = p_codigo_metodo;
    if not found then
        raise exception 'Método de pago desconocido: %', p_codigo_metodo;
    end if;
    if v_metodo.es_tarjeta and (v_ultimos4 is null or v_marca is null) then
        raise exception 'El pago con tarjeta necesita los últimos 4 dígitos y la marca';
    elsif not v_metodo.es_tarjeta then
        v_ultimos4 := null;
        v_marca := null;
    end if;

    insert into bitacora.transaccion_log (id_orden, evento, monto, impuesto)
    values (p_id_orden, 'pago_solicitado', v_orden.total, v_orden.impuesto);

    -- Respuesta de la pasarela simulada
    if (select count(*) from ocupacion_asiento
         where id_orden = p_id_orden and estado = 'bloqueado' and expira_en > now())
       < (select count(*) from orden_detalle where id_orden = p_id_orden) then
        v_motivo := 'El tiempo de bloqueo de los asientos expiró';
    elsif v_ultimos4 = '0002' then
        v_motivo := 'Tarjeta rechazada por el banco emisor';
    end if;

    if v_motivo is null then
        insert into pago (id_orden, id_metodo_pago, monto, estado, token_pasarela, codigo_autorizacion, ultimos4, marca)
        values (p_id_orden, v_metodo.id_metodo_pago, v_orden.total, 'aprobado',
                'tok_' || replace(gen_random_uuid()::text, '-', ''), upper(substr(md5(random()::text), 1, 8)),
                v_ultimos4, v_marca)
        returning id_pago into v_id_pago;

        update ocupacion_asiento set estado = 'vendido', expira_en = null where id_orden = p_id_orden;
        update orden set estado = 'pagada', pagada_en = now() where id_orden = p_id_orden;

        insert into bitacora.transaccion_log (id_orden, id_pago, evento, monto, impuesto, detalle)
        values (p_id_orden, v_id_pago, 'pago_aprobado', v_orden.total, v_orden.impuesto,
                jsonb_build_object('metodo', p_codigo_metodo, 'marca', v_marca, 'ultimos4', v_ultimos4));
        insert into bitacora.asiento_auditoria_log (id_funcion, id_asiento, id_orden, id_usuario, evento)
        select v_orden.id_funcion, d.id_asiento, p_id_orden, coalesce(v_orden.id_usuario_cliente, v_orden.id_usuario_vendedor), 'compra'
        from orden_detalle d where d.id_orden = p_id_orden;

        perform emitir_boletos(p_id_orden);
        return 'aprobado';
    end if;

    insert into pago (id_orden, id_metodo_pago, monto, estado, token_pasarela, motivo_rechazo, ultimos4, marca)
    values (p_id_orden, v_metodo.id_metodo_pago, v_orden.total, 'rechazado',
            'tok_' || replace(gen_random_uuid()::text, '-', ''), v_motivo, v_ultimos4, v_marca)
    returning id_pago into v_id_pago;

    insert into bitacora.transaccion_log (id_orden, id_pago, evento, monto, impuesto, detalle)
    values (p_id_orden, v_id_pago, 'pago_rechazado', v_orden.total, v_orden.impuesto, jsonb_build_object('motivo', v_motivo));

    with borrados as (
        delete from ocupacion_asiento where id_orden = p_id_orden
        returning id_funcion, id_asiento, id_orden, id_usuario
    )
    insert into bitacora.asiento_auditoria_log (id_funcion, id_asiento, id_orden, id_usuario, evento)
    select id_funcion, id_asiento, id_orden, id_usuario, 'liberacion_rechazo' from borrados;

    update orden set estado = 'rechazada' where id_orden = p_id_orden;
    return 'rechazado: ' || v_motivo;
end $$;
