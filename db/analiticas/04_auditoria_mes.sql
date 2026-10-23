-- 04_auditoria_mes.sql
-- Auditoría de operaciones críticas: modificaciones manuales, cortesías y reembolsos
-- hechos por los administradores durante el último mes, agrupados por administrador.
--
--   psql -U imax_owner -d imax -f db/analiticas/04_auditoria_mes.sql

select a.id_usuario,
       u.nombre || ' ' || u.apellidos as administrador,
       count(*) as operaciones,
       count(*) filter (where a.operacion = 'cortesia') as cortesias,
       count(*) filter (where a.operacion like 'reembolso%') as reembolsos,
       count(*) filter (where a.operacion = 'cambio_asiento') as cambios_asiento,
       count(*) filter (where a.operacion <> 'cortesia' and a.operacion not like 'reembolso%'
                          and a.operacion <> 'cambio_asiento') as otros_cambios,
       min(a.ocurrido_en) as primera,
       max(a.ocurrido_en) as ultima
from bitacora.admin_operacion_audit a
join cine.usuario u on u.id_usuario = a.id_usuario
where a.ocurrido_en >= now() - interval '1 month'
  and a.id_rol = (select id_rol from cine.rol where codigo = 'administrador')
group by a.id_usuario, u.nombre, u.apellidos
order by operaciones desc, a.id_usuario;
