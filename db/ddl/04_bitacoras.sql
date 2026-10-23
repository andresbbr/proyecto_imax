-- 04_bitacoras.sql
-- Las 4 bitácoras con retención de 5 años (RN-20). Son append-only: ningún rol de la
-- aplicación tiene UPDATE ni DELETE sobre ellas (ver 06_roles.sql).
-- Se particionan por mes sobre ocurrido_en. La columna de partición forma parte de la PK.
-- No tienen FK hacia las tablas de cine para que el registro sobreviva aunque la fila
-- original se anule o se purgue.
-- PostgreSQL 16 no admite columnas identity en tablas particionadas, por eso id es bigserial.

create table bitacora.transaccion_log (
    id          bigserial,
    ocurrido_en timestamptz   not null default now(),
    id_orden    bigint        not null,
    id_pago     bigint,
    id_boleto   bigint,
    evento      text          not null constraint ck_transaccion_log_evento check (evento in (
                    'orden_creada', 'pago_solicitado', 'pago_aprobado', 'pago_rechazado', 'boletos_emitidos', 'reembolso')),
    monto       numeric(12,2),
    impuesto    numeric(12,2),
    detalle     jsonb,
    primary key (id, ocurrido_en)
) partition by range (ocurrido_en);

create table bitacora.asiento_auditoria_log (
    id          bigserial,
    ocurrido_en timestamptz not null default now(),
    id_funcion  bigint      not null,
    id_asiento  integer     not null,
    id_orden    bigint,
    id_usuario  bigint,
    evento      text        not null constraint ck_asiento_auditoria_log_evento check (evento in (
                    'bloqueo', 'liberacion_expiracion', 'liberacion_rechazo', 'liberacion_usuario',
                    'liberacion_reembolso', 'compra', 'reserva', 'colision')),
    detalle     jsonb,
    primary key (id, ocurrido_en)
) partition by range (ocurrido_en);

create table bitacora.acceso_puerta_log (
    id                  bigserial,
    ocurrido_en         timestamptz not null default now(),
    codigo_qr_leido     text        not null,
    id_boleto           bigint,
    id_puerta           integer     not null,
    id_funcion_en_curso bigint,
    id_usuario_operador bigint,
    resultado           text        not null constraint ck_acceso_puerta_log_resultado check (resultado in (
                            'exitoso', 'duplicado', 'otra_funcion', 'fuera_de_horario', 'inexistente', 'anulado',
                            'incidencia_documento')),
    mensaje             text        not null,
    primary key (id, ocurrido_en)
) partition by range (ocurrido_en);

create table bitacora.admin_operacion_audit (
    id                 bigserial,
    ocurrido_en        timestamptz not null default now(),
    id_usuario         bigint      not null,
    id_rol             smallint    not null,
    ip                 inet        not null,
    operacion          text        not null,
    entidad            text        not null,
    id_entidad         text        not null,
    valores_anteriores jsonb,
    valores_nuevos     jsonb,
    motivo             text,
    primary key (id, ocurrido_en)
) partition by range (ocurrido_en);

-- Una partición por mes desde 2025-11 hasta 2027-12, más una partición por defecto
-- para cualquier fecha fuera de ese rango.
do $$
declare
    tabla text;
    mes   date;
begin
    foreach tabla in array array['transaccion_log', 'asiento_auditoria_log', 'acceso_puerta_log', 'admin_operacion_audit'] loop
        for mes in select generate_series(date '2025-11-01', date '2027-12-01', interval '1 month')::date loop
            execute format('create table bitacora.%I partition of bitacora.%I for values from (%L) to (%L)',
                           tabla || '_' || to_char(mes, 'YYYY_MM'), tabla, mes, (mes + interval '1 month')::date);
        end loop;
        execute format('create table bitacora.%I partition of bitacora.%I default', tabla || '_default', tabla);
    end loop;
end $$;
