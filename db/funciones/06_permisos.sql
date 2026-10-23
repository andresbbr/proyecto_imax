-- 06_permisos.sql
-- Permisos de ejecución de las funciones y de lectura de las vistas, según la matriz de
-- privilegio mínimo (RN-17). Las funciones internas (emitir_boletos, registrar_operacion_admin)
-- no se otorgan a nadie: solo las llaman otras funciones.

revoke execute on all functions in schema cine from public;
revoke execute on all functions in schema bitacora from public;

grant execute on function cine.parametro(text)
    to rol_cliente, rol_taquillero, rol_operador_puerta, rol_contador, rol_administrador;

-- Los empleados indican quién hace la operación y desde qué IP
grant execute on function cine.establecer_contexto(bigint, inet)
    to rol_taquillero, rol_operador_puerta, rol_contador, rol_administrador;

-- Compra en línea (cliente) y venta presencial (taquillero)
grant execute on function
    cine.bloquear_asientos(bigint, bigint, integer[], text),
    cine.elegir_tarifa(bigint, integer, text),
    cine.calcular_total(bigint),
    cine.liberar_asientos(bigint),
    cine.procesar_pago(bigint, text, text, text)
to rol_cliente, rol_taquillero, rol_administrador;

-- Control de acceso en puerta
grant execute on function
    cine.validar_entrada(text, integer, bigint),
    cine.registrar_incidencia(text, integer, bigint, text)
to rol_operador_puerta, rol_administrador;

-- Operaciones del administrador
grant execute on function
    cine.anular_boleto(bigint, text, text),
    cine.cancelar_funcion(bigint, text),
    cine.otorgar_cortesia(bigint, integer, bigint, text),
    cine.cambiar_asiento(bigint, integer, text),
    cine.reservar_asiento(bigint, integer, text),
    cine.liberar_reserva(bigint, integer, text),
    cine.liberar_bloqueos_expirados(bigint, integer[]),
    cine.sala_tiene_ventas(integer),
    cine.usuario_en_contexto()
to rol_administrador;

-- Vistas
grant select on cine.v_cartelera_activa, cine.v_mapa_asientos
    to rol_cliente, rol_taquillero, rol_operador_puerta, rol_contador, rol_administrador;
grant select on cine.v_mis_entradas to rol_cliente, rol_administrador;
