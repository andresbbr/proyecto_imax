-- 07_datos_base.sql
-- Catálogos fijos y parámetros de las reglas de negocio. Los datos de prueba
-- (sedes, salas, películas, funciones, ventas) están en db/seed.

insert into cine.rol (codigo, nombre) values
    ('cliente',         'Cliente / Espectador'),
    ('taquillero',      'Taquillero'),
    ('operador_puerta', 'Operador de Sala (Puerta)'),
    ('contador',        'Contador'),
    ('administrador',   'Administrador / Gerente');

insert into cine.tipo_zona (codigo, nombre) values
    ('general',      'General'),
    ('preferencial', 'Preferencial'),
    ('vip',          'VIP');

-- RN-06: las tarifas especiales se validan con documento en la puerta
insert into cine.tipo_tarifa (codigo, nombre, requiere_validacion_documento, es_cortesia) values
    ('adulto',       'Adulto',       false, false),
    ('nino',         'Niño',         true,  false),
    ('tercera_edad', 'Tercera edad', true,  false),
    ('estudiante',   'Estudiante',   true,  false),
    ('cortesia',     'Cortesía',     false, true);

insert into cine.clasificacion (codigo, descripcion, edad_minima) values
    ('TP',  'Todo público',         0),
    ('+12', 'Mayores de 12 años',  12),
    ('+15', 'Mayores de 15 años',  15),
    ('+18', 'Mayores de 18 años',  18);

insert into cine.genero (nombre) values
    ('Acción'), ('Animación'), ('Aventura'), ('Ciencia ficción'), ('Comedia'),
    ('Documental'), ('Drama'), ('Fantasía'), ('Suspenso'), ('Terror');

insert into cine.metodo_pago (codigo, nombre, es_tarjeta) values
    ('tarjeta_credito',   'Tarjeta de crédito', true),
    ('tarjeta_debito',    'Tarjeta de débito',  true),
    ('paypal',            'PayPal',             false),
    ('transferencia',     'Transferencia',      false),
    ('billetera_digital', 'Billetera digital',  false);

insert into cine.parametro_sistema (clave, valor, unidad, descripcion) values
    ('max_asientos_por_orden',  6,    'asientos',       'Máximo de asientos por compra (RN-04)'),
    ('minutos_bloqueo',         2,    'minutos',        'Duración del bloqueo temporal de asientos (RN-05)'),
    ('minutos_antes_ingreso',   30,   'minutos',        'Ingreso permitido desde este tiempo antes del inicio (RN-16)'),
    ('minutos_despues_ingreso', 15,   'minutos',        'Ingreso permitido hasta este tiempo después del inicio (RN-16)'),
    ('horas_limite_reembolso',  2,    'horas',          'Reembolso por política hasta este tiempo antes de la función (RN-19)'),
    ('cargo_servicio',          1.50, 'USD por boleto', 'Cargo por servicio en la venta en línea (RN-08)'),
    ('minutos_limpieza',        15,   'minutos',        'Tiempo de limpieza entre funciones de la misma sala');
