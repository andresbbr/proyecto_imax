# Convenciones del proyecto

Aplican a todo el repositorio. No se mezclan idiomas ni estilos.

## 1. Idioma

- Documentación, comentarios, mensajes de la interfaz y mensajes de commit: español.
- Identificadores de SQL y de código: **español sin tildes ni ñ**, en `snake_case`.
  - `anio` en lugar de "año", `contrasena_hash` en lugar de "contraseña", `funcion` en lugar de "función".
- Se usan en inglés solo los términos propios del lenguaje o del framework (`id`, `token`, `hash`, `qr`, `api`, decoradores y clases de FastAPI, etc.).

## 2. Base de datos

### Esquemas

| Esquema | Contenido |
|---|---|
| `cine` | Tablas operativas: catálogo, salas, funciones, tarifas, órdenes, pagos, boletos |
| `bitacora` | Las 4 bitácoras append-only, particionadas por fecha |

### Tablas y columnas

- Nombres de tabla en **singular**: `sala`, `asiento`, `funcion`, `boleto`, `pago`.
- Columnas en `snake_case`.
- Llave primaria: `id_<tabla>` de tipo `bigint generated always as identity` (por ejemplo `id_sala`).
- Llave foránea: el mismo nombre de la PK a la que apunta (`zona.id_sala` apunta a `sala.id_sala`). Si una tabla tiene dos FK a la misma tabla, se agrega un sufijo de rol (`id_usuario_responsable`).
- Booleanos con prefijo `es_`, `tiene_` o `requiere_` (`es_activa`, `requiere_validacion_documento`).
- Marcas de tiempo: siempre `timestamptz`, con el servidor en UTC. Nombres `creado_en`, `actualizado_en`, `expira_en`, `inicio`, `fin`.
- Dinero: `numeric(12,2)`. Nunca `float` ni `money`.
- Textos: `text` con `CHECK` de longitud cuando haga falta; `varchar(n)` solo si el estándar lo fija (por ejemplo `char(4)` para los últimos 4 dígitos de tarjeta).
- Prohibidas las columnas para PAN completo o CVV (RN-09).

### Objetos

| Objeto | Patrón | Ejemplo |
|---|---|---|
| Llave primaria | `pk_<tabla>` | `pk_sala` |
| Llave foránea | `fk_<tabla>_<referida>` | `fk_asiento_sala` |
| Unicidad | `uq_<tabla>_<columnas>` | `uq_boleto_codigo_qr` |
| Check | `ck_<tabla>_<regla>` | `ck_orden_total_coherente` |
| Índice | `ix_<tabla>_<columnas>` | `ix_funcion_inicio` |
| Trigger | `trg_<tabla>_<momento>_<evento>` | `trg_sala_before_update` |
| Función o procedimiento | verbo en infinitivo + objeto | `bloquear_asientos`, `calcular_total`, `validar_entrada` |
| Vista | `v_<nombre>` | `v_cartelera_activa`, `v_mapa_asientos` |
| Partición | `<tabla>_<aaaa>_<mm>` | `transaccion_log_2026_10` |

### Roles de base de datos

- Roles de grupo (`NOLOGIN`), uno por perfil del enunciado:
  `rol_cliente`, `rol_taquillero`, `rol_operador_puerta`, `rol_contador`, `rol_administrador`.
- Usuarios de conexión (`LOGIN`) aparte, miembros de un rol de grupo: `usr_<proposito>` (por ejemplo `usr_app_web`).
- El dueño del esquema (`imax_owner`) solo se usa para migraciones; la aplicación nunca se conecta con él.
- Ningún rol de aplicación tiene `UPDATE` ni `DELETE` sobre las bitácoras.

### Scripts SQL

- Numerados por orden de ejecución: `db/ddl/01_schema.sql`, `02_tablas.sql`, ...
- Idempotentes: `create ... if not exists`, `create or replace`, `drop ... if exists` cuando aplique.
- Palabras clave de SQL en minúscula; un archivo por tema lógico.
- Cada archivo empieza con un comentario que dice qué crea y a qué RN sirve.

## 3. Python (backend y scripts)

- Módulos, funciones y variables en `snake_case` en español; clases en `PascalCase` (`ServicioPago`).
- Sin ORM: las consultas llaman a funciones y vistas de la BD con `psycopg` y parámetros enlazados (nunca concatenar SQL).
- Credenciales solo desde variables de entorno (`.env`).

## 4. Git

- Commits pequeños, un cambio lógico por commit, con el formato `tipo(ámbito): descripción en español`.
- Tipos: `feat`, `fix`, `docs`, `test`, `db`, `chore`, `refactor`.
- Ejemplo: `db(ddl): crear tablas de sala, asiento y funcion`.
- Un tag `etapa-N` al cerrar cada etapa del proyecto.
- Rama principal: `main`.

## 5. Documentos

- Sin raya larga (em dash); se usan comas, punto y coma o dos puntos.
- Cifras siempre con unidad y fuente.
- Evidencias en `docs/evidencias` con fecha y el comando usado en el nombre o en el encabezado del archivo.
