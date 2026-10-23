-- crear_base.sql
-- Crea el usuario dueño (imax_owner) y la base de datos (imax) en un PostgreSQL 16 ya
-- instalado. Se ejecuta una sola vez, con el superusuario de la instalación (postgres), antes
-- de db/init.sql. Si el usuario o la base ya existen, no los vuelve a crear.
--
--   $env:POSTGRES_PASSWORD = "<contraseña de imax_owner del .env>"
--   psql -U postgres -d postgres -f db/crear_base.sql
--
-- imax_owner es superusuario porque crea los roles de la aplicación y las pruebas cambian
-- de rol (set role). La aplicación nunca se conecta con él: usa imax_app (08_usuario_app.sql).

\set ON_ERROR_STOP on
\getenv clave_owner POSTGRES_PASSWORD
\if :{?clave_owner}
\else
    do $$ begin raise exception 'Falta la variable POSTGRES_PASSWORD del archivo .env'; end $$;
\endif

select 'create role imax_owner login superuser'
where not exists (select 1 from pg_roles where rolname = 'imax_owner') \gexec

select format('alter role imax_owner with login superuser password %L', :'clave_owner') \gexec

-- UTF8 para las tildes y la ñ; template0 permite elegir la codificación en cualquier equipo
select 'create database imax owner imax_owner encoding ''UTF8'' template template0'
where not exists (select 1 from pg_database where datname = 'imax') \gexec

-- Las marcas de tiempo se guardan en UTC; las horas locales se calculan con
-- 'America/Costa_Rica' en las consultas, igual en cualquier equipo
alter database imax set timezone to 'UTC';

\echo 'Usuario imax_owner y base imax listos.'
