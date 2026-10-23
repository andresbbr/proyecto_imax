-- 07_aplicacion.sql
-- Funciones de apoyo para la aplicación web. Devuelven solo lo que cada pantalla necesita,
-- verificando que la orden sea del usuario, para no dar permisos de lectura sobre las tablas.

-- Inicio de sesión: datos del usuario activo con ese correo. La contraseña se verifica en la
-- aplicación contra el hash.
create or replace function cine.datos_login(p_email text)
returns table (id_usuario bigint, contrasena_hash text, rol text, id_sede integer, nombre text)
language sql stable security definer set search_path = cine, pg_temp as $$
    select u.id_usuario, u.contrasena_hash, r.codigo, u.id_sede, u.nombre || ' ' || u.apellidos
    from usuario u
    join rol r on r.id_rol = u.id_rol
    where lower(u.email) = lower(p_email) and u.es_activo
$$;

-- Desglose de una orden para la pantalla de pago (RN-08): función, líneas, totales,
-- estado y vencimiento del bloqueo. Solo para el cliente o el vendedor de la orden.
create or replace function cine.resumen_orden(p_id_orden bigint, p_id_usuario bigint) returns jsonb
language plpgsql stable security definer set search_path = cine, pg_temp as $$
declare
    v_orden orden%rowtype;
begin
    select * into v_orden from orden where id_orden = p_id_orden;
    if not found or p_id_usuario not in (coalesce(v_orden.id_usuario_cliente, 0), coalesce(v_orden.id_usuario_vendedor, 0)) then
        raise exception 'La orden no existe o no le pertenece';
    end if;

    return jsonb_build_object(
        'id_orden', v_orden.id_orden,
        'id_funcion', v_orden.id_funcion,
        'estado', v_orden.estado,
        'canal', v_orden.canal,
        'subtotal', v_orden.subtotal,
        'descuento', v_orden.descuento,
        'cargo_servicio', v_orden.cargo_servicio,
        'impuesto', v_orden.impuesto,
        'total', v_orden.total,
        'expira_en', (select min(expira_en) from ocupacion_asiento where id_orden = p_id_orden and estado = 'bloqueado'),
        'funcion', (select jsonb_build_object('titulo', p.titulo, 'inicio', f.inicio, 'sala', s.nombre, 'sede', se.nombre)
                    from funcion f join pelicula p on p.id_pelicula = f.id_pelicula
                    join sala s on s.id_sala = f.id_sala join sede se on se.id_sede = s.id_sede
                    where f.id_funcion = v_orden.id_funcion),
        'lineas', (select coalesce(jsonb_agg(jsonb_build_object(
                        'id_asiento', d.id_asiento, 'fila', a.fila, 'numero', a.numero, 'zona', z.nombre,
                        'tipo_tarifa', tt.codigo, 'tarifa', tt.nombre, 'precio', d.precio_unitario,
                        'descuento', d.descuento, 'promocion', pr.nombre) order by a.fila, a.numero), '[]'::jsonb)
                   from orden_detalle d
                   join asiento a on a.id_asiento = d.id_asiento
                   join zona z on z.id_zona = a.id_zona
                   join tipo_tarifa tt on tt.id_tipo_tarifa = d.id_tipo_tarifa
                   left join promocion pr on pr.id_promocion = d.id_promocion
                   where d.id_orden = p_id_orden)
    );
end $$;

-- Boletos emitidos de una orden pagada, para la pantalla de confirmación (RN-11)
create or replace function cine.boletos_de_orden(p_id_orden bigint, p_id_usuario bigint)
returns table (id_boleto bigint, codigo_qr text, fila text, numero smallint, zona text, tarifa text, estado text)
language plpgsql stable security definer set search_path = cine, pg_temp as $$
begin
    if not exists (select 1 from orden o where o.id_orden = p_id_orden and o.estado = 'pagada'
                   and p_id_usuario in (coalesce(o.id_usuario_cliente, 0), coalesce(o.id_usuario_vendedor, 0))) then
        raise exception 'La orden no está pagada o no le pertenece';
    end if;
    return query
    select b.id_boleto, b.codigo_qr, a.fila, a.numero, z.nombre, tt.nombre, b.estado
    from boleto b
    join orden_detalle d on d.id_orden = b.id_orden and d.id_asiento = b.id_asiento
    join tipo_tarifa tt on tt.id_tipo_tarifa = d.id_tipo_tarifa
    join asiento a on a.id_asiento = b.id_asiento
    join zona z on z.id_zona = a.id_zona
    where b.id_orden = p_id_orden
    order by a.fila, a.numero;
end $$;

-- Corte de caja del taquillero: sus ventas pagadas en un día
create or replace function cine.corte_de_caja(p_id_vendedor bigint, p_fecha date)
returns table (ordenes bigint, boletos bigint, total numeric)
language sql stable security definer set search_path = cine, pg_temp as $$
    select count(*),
           coalesce(sum((select count(*) from orden_detalle d where d.id_orden = o.id_orden)), 0),
           coalesce(sum(o.total), 0)
    from orden o
    where o.id_usuario_vendedor = p_id_vendedor
      and o.estado = 'pagada'
      and (o.pagada_en at time zone 'America/Costa_Rica')::date = p_fecha
$$;

revoke execute on function cine.datos_login(text), cine.resumen_orden(bigint, bigint),
    cine.boletos_de_orden(bigint, bigint), cine.corte_de_caja(bigint, date) from public;
grant execute on function cine.datos_login(text) to imax_app;
grant execute on function cine.resumen_orden(bigint, bigint), cine.boletos_de_orden(bigint, bigint)
    to rol_cliente, rol_taquillero, rol_administrador;
grant execute on function cine.corte_de_caja(bigint, date) to rol_taquillero, rol_administrador;

-- El taquillero emite boletos físicos o digitales: puede leerlos (matriz de roles)
grant select on cine.boleto to rol_taquillero;
