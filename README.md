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

### Ejecutar scripts SQL

La carpeta `db/` está montada en solo lectura dentro del contenedor en `/db`:

```powershell
docker exec imax_db psql -U imax_owner -d imax -v ON_ERROR_STOP=1 -f /db/ddl/01_schema.sql
```

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
