-- 01_datos_demo.sql
-- Datos pequeños para la demostración: 6 sedes con una sala IMAX cada una (más una segunda sala en San José), 12 películas,
-- la matriz de tarifas, 2 promociones, funciones para los próximos 14 días y un usuario
-- por cada rol. Las fechas son relativas al día de la carga.
--
-- Usuarios de demostración (contraseña de prueba: imax2026):
--   cliente@imax.demo, cliente2@imax.demo, taquilla@imax.demo, puerta@imax.demo,
--   contador@imax.demo, admin@imax.demo

\set hash_demo 'pbkdf2_sha256$260000$imaxdemo2026sal$VYdRQY73NsQsJ7CWLqU3hImyoL6zBmIbZhHm++Dhrsk='

-- Ubicación ---------------------------------------------------------------------------

insert into cine.pais (codigo_iso, nombre, tasa_impuesto) values
    ('CR', 'Costa Rica',      0.13),
    ('MX', 'México',          0.16),
    ('US', 'Estados Unidos',  0.08),
    ('ES', 'España',          0.21);

insert into cine.ciudad (id_pais, nombre)
select p.id_pais, c.nombre
from (values ('CR', 'San José'), ('MX', 'Ciudad de México'), ('MX', 'Guadalajara'),
             ('US', 'Los Ángeles'), ('US', 'Nueva York'), ('ES', 'Madrid')) as c (pais, nombre)
join cine.pais p on p.codigo_iso = c.pais;

insert into cine.sede (id_ciudad, nombre, direccion)
select ci.id_ciudad, s.nombre, s.direccion
from (values
    ('San José',         'IMAX San José',         'Avenida Central, calle 5'),
    ('Ciudad de México', 'IMAX Ciudad de México', 'Paseo de la Reforma 222'),
    ('Guadalajara',      'IMAX Guadalajara',      'Avenida Vallarta 3959'),
    ('Los Ángeles',      'IMAX Los Ángeles',      '6801 Hollywood Blvd'),
    ('Nueva York',       'IMAX Nueva York',       '1998 Broadway'),
    ('Madrid',           'IMAX Madrid',           'Calle de Alcalá 45')
) as s (ciudad, nombre, direccion)
join cine.ciudad ci on ci.nombre = s.ciudad;

-- Una sala por sede: 10 filas de 20 asientos (A-D general, E-H preferencial, I-J VIP)
insert into cine.sala (id_sede, nombre, formato)
select id_sede, 'Sala IMAX 1', 'IMAX con láser' from cine.sede;

-- Segunda sala en San José, sin funciones programadas: en la demostración el administrador
-- crea ahí una función que empiece en pocos minutos para mostrar la validación en puerta.
insert into cine.sala (id_sede, nombre, formato)
select id_sede, 'Sala IMAX 2', 'IMAX digital' from cine.sede where nombre = 'IMAX San José';

insert into cine.zona (id_sala, id_tipo_zona, nombre)
select s.id_sala, tz.id_tipo_zona, tz.nombre
from cine.sala s
cross join cine.tipo_zona tz;

insert into cine.asiento (id_zona, fila, numero)
select z.id_zona, f.fila, n
from cine.zona z
join cine.tipo_zona tz on tz.id_tipo_zona = z.id_tipo_zona
join (values ('A', 'general'), ('B', 'general'), ('C', 'general'), ('D', 'general'),
             ('E', 'preferencial'), ('F', 'preferencial'), ('G', 'preferencial'), ('H', 'preferencial'),
             ('I', 'vip'), ('J', 'vip')) as f (fila, tipo) on f.tipo = tz.codigo
cross join generate_series(1, 20) as n;

insert into cine.puerta (id_sala, codigo, tipo)
select s.id_sala, 'P-' || s.id_sala || '-1', 'totem' from cine.sala s;

-- Catálogo ----------------------------------------------------------------------------

