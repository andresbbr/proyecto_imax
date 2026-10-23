-- 05_indices.sql
-- Índices para las consultas más frecuentes. Las PK y los UNIQUE ya crean su propio índice;
-- aquí van los que aceleran las búsquedas por FK y por fecha. Están en un archivo aparte
-- para poder comparar los planes de EXPLAIN ANALYZE con y sin ellos.

-- Cartelera: funciones programadas a futuro y filtros por ubicación y género
create index ix_funcion_inicio on cine.funcion (inicio);
create index ix_funcion_sala_inicio on cine.funcion (id_sala, inicio);  -- programación por sala y control de traslapes
create index ix_sede_ciudad on cine.sede (id_ciudad);
create index ix_pelicula_genero_genero on cine.pelicula_genero (id_genero);

-- Mapa de asientos de una función: asientos de la sala y su ocupación
create index ix_zona_sala on cine.zona (id_sala);
create index ix_asiento_zona on cine.asiento (id_zona);

-- Barrido de bloqueos vencidos (RN-05)
create index ix_ocupacion_expira on cine.ocupacion_asiento (expira_en) where estado = 'bloqueado';

-- Reportes: ocupación y recaudación por función, top de la última semana, mis entradas
create index ix_orden_funcion on cine.orden (id_funcion);
create index ix_orden_pagada_en on cine.orden (pagada_en);
create index ix_orden_cliente on cine.orden (id_usuario_cliente);

-- Pagos por orden y métodos de pago preferidos
create index ix_pago_orden on cine.pago (id_orden);
create index ix_pago_metodo on cine.pago (id_metodo_pago);

-- Boletos de una función (ocupación) y de una orden (emisión) ya están cubiertos por
-- uq_boleto_funcion_asiento_vigente y uq_boleto_orden_asiento.

-- Bitácoras: auditoría del último mes por administrador y escaneos de un boleto
create index ix_admin_audit_usuario_fecha on bitacora.admin_operacion_audit (id_usuario, ocurrido_en);
create index ix_acceso_puerta_boleto on bitacora.acceso_puerta_log (id_boleto);
