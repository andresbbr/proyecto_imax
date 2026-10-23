-- explain_indices.sql
-- Planes de ejecución antes y después de los índices de db/ddl/05_indices.sql para la
-- consultas de disponibilidad de asientos (mapa de una función y asientos libres de las
-- funciones de una sala) y las 4 consultas analíticas.
-- 1) Se borran los índices ix_* y se ejecuta EXPLAIN (ANALYZE, BUFFERS) de cada consulta.
-- 2) Se vuelven a crear los índices y se repiten los mismos EXPLAIN.
-- Antes de cada EXPLAIN la consulta se ejecuta una vez sin mostrar el resultado, para que
-- en las dos fases los datos ya estén en memoria y la comparación sea justa.
--
--   docker exec imax_db psql -U imax_owner -d imax -v ON_ERROR_STOP=1 -f /db/analiticas/explain_indices.sql

\set ON_ERROR_STOP on
\pset footer off

-- Parámetros: la función futura con más asientos ocupados (mapa) y la función ya realizada
-- con más boletos vendidos (ocupación y recaudación)
select id_funcion as id_funcion_mapa
from cine.ocupacion_asiento
group by id_funcion
order by count(*) desc, id_funcion
limit 1 \gset

select id_sala as id_sala_mapa from cine.funcion where id_funcion = :id_funcion_mapa \gset

select b.id_funcion as id_funcion
from cine.boleto b
join cine.funcion f on f.id_funcion = b.id_funcion
where f.inicio < now() and b.estado = 'vigente'
group by b.id_funcion
order by count(*) desc, b.id_funcion
limit 1 \gset

\echo 'Función del mapa:' :id_funcion_mapa ' Sala:' :id_sala_mapa ' Función de la ocupación:' :id_funcion

-- Consultas que se miden (las mismas de db/analiticas)
\set q_mapa 'select * from cine.v_mapa_asientos where id_funcion = ' :id_funcion_mapa

\set q_disponibles 'select f.id_funcion, f.inicio, count(a.id_asiento) - count(o.id_asiento) as disponibles from cine.funcion f join cine.zona z on z.id_sala = f.id_sala join cine.asiento a on a.id_zona = z.id_zona and a.es_habilitado left join cine.ocupacion_asiento o on o.id_funcion = f.id_funcion and o.id_asiento = a.id_asiento and (o.estado <> ''bloqueado'' or o.expira_en > now()) where f.id_sala = ' :id_sala_mapa ' and f.estado = ''programada'' and f.inicio between now() and now() + interval ''7 days'' group by f.id_funcion, f.inicio order by f.inicio'

\set q_ocupacion 'select f.id_funcion, cap.capacidad, ven.vendidos, round(100.0 * ven.vendidos / cap.capacidad, 2) as porcentaje, (select coalesce(sum(o.total), 0) from cine.orden o where o.id_funcion = f.id_funcion and o.estado = ''pagada'') as ventas from cine.funcion f cross join lateral (select count(*) as capacidad from cine.asiento a join cine.zona z on z.id_zona = a.id_zona where z.id_sala = f.id_sala and a.es_habilitado) cap cross join lateral (select count(*) as vendidos from cine.boleto b where b.id_funcion = f.id_funcion and b.estado = ''vigente'') ven where f.id_funcion = ' :id_funcion

\set q_top5 'select p.titulo, count(*) as boletos_vendidos from cine.boleto b join cine.funcion f on f.id_funcion = b.id_funcion join cine.pelicula p on p.id_pelicula = f.id_pelicula where b.estado = ''vigente'' and b.emitido_en >= now() - interval ''7 days'' group by p.id_pelicula, p.titulo order by boletos_vendidos desc, p.titulo limit 5'

\set q_metodos 'select m.nombre, count(*) as pagos, round(100.0 * count(*) / sum(count(*)) over (), 2) as porcentaje from cine.pago p join cine.metodo_pago m on m.id_metodo_pago = p.id_metodo_pago where p.estado = ''aprobado'' group by m.id_metodo_pago, m.nombre order by pagos desc'

\set q_auditoria 'select a.id_usuario, count(*) as operaciones, count(*) filter (where a.operacion = ''cortesia'') as cortesias, count(*) filter (where a.operacion like ''reembolso%'') as reembolsos from bitacora.admin_operacion_audit a where a.ocurrido_en >= now() - interval ''1 month'' and a.id_rol = (select id_rol from cine.rol where codigo = ''administrador'') group by a.id_usuario order by operaciones desc'

-- Fase 1: sin índices --------------------------------------------------------------------

\echo ''
\echo '================ ANTES: sin los índices de 05_indices.sql ================'
drop index cine.ix_funcion_inicio, cine.ix_funcion_sala_inicio, cine.ix_sede_ciudad, cine.ix_pelicula_genero_genero,
           cine.ix_ocupacion_expira, cine.ix_orden_funcion, cine.ix_boleto_emitido_en, cine.ix_orden_cliente,
           cine.ix_pago_orden;
drop index bitacora.ix_admin_audit_usuario_fecha, bitacora.ix_acceso_puerta_boleto;
analyze;

\o /dev/null
:q_mapa;
:q_disponibles;
:q_ocupacion;
:q_top5;
:q_metodos;
:q_auditoria;
\o

\echo '--- ANTES: mapa de asientos de una función ---'
explain (analyze, buffers) :q_mapa;
\echo '--- ANTES: asientos libres de las funciones de una sala en los próximos 7 días ---'
explain (analyze, buffers) :q_disponibles;
\echo '--- ANTES: ocupación y recaudación de una función ---'
explain (analyze, buffers) :q_ocupacion;
\echo '--- ANTES: top 5 de la última semana ---'
explain (analyze, buffers) :q_top5;
\echo '--- ANTES: métodos de pago ---'
explain (analyze, buffers) :q_metodos;
\echo '--- ANTES: auditoría del último mes ---'
explain (analyze, buffers) :q_auditoria;

-- Fase 2: con índices --------------------------------------------------------------------

\echo ''
\echo '================ DESPUÉS: con los índices de 05_indices.sql ================'
\ir ../ddl/05_indices.sql
analyze;

\o /dev/null
:q_mapa;
:q_disponibles;
:q_ocupacion;
:q_top5;
:q_metodos;
:q_auditoria;
\o

\echo '--- DESPUÉS: mapa de asientos de una función ---'
explain (analyze, buffers) :q_mapa;
\echo '--- DESPUÉS: asientos libres de las funciones de una sala en los próximos 7 días ---'
explain (analyze, buffers) :q_disponibles;
\echo '--- DESPUÉS: ocupación y recaudación de una función ---'
explain (analyze, buffers) :q_ocupacion;
\echo '--- DESPUÉS: top 5 de la última semana ---'
explain (analyze, buffers) :q_top5;
\echo '--- DESPUÉS: métodos de pago ---'
explain (analyze, buffers) :q_metodos;
\echo '--- DESPUÉS: auditoría del último mes ---'
explain (analyze, buffers) :q_auditoria;

\echo ''
\echo 'Índices ix_* presentes al terminar:'
select schemaname, count(*) as indices from pg_indexes
where indexname like 'ix\_%' and schemaname in ('cine', 'bitacora') and tablename not like '%\_20%' and tablename not like '%\_default'
group by schemaname order by schemaname;
