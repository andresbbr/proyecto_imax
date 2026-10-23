-- 02_tablas_catalogo.sql
-- Ubicación, salas y asientos, catálogo de películas, programación de funciones,
-- precios, promociones y parámetros del sistema.

-- Ubicación ------------------------------------------------------------------

create table cine.pais (
    id_pais       smallint generated always as identity primary key,
    codigo_iso    char(2)      not null constraint uq_pais_codigo_iso unique,
    nombre        text         not null constraint uq_pais_nombre unique,
    tasa_impuesto numeric(5,4) not null constraint ck_pais_tasa_impuesto check (tasa_impuesto between 0 and 1)
);

create table cine.ciudad (
    id_ciudad integer generated always as identity primary key,
    id_pais   smallint not null references cine.pais,
    nombre    text     not null,
    constraint uq_ciudad_pais_nombre unique (id_pais, nombre)
);

create table cine.sede (
    id_sede   integer generated always as identity primary key,
    id_ciudad integer not null references cine.ciudad,
    nombre    text    not null constraint uq_sede_nombre unique,
    direccion text    not null,
    es_activa boolean not null default true
);

-- Salas y asientos -------------------------------------------------------------

create table cine.sala (
    id_sala   integer generated always as identity primary key,
    id_sede   integer not null references cine.sede,
    nombre    text    not null,
    formato   text    not null,
    es_activa boolean not null default true,
    constraint uq_sala_sede_nombre unique (id_sede, nombre)
);

create table cine.tipo_zona (
    id_tipo_zona smallint generated always as identity primary key,
    codigo       text not null constraint uq_tipo_zona_codigo unique,
    nombre       text not null
);

create table cine.zona (
    id_zona      integer generated always as identity primary key,
    id_sala      integer  not null references cine.sala,
    id_tipo_zona smallint not null references cine.tipo_zona,
    nombre       text     not null,
    constraint uq_zona_sala_nombre unique (id_sala, nombre)
);

create table cine.asiento (
    id_asiento    integer generated always as identity primary key,
    id_zona       integer  not null references cine.zona,
    fila          text     not null,
    numero        smallint not null constraint ck_asiento_numero check (numero > 0),
    es_habilitado boolean  not null default true,
    constraint uq_asiento_zona_fila_numero unique (id_zona, fila, numero)
);

create table cine.puerta (
    id_puerta integer generated always as identity primary key,
    id_sala   integer not null references cine.sala,
    codigo    text    not null constraint uq_puerta_codigo unique,
    tipo      text    not null constraint ck_puerta_tipo check (tipo in ('totem', 'manual')),
    es_activa boolean not null default true
);

-- Catálogo (RN-02: título, sinopsis, clasificación y duración obligatorios) ----

create table cine.clasificacion (
    id_clasificacion smallint generated always as identity primary key,
    codigo           text     not null constraint uq_clasificacion_codigo unique,
    descripcion      text     not null,
    edad_minima      smallint not null constraint ck_clasificacion_edad check (edad_minima >= 0)
);

create table cine.genero (
    id_genero smallint generated always as identity primary key,
    nombre    text not null constraint uq_genero_nombre unique
);

create table cine.pelicula (
    id_pelicula      integer generated always as identity primary key,
    id_clasificacion smallint not null references cine.clasificacion,
    titulo           text     not null,
    sinopsis         text     not null,
    duracion_min     smallint not null constraint ck_pelicula_duracion check (duracion_min > 0),
    poster_url       text     not null,
    fecha_estreno    date     not null,
    es_activa        boolean  not null default true,
    constraint uq_pelicula_titulo_estreno unique (titulo, fecha_estreno)
);

create table cine.pelicula_genero (
    id_pelicula integer  not null references cine.pelicula on delete cascade,
    id_genero   smallint not null references cine.genero,
    primary key (id_pelicula, id_genero)
);

-- Programación -------------------------------------------------------------------
-- El no traslape de funciones en la misma sala lo valida un trigger (db/funciones).

create table cine.funcion (
    id_funcion  bigint generated always as identity primary key,
    id_pelicula integer     not null references cine.pelicula,
    id_sala     integer     not null references cine.sala,
    inicio      timestamptz not null,
    fin         timestamptz not null,
    idioma      text        not null,
    estado      text        not null default 'programada'
                constraint ck_funcion_estado check (estado in ('programada', 'cancelada')),
    creado_en   timestamptz not null default now(),
    constraint ck_funcion_horario check (fin > inicio)
);

-- Precios y promociones ----------------------------------------------------------

create table cine.tipo_tarifa (
    id_tipo_tarifa                smallint generated always as identity primary key,
    codigo                        text    not null constraint uq_tipo_tarifa_codigo unique,
    nombre                        text    not null,
    requiere_validacion_documento boolean not null default false,  -- RN-06
    es_cortesia                   boolean not null default false
);

create table cine.tarifa (
    id_tarifa      integer generated always as identity primary key,
    id_sede        integer       not null references cine.sede,
    id_tipo_zona   smallint      not null references cine.tipo_zona,
    id_tipo_tarifa smallint      not null references cine.tipo_tarifa,
    tipo_dia       text          not null
                   constraint ck_tarifa_tipo_dia check (tipo_dia in ('entre_semana', 'fin_de_semana')),
    precio         numeric(12,2) not null constraint ck_tarifa_precio check (precio >= 0),
    constraint uq_tarifa_combinacion unique (id_sede, id_tipo_zona, id_tipo_tarifa, tipo_dia)
);

create table cine.promocion (
    id_promocion   integer generated always as identity primary key,
    codigo         text     not null constraint uq_promocion_codigo unique,
    nombre         text     not null,
    tipo           text     not null constraint ck_promocion_tipo check (tipo in ('2x1', 'porcentaje')),
    porcentaje     numeric(5,2),
    id_tipo_tarifa smallint references cine.tipo_tarifa,  -- nulo: cualquier tipo de tarifa
    dia_semana     smallint constraint ck_promocion_dia check (dia_semana between 1 and 7),  -- 1 = lunes; nulo: cualquier día
    vigente_desde  date     not null,
    vigente_hasta  date     not null,
    es_activa      boolean  not null default true,
    constraint ck_promocion_porcentaje check (
        (tipo = 'porcentaje' and porcentaje between 0 and 100) or (tipo = '2x1' and porcentaje is null)),
    constraint ck_promocion_vigencia check (vigente_hasta >= vigente_desde)
);

-- Parámetros configurables de las reglas de negocio (RN-04, RN-05, RN-16, RN-19) --

create table cine.parametro_sistema (
    clave       text    primary key,
    valor       numeric not null,
    unidad      text    not null,
    descripcion text    not null
);
