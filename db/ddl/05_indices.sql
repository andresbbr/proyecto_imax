-- 05_indices.sql
-- Índices para las consultas más frecuentes. Las PK y los UNIQUE ya crean su propio índice;
-- aquí van los que aceleran las búsquedas por FK y por fecha. Están en un archivo aparte
-- para poder comparar los planes de EXPLAIN ANALYZE con y sin ellos.
--
-- No se crean índices sobre zona(id_sala) ni asiento(id_zona): esas búsquedas ya las cubren
-- uq_zona_sala_nombre (id_sala, nombre) y uq_asiento_zona_fila_numero (id_zona, fila, numero),
-- porque un índice sirve para buscar por su primera columna.

-- Cartelera y disponibilidad: funciones programadas a futuro, por fecha y por sala
create index ix_funcion_inicio on cine.funcion (inicio);
create index ix_funcion_sala_inicio on cine.funcion (id_sala, inicio);  -- funciones de una sala y control de traslapes
create index ix_sede_ciudad on cine.sede (id_ciudad);
create index ix_pelicula_genero_genero on cine.pelicula_genero (id_genero);

-- Barrido de bloqueos vencidos (RN-05)
create index ix_ocupacion_expira on cine.ocupacion_asiento (expira_en) where estado = 'bloqueado';

-- Reportes: ocupación y recaudación por función, top 5 de la última semana, mis entradas
create index ix_orden_funcion on cine.orden (id_funcion);
create index ix_boleto_emitido_en on cine.boleto (emitido_en);
create index ix_orden_cliente on cine.orden (id_usuario_cliente);

-- Pagos de una orden
create index ix_pago_orden on cine.pago (id_orden);

-- Boletos de una función (ocupación) y de una orden (emisión) ya están cubiertos por
-- uq_boleto_funcion_asiento_vigente y uq_boleto_orden_asiento.

-- Bitácoras: historial de un administrador y escaneos de un boleto
create index ix_admin_audit_usuario_fecha on bitacora.admin_operacion_audit (id_usuario, ocurrido_en);
create index ix_acceso_puerta_boleto on bitacora.acceso_puerta_log (id_boleto);
