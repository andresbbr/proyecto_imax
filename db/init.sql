-- init.sql
-- Crea la base de datos IMAX desde cero. Se puede ejecutar las veces que se quiera:
-- borra y vuelve a crear los esquemas cine y bitacora.
--
--   docker exec imax_db psql -U imax_owner -d imax -v ON_ERROR_STOP=1 -f /db/init.sql

\set ON_ERROR_STOP on
\set QUIET on
set client_min_messages = warning;

\echo 'Creando esquemas y tablas...'
\ir ddl/01_esquemas.sql
\ir ddl/02_tablas_catalogo.sql
\ir ddl/03_tablas_venta.sql
\ir ddl/04_bitacoras.sql
\echo 'Creando índices y roles...'
\ir ddl/05_indices.sql
\ir ddl/06_roles.sql
\echo 'Cargando datos base...'
\ir ddl/07_datos_base.sql

\echo 'Base de datos IMAX creada.'
