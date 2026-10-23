-- 01_esquemas.sql
-- Esquemas de la base de datos IMAX:
--   cine      tablas de la operación (catálogo, salas, venta, pagos, acceso)
--   bitacora  las 4 bitácoras con retención de 5 años (RN-20)
-- Se borran y se crean de nuevo para que la inicialización se pueda repetir desde cero.

drop schema if exists bitacora cascade;
drop schema if exists cine cascade;

create schema cine;
create schema bitacora;

revoke all on schema cine, bitacora from public;
