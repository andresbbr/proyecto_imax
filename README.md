# Licitación para el Ecosistema Digital de Cines IMAX

Proyecto 2 del curso de Bases de Datos (TEC, ATI). Propuesta técnica y su implementación: rechazo de la infraestructura legada, dimensionamiento, diseño e implementación de la base de datos de venta de entradas (cartelera, bloqueo de asientos, pagos simulados, QR, control de acceso en puerta, panel de administración y auditoría a 5 años).

## Requisitos

- Docker Desktop con Docker Compose v2 o superior.
- Git.
- Python 3.14 (scripts de concurrencia y backend).

## Levantar la base de datos

En PowerShell, desde la raíz del repositorio:

```powershell
Copy-Item .env.example .env      # luego editar POSTGRES_PASSWORD en .env
docker compose up -d
docker compose ps                # imax_db debe aparecer como (healthy)
```

En Git Bash el primer paso es `cp .env.example .env`.

Comprobar la versión:

```powershell
docker exec imax_db psql -U imax_owner -d imax -c "select version();"
```

Conexión desde el host (DBeaver, pgAdmin, `psql`): `localhost:5433`, base `imax`, usuario `imax_owner`, contraseña la del `.env`.

### Crear las tablas

La carpeta `db/` está montada en solo lectura dentro del contenedor en `/db`. El script `db/init.sql` crea los esquemas, las tablas, las bitácoras particionadas, los índices, los roles y los datos base. Se puede ejecutar las veces que se quiera: cada vez vuelve a crear todo desde cero.

```powershell
docker exec imax_db psql -U imax_owner -d imax -v ON_ERROR_STOP=1 -f /db/init.sql
```

### Cargar los datos de prueba

Carga los datos de demostración y la carga masiva (millones de filas; tarda varios minutos):

```powershell
docker exec imax_db psql -U imax_owner -d imax -v ON_ERROR_STOP=1 -f /db/seed/cargar.sql
```

Para una carga más chica: `-v salas=20 -v dias=30`. Solo la demostración: `-f /db/seed/01_datos_demo.sql`.

Usuarios de demostración (contraseña de prueba `imax2026`):

| Usuario | Rol |
|---|---|
| `cliente@imax.demo`, `cliente2@imax.demo` | Cliente |
| `taquilla@imax.demo` | Taquillero (IMAX San José) |
| `puerta@imax.demo` | Operador de puerta (IMAX San José) |
| `contador@imax.demo` | Contador |
| `admin@imax.demo` | Administrador |

En el pago simulado, una tarjeta que termina en `0002` es rechazada.

### Pruebas

```powershell
docker exec imax_db psql -U imax_owner -d imax -v ON_ERROR_STOP=1 -f /db/tests/01_restricciones.sql
docker exec imax_db psql -U imax_owner -d imax -v ON_ERROR_STOP=1 -f /db/tests/02_reglas.sql
```

La primera prueba las restricciones y los permisos; la segunda, las reglas de negocio RN-01 a RN-20. Las dos corren dentro de una transacción que se revierte al final, así que no dejan datos.

### Reiniciar desde cero

Borra el volumen con los datos y vuelve a crear la base vacía:

```powershell
docker compose down -v
docker compose up -d
```

## Estructura del repositorio

| Ruta | Contenido |
|---|---|
| `docker-compose.yml` | PostgreSQL 16.15, puerto 5433 del host, volumen `imax_pgdata`, healthcheck |
| `.env.example` | Variables de entorno de ejemplo (el `.env` real no se versiona) |
| `docs/` | Documento técnico, diagramas, cálculos y evidencias de pruebas |
| `docs/trazabilidad_rn.md` | Matriz RN-01..RN-20, roles y bitácoras |
| `docs/convenciones.md` | Convención de nombres y estilo |
| `db/` | Scripts SQL: DDL, funciones, datos de prueba, pruebas y consultas analíticas |
| `app/` | Backend (FastAPI) y GUI |
| `scripts/` | Pruebas de concurrencia y utilidades |

## Convención de commits

`tipo(ámbito): descripción en español`, con los tipos `feat`, `fix`, `docs`, `test`, `db`, `chore`, `refactor`. Detalle en [docs/convenciones.md](docs/convenciones.md).

## Seguridad

Nunca se versionan secretos ni datos personales, y ninguna tabla, log, seed o documento guarda el número completo de tarjeta ni el CVV (RN-09): solo un token simulado, los últimos 4 dígitos y la marca.
