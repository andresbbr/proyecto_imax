-- 03_tablas_venta.sql
-- Usuarios y roles, órdenes, inventario de asientos, pagos, boletos, check-in y reembolsos.

-- Seguridad (RN-17) ----------------------------------------------------------------

create table cine.rol (
    id_rol smallint generated always as identity primary key,
    codigo text not null constraint uq_rol_codigo unique
           constraint ck_rol_codigo check (codigo in ('cliente', 'taquillero', 'operador_puerta', 'contador', 'administrador')),
    nombre text not null
);

create table cine.usuario (
    id_usuario      bigint generated always as identity primary key,
    id_rol          smallint    not null references cine.rol,
    id_sede         integer     references cine.sede,  -- solo taquilleros y operadores de puerta
    email           text        not null constraint uq_usuario_email unique
                                constraint ck_usuario_email check (email like '%_@_%'),
    contrasena_hash text        not null,
    nombre          text        not null,
    apellidos       text        not null,
    creado_en       timestamptz not null default now(),
    es_activo       boolean     not null default true
);

-- Venta ----------------------------------------------------------------------------

create table cine.orden (
    id_orden            bigint generated always as identity primary key,
    id_funcion          bigint        not null references cine.funcion,
    canal               text          not null constraint ck_orden_canal check (canal in ('en_linea', 'taquilla')),
    id_usuario_cliente  bigint        references cine.usuario,
    id_usuario_vendedor bigint        references cine.usuario,
    estado              text          not null default 'pendiente'
                        constraint ck_orden_estado check (estado in ('pendiente', 'pagada', 'rechazada', 'expirada', 'cancelada')),
    subtotal            numeric(12,2) not null default 0,
    descuento           numeric(12,2) not null default 0,
    cargo_servicio      numeric(12,2) not null default 0,
    impuesto            numeric(12,2) not null default 0,
    total               numeric(12,2) not null default 0,
    creado_en           timestamptz   not null default now(),
    pagada_en           timestamptz,
    constraint ck_orden_responsable check (
        (canal = 'en_linea' and id_usuario_cliente is not null) or
        (canal = 'taquilla' and id_usuario_vendedor is not null)),
    constraint ck_orden_montos check (subtotal >= 0 and descuento >= 0 and cargo_servicio >= 0 and impuesto >= 0),
    constraint ck_orden_descuento check (descuento <= subtotal),
    -- RN-08: el total es la suma de tarifas menos descuentos más cargos e impuesto
    constraint ck_orden_total_coherente check (total = subtotal - descuento + cargo_servicio + impuesto),
    constraint ck_orden_pagada check (estado <> 'pagada' or pagada_en is not null)
);

create table cine.orden_detalle (
    id_orden        bigint        not null references cine.orden,
    id_asiento      integer       not null references cine.asiento,
    id_tipo_tarifa  smallint      not null references cine.tipo_tarifa,
    id_promocion    integer       references cine.promocion,
    precio_unitario numeric(12,2) not null constraint ck_orden_detalle_precio check (precio_unitario >= 0),
    descuento       numeric(12,2) not null default 0,
    primary key (id_orden, id_asiento),
    constraint ck_orden_detalle_descuento check (descuento between 0 and precio_unitario)
);

-- Inventario de asientos por función. La PK (id_funcion, id_asiento) impide que dos
-- transacciones bloqueen o vendan el mismo asiento de la misma función (RN-05, RN-12).
create table cine.ocupacion_asiento (
    id_funcion bigint      not null references cine.funcion,
    id_asiento integer     not null references cine.asiento,
    id_orden   bigint      references cine.orden,  -- nulo en reservas administrativas
    id_usuario bigint      not null references cine.usuario,
    estado     text        not null
               constraint ck_ocupacion_estado check (estado in ('bloqueado', 'reservado', 'vendido')),
    creado_en  timestamptz not null default now(),
    expira_en  timestamptz,
    primary key (id_funcion, id_asiento),
    constraint ck_ocupacion_expiracion check ((estado = 'bloqueado') = (expira_en is not null)),
    constraint ck_ocupacion_orden check (estado = 'reservado' or id_orden is not null)
);