insert into cine.pelicula (id_clasificacion, titulo, sinopsis, duracion_min, poster_url, fecha_estreno)
select c.id_clasificacion, p.titulo, p.sinopsis, p.duracion, p.poster, current_date - p.dias
from (values
    ('Horizonte de Marte',   'Una tripulación debe sobrevivir a una tormenta de arena en el primer asentamiento humano en Marte.', 148, '+12', 'horizonte-de-marte.jpg', 20),
    ('La última órbita',     'Una astronauta queda sola en una estación espacial y tiene 48 horas para volver a la Tierra.',        132, '+12', 'la-ultima-orbita.jpg', 35),
    ('Bosque de cristal',    'Dos hermanos descubren un bosque mágico donde los árboles guardan los recuerdos del pueblo.',        98,  'TP',  'bosque-de-cristal.jpg', 10),
    ('Ruta en llamas',       'Un piloto retirado acepta un último trabajo: cruzar el desierto con un cargamento que todos buscan.', 125, '+15', 'ruta-en-llamas.jpg', 5),
    ('Océanos profundos',    'Documental filmado a cuatro mil metros de profundidad sobre las especies que nunca ven la luz.',      95,  'TP',  'oceanos-profundos.jpg', 60),
    ('El guardián del faro', 'Un farero aislado empieza a recibir mensajes de un barco que naufragó hace cien años.',               118, '+15', 'el-guardian-del-faro.jpg', 15),
    ('Noche de risas',       'Un grupo de amigos intenta salvar el último club de comedia de la ciudad en una sola noche.',          104, '+12', 'noche-de-risas.jpg', 25),
    ('Ecos del pasado',      'Una pianista vuelve a su ciudad natal y enfrenta la historia que la obligó a irse.',                   127, '+12', 'ecos-del-pasado.jpg', 45),
    ('Dragones de hielo',    'En un reino congelado, una joven domadora debe unir a los últimos dragones antes del invierno eterno.', 156, 'TP',  'dragones-de-hielo.jpg', 3),
    ('La casa del fondo',    'Una familia se muda a una casa donde cada noche aparece una puerta nueva.',                            109, '+18', 'la-casa-del-fondo.jpg', 12),
    ('Galaxia perdida',      'Una nave de exploración encuentra una señal en una galaxia que no aparece en ningún mapa.',            162, '+12', 'galaxia-perdida.jpg', 1),
    ('Aventura en la selva', 'Una bióloga y su hija se pierden en el Amazonas siguiendo la pista de un animal que se creía extinto.', 112, 'TP',  'aventura-en-la-selva.jpg', 30)
) as p (titulo, sinopsis, duracion, clasificacion, poster, dias)
join cine.clasificacion c on c.codigo = p.clasificacion;

insert into cine.pelicula_genero (id_pelicula, id_genero)
select p.id_pelicula, g.id_genero
from (values
    ('Horizonte de Marte', 'Ciencia ficción'), ('Horizonte de Marte', 'Aventura'),
    ('La última órbita', 'Ciencia ficción'), ('La última órbita', 'Drama'),
    ('Bosque de cristal', 'Animación'), ('Bosque de cristal', 'Fantasía'),
    ('Ruta en llamas', 'Acción'),
    ('Océanos profundos', 'Documental'),
    ('El guardián del faro', 'Suspenso'), ('El guardián del faro', 'Drama'),
    ('Noche de risas', 'Comedia'),
    ('Ecos del pasado', 'Drama'),
    ('Dragones de hielo', 'Animación'), ('Dragones de hielo', 'Fantasía'), ('Dragones de hielo', 'Aventura'),
    ('La casa del fondo', 'Terror'),
    ('Galaxia perdida', 'Ciencia ficción'), ('Galaxia perdida', 'Acción'),
    ('Aventura en la selva', 'Aventura')
) as x (titulo, genero)
join cine.pelicula p on p.titulo = x.titulo
join cine.genero g on g.nombre = x.genero;

-- Precios ------------------------------------------------------------------------------
-- Precio base del adulto en zona general por país; multiplicadores por zona, tipo de
-- entrada y fin de semana. La cortesía no lleva tarifa: siempre vale 0.

