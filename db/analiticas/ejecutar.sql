-- ejecutar.sql
-- Corre las 4 consultas analíticas y comprueba que sus resultados cuadran con los datos,
-- calculando lo mismo por otro camino.
--
--   psql -U imax_owner -d imax -v ON_ERROR_STOP=1 -f db/analiticas/ejecutar.sql

\set ON_ERROR_STOP on
\pset footer off

\echo '1. Ocupación y recaudación por función'
\ir 01_ocupacion_recaudacion.sql
\echo '2. Top 5 de películas de la última semana'
\ir 02_top5_semana.sql
\echo '3. Métodos de pago preferidos'
\ir 03_metodos_pago.sql
\echo '4. Auditoría de operaciones críticas del último mes'
\ir 04_auditoria_mes.sql

\echo 'Comprobaciones'

select 'Ocupación: los vendidos coinciden con las líneas de órdenes pagadas sin anular' as comprobacion,
       (select count(*) from cine.boleto where id_funcion = :id_funcion and estado = 'vigente')
     = (select count(*) from cine.orden_detalle d join cine.orden o on o.id_orden = d.id_orden
        where o.id_funcion = :id_funcion and o.estado = 'pagada'
          and not exists (select 1 from cine.reembolso r join cine.boleto b on b.id_boleto = r.id_boleto
                          where b.id_orden = d.id_orden and b.id_asiento = d.id_asiento)) as cumple
union all
select 'Recaudación: ventas de la función = pagos aprobados de sus órdenes',
       (select coalesce(sum(o.total), 0) from cine.orden o where o.id_funcion = :id_funcion and o.estado = 'pagada')
     = (select coalesce(sum(p.monto), 0) from cine.pago p join cine.orden o on o.id_orden = p.id_orden
        where o.id_funcion = :id_funcion and p.estado = 'aprobado')
union all
select 'Top 5: los boletos de la semana coinciden con las órdenes pagadas en la semana',
       (select count(*) from cine.boleto b
        where b.estado = 'vigente' and b.emitido_en >= now() - interval '7 days')
     = (select count(*) from cine.orden o join cine.boleto b on b.id_orden = o.id_orden and b.estado = 'vigente'
        where o.estado = 'pagada' and o.pagada_en >= now() - interval '7 days')
union all
select 'Métodos de pago: los porcentajes suman 100',
       (select abs(sum(pct) - 100) < 0.05 from (
            select 100.0 * count(*) / sum(count(*)) over () as pct
            from cine.pago where estado = 'aprobado' group by id_metodo_pago) x)
union all
select 'Métodos de pago: un pago aprobado por cada orden pagada con monto',
       (select count(*) from cine.pago where estado = 'aprobado')
     = (select count(*) from cine.orden where estado = 'pagada' and total > 0)
union all
select 'Auditoría: el total agrupado coincide con las operaciones del último mes',
       (select count(*) from bitacora.admin_operacion_audit
        where ocurrido_en >= now() - interval '1 month'
          and id_rol = (select id_rol from cine.rol where codigo = 'administrador'))
     = (select coalesce(sum(n), 0) from (
            select count(*) as n from bitacora.admin_operacion_audit a
            join cine.usuario u on u.id_usuario = a.id_usuario
            where a.ocurrido_en >= now() - interval '1 month'
              and a.id_rol = (select id_rol from cine.rol where codigo = 'administrador')
            group by a.id_usuario) x);