-- Pago (RN-09: solo token, últimos 4 dígitos y marca; nunca el número completo ni el CVV) --

create table cine.metodo_pago (
    id_metodo_pago smallint generated always as identity primary key,
    codigo         text    not null constraint uq_metodo_pago_codigo unique,
    nombre         text    not null,
    es_tarjeta     boolean not null
);

create table cine.pago (
    id_pago             bigint generated always as identity primary key,
    id_orden            bigint        not null references cine.orden,
    id_metodo_pago      smallint      not null references cine.metodo_pago,
    monto               numeric(12,2) not null constraint ck_pago_monto check (monto > 0),
    estado              text          not null constraint ck_pago_estado check (estado in ('aprobado', 'rechazado')),
    token_pasarela      text,
    codigo_autorizacion text,
    motivo_rechazo      text,
    ultimos4            char(4)       constraint ck_pago_ultimos4 check (ultimos4 ~ '^[0-9]{4}$'),
    marca               text          constraint ck_pago_marca check (marca in ('visa', 'mastercard', 'amex', 'otra')),
    solicitado_en       timestamptz   not null default now(),
    respondido_en       timestamptz   not null default now(),
    constraint ck_pago_aprobado check (estado <> 'aprobado' or codigo_autorizacion is not null),
    constraint ck_pago_rechazado check (estado <> 'rechazado' or motivo_rechazo is not null),
    constraint ck_pago_tarjeta check ((ultimos4 is null) = (marca is null)),
    constraint ck_pago_tiempos check (respondido_en >= solicitado_en)
);

-- Una orden tiene como máximo un pago aprobado
create unique index uq_pago_orden_aprobado on cine.pago (id_orden) where estado = 'aprobado';

-- Emisión y acceso -------------------------------------------------------------------

create table cine.boleto (
    id_boleto  bigint generated always as identity primary key,
    id_orden   bigint      not null,
    id_asiento integer     not null,
    id_funcion bigint      not null references cine.funcion,  -- se copia de la orden para el índice único parcial
    codigo_qr  text        not null constraint uq_boleto_codigo_qr unique,  -- RN-12
    estado     text        not null default 'vigente' constraint ck_boleto_estado check (estado in ('vigente', 'anulado')),
    emitido_en timestamptz not null default now(),
    constraint uq_boleto_orden_asiento unique (id_orden, id_asiento),
    -- on update cascade: un cambio manual de asiento en la línea de la orden se refleja en el boleto
    foreign key (id_orden, id_asiento) references cine.orden_detalle on update cascade
);

-- Segunda barrera contra la doble venta: un solo boleto vigente por asiento y función
create unique index uq_boleto_funcion_asiento_vigente on cine.boleto (id_funcion, id_asiento) where estado = 'vigente';

-- La PK impide que un boleto ingrese dos veces (RN-14)
create table cine.checkin (
    id_boleto           bigint      primary key references cine.boleto,
    id_puerta           integer     not null references cine.puerta,
    id_usuario_operador bigint      references cine.usuario,  -- nulo si lo validó un tótem
    validado_en         timestamptz not null default now()
);

create table cine.reembolso (
    id_reembolso        bigint generated always as identity primary key,
    id_boleto           bigint        not null references cine.boleto constraint uq_reembolso_boleto unique,
    id_pago             bigint        not null references cine.pago,
    id_usuario_autoriza bigint        not null references cine.usuario,
    tipo                text          not null
                        constraint ck_reembolso_tipo check (tipo in ('politica', 'forzado', 'cancelacion_funcion')),
    monto               numeric(12,2) not null constraint ck_reembolso_monto check (monto > 0),
    motivo              text          not null,
    creado_en           timestamptz   not null default now()
);