insert into cine.tarifa (id_sede, id_tipo_zona, id_tipo_tarifa, tipo_dia, precio)
select se.id_sede, tz.id_tipo_zona, tt.id_tipo_tarifa, d.tipo_dia,
       round(b.base
             * case tz.codigo when 'general' then 1 when 'preferencial' then 1.25 else 1.6 end
             * case tt.codigo when 'adulto' then 1 when 'nino' then 0.7 when 'tercera_edad' then 0.6 else 0.8 end
             * case d.tipo_dia when 'fin_de_semana' then 1.15 else 1 end, 2)
from cine.sede se
join cine.ciudad ci on ci.id_ciudad = se.id_ciudad
join cine.pais pa on pa.id_pais = ci.id_pais
join (values ('CR', 8.00), ('MX', 7.00), ('US', 18.00), ('ES', 12.00)) as b (pais, base) on b.pais = pa.codigo_iso
cross join cine.tipo_zona tz
cross join cine.tipo_tarifa tt
cross join (values ('entre_semana'), ('fin_de_semana')) as d (tipo_dia)
where not tt.es_cortesia;

insert into cine.promocion (codigo, nombre, tipo, porcentaje, id_tipo_tarifa, dia_semana, vigente_desde, vigente_hasta)
values
    ('MARTES2X1', '2x1 en entradas de adulto los martes', '2x1', null,
     (select id_tipo_tarifa from cine.tipo_tarifa where codigo = 'adulto'), 2, '2025-11-01', '2027-12-31'),
    ('ESTUDIANTE20', '20 % de descuento para estudiantes los miércoles', 'porcentaje', 20,
     (select id_tipo_tarifa from cine.tipo_tarifa where codigo = 'estudiante'), 3, '2025-11-01', '2027-12-31');

-- Funciones de los próximos 14 días: 4 por sala y día (13:00, 16:00, 19:00 y 22:00, hora
-- de Costa Rica), con 15 minutos de limpieza al final.

insert into cine.funcion (id_pelicula, id_sala, inicio, fin, idioma)
select p.id_pelicula, s.id_sala, h.inicio,
       h.inicio + make_interval(mins => p.duracion_min + cine.parametro('minutos_limpieza')::int),
       case when (s.id_sala + h.n) % 3 = 0 then 'Doblada' else 'Original subtitulada' end
from cine.sala s
cross join lateral (
    select ((current_date + d) || ' ' || hora || ' -06')::timestamptz as inicio,
           row_number() over (order by d, hora) as n
    from generate_series(0, 13) as d
    cross join unnest(array['13:00', '16:00', '19:00', '22:00']) as hora
) as h
join cine.pelicula p on p.id_pelicula = (select min(id_pelicula) from cine.pelicula)
                                         + ((s.id_sala * 5 + h.n) % (select count(*) from cine.pelicula))
where h.inicio > now()
  and s.nombre = 'Sala IMAX 1';

-- Usuarios de demostración, uno por rol ---------------------------------------------

insert into cine.usuario (id_rol, id_sede, email, contrasena_hash, nombre, apellidos)
select r.id_rol, se.id_sede, u.email, :'hash_demo', u.nombre, u.apellidos
from (values
    ('cliente',         null,            'cliente@imax.demo',  'Ana',    'Rojas'),
    ('cliente',         null,            'cliente2@imax.demo', 'Bruno',  'Mora'),
    ('taquillero',      'IMAX San José', 'taquilla@imax.demo', 'Carla',  'Vargas'),
    ('operador_puerta', 'IMAX San José', 'puerta@imax.demo',   'Diego',  'Solís'),
    ('contador',        null,            'contador@imax.demo', 'Elena',  'Castro'),
    ('administrador',   null,            'admin@imax.demo',    'Fabián', 'Jiménez')
) as u (rol, sede, email, nombre, apellidos)
join cine.rol r on r.codigo = u.rol
left join cine.sede se on se.nombre = u.sede;
