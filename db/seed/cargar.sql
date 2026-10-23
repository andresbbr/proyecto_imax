-- cargar.sql
-- Carga los datos de demostración y la carga masiva, y muestra las filas y el tamaño de
-- las tablas principales. Se ejecuta después de db/init.sql:
--
--   docker exec imax_db psql -U imax_owner -d imax -v ON_ERROR_STOP=1 -f /db/seed/cargar.sql

\set ON_ERROR_STOP on
\timing on
set client_min_messages = warning;

\echo 'Datos de demostración...'
\ir 01_datos_demo.sql
\echo 'Carga masiva...'
\ir 02_carga_masiva.sql

\timing off
\echo 'Filas y tamaño por tabla:'
select t.tabla,
       t.filas,
       pg_size_pretty(t.bytes) as tamano_total,
       case when t.filas > 0 then round(t.bytes::numeric / t.filas) end as bytes_por_fila
from (
    select tabla,
           (xpath('/row/c/text()', query_to_xml('select count(*) as c from ' || tabla, false, true, '')))[1]::text::bigint as filas,
           coalesce((select sum(pg_total_relation_size(relid)) from pg_partition_tree(tabla::regclass)),
                    pg_total_relation_size(tabla::regclass)) as bytes
    from unnest(array[
        'cine.sede', 'cine.sala', 'cine.asiento', 'cine.funcion', 'cine.usuario', 'cine.orden',
        'cine.orden_detalle', 'cine.pago', 'cine.boleto', 'cine.checkin', 'cine.reembolso', 'cine.ocupacion_asiento',
        'bitacora.transaccion_log', 'bitacora.asiento_auditoria_log', 'bitacora.acceso_puerta_log',
        'bitacora.admin_operacion_audit'
    ]) as tabla
) as t
order by t.bytes desc;

select pg_size_pretty(pg_database_size(current_database())) as tamano_base_de_datos;
