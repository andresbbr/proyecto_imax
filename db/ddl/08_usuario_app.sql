-- 08_usuario_app.sql
-- Usuario de conexión de la aplicación web. No tiene permisos propios (NOINHERIT): en cada
-- petición la aplicación hace "set local role" al rol del usuario que inició sesión, así que
-- la base de datos aplica los permisos de ese rol (RN-17).
-- La contraseña se toma de la variable APP_DB_PASSWORD del archivo .env.

\getenv clave_app APP_DB_PASSWORD
\if :{?clave_app}
\else
    do $$ begin raise exception 'Falta la variable APP_DB_PASSWORD en el archivo .env'; end $$;
\endif

select 'create role imax_app login noinherit'
where not exists (select 1 from pg_roles where rolname = 'imax_app') \gexec

select format('alter role imax_app with login noinherit password %L', :'clave_app') \gexec

grant rol_cliente, rol_taquillero, rol_operador_puerta, rol_contador, rol_administrador to imax_app;
grant usage on schema cine to imax_app;
