-- 06_roles.sql
-- Roles de base de datos con privilegio mínimo, uno por perfil de la matriz (RN-17).
-- Las operaciones de venta, pago, check-in y reembolso, y los registros en las
-- bitácoras, se hacen con funciones de la base de datos (db/funciones); los roles solo
-- reciben permiso para ejecutarlas. Ningún rol puede modificar ni borrar las bitácoras.

-- Los roles son globales del servidor: se crean solo si no existen.
do $$
declare
    r text;
begin
    foreach r in array array['rol_cliente', 'rol_taquillero', 'rol_operador_puerta', 'rol_contador', 'rol_administrador'] loop
        if not exists (select 1 from pg_roles where rolname = r) then
            execute format('create role %I nologin', r);
        end if;
    end loop;
end $$;

-- Todos los perfiles leen la cartelera y el catálogo
grant usage on schema cine to rol_cliente, rol_taquillero, rol_operador_puerta, rol_contador, rol_administrador;

grant select on
    cine.pais, cine.ciudad, cine.sede, cine.sala, cine.tipo_zona, cine.zona, cine.asiento, cine.puerta,
    cine.clasificacion, cine.genero, cine.pelicula, cine.pelicula_genero, cine.funcion,
    cine.tipo_tarifa, cine.tarifa, cine.promocion, cine.metodo_pago, cine.parametro_sistema
to rol_cliente, rol_taquillero, rol_operador_puerta, rol_contador, rol_administrador;

-- Cliente y taquillero: estado de los asientos para el mapa
grant select on cine.ocupacion_asiento to rol_cliente, rol_taquillero;

-- Operador de puerta: boletos y check-in
grant select on cine.boleto, cine.checkin to rol_operador_puerta;

-- Contador: conciliación, recaudación e informes
grant select on cine.orden, cine.orden_detalle, cine.pago, cine.boleto, cine.reembolso to rol_contador;
grant usage on schema bitacora to rol_contador;
grant select on bitacora.transaccion_log to rol_contador;

-- Administrador: lectura total, incluidas las bitácoras
grant select on all tables in schema cine to rol_administrador;
grant usage on schema bitacora to rol_administrador;
grant select on all tables in schema bitacora to rol_administrador;

-- Administrador: configuración de cartelera, salas, funciones y precios. Los cambios en
-- salas y asientos con ventas activas los rechaza un trigger (RN-18).
grant insert, update, delete on
    cine.pais, cine.ciudad, cine.sede, cine.sala, cine.tipo_zona, cine.zona, cine.asiento, cine.puerta,
    cine.clasificacion, cine.genero, cine.pelicula, cine.pelicula_genero, cine.funcion,
    cine.tipo_tarifa, cine.tarifa, cine.promocion, cine.parametro_sistema
to rol_administrador;
