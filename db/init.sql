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
\ir ddl/08_usuario_app.sql
\echo 'Creando funciones, triggers y vistas...'
\ir funciones/01_reglas.sql
\ir funciones/02_vistas.sql
\ir funciones/03_venta.sql
\ir funciones/04_acceso.sql
\ir funciones/05_administracion.sql
\ir funciones/06_permisos.sql
\ir funciones/07_aplicacion.sql

\echo 'Base de datos IMAX creada.'
