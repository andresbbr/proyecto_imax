# Licitación para el Ecosistema Digital de Cines IMAX

Proyecto 2 del curso de Bases de Datos (TEC, ATI). Propuesta técnica y su implementación: rechazo de la infraestructura legada, dimensionamiento, diseño e implementación de la base de datos de venta de entradas (cartelera, bloqueo de asientos, pagos simulados, QR, control de acceso en puerta, panel de administración y auditoría a 5 años).

## Descargas

En [Releases](https://github.com/andresbbr/proyecto_imax/releases/latest) están los dos entregables:

- `documento_tecnico_imax.docx`: el documento técnico final.
- `proyecto_imax.zip`: el proyecto completo, listo para ejecutar.

## Requisitos

- PostgreSQL 16 instalado (con `psql`, que viene en `C:\Program Files\PostgreSQL\16\bin`).
- Python 3.14.
- Git, solo si se clona el repositorio en lugar de descargar el zip.

## Arranque rápido en Windows

Descomprimir `proyecto_imax.zip` (o clonar el repositorio) y ejecutar en PowerShell, dentro de la carpeta:

```powershell
powershell -ExecutionPolicy Bypass -File iniciar.ps1
```

El script hace lo siguiente:

1. Crea el `.env` a partir de `.env.example` si no existe.
2. La primera vez crea el usuario `imax_owner` y la base `imax`. Para eso pide la contraseña del superusuario `postgres` de la instalación.
3. Crea el esquema y carga los datos de prueba, lo que tarda unos 2 minutos.
4. Instala las dependencias de Python y abre la aplicación en `http://127.0.0.1:8000`.

Las siguientes veces reutiliza la base; con `-Reiniciar` la vuelve a crear desde cero. Si PostgreSQL usa otro puerto o servidor, se cambian `POSTGRES_PORT` y `POSTGRES_HOST` en el `.env`.

Las secciones siguientes muestran los mismos pasos a mano.

## Base de datos paso a paso

En PowerShell, desde la carpeta del proyecto, con `psql` en el PATH. Las variables toman las contraseñas del `.env`:

```powershell
Copy-Item .env.example .env      # cambiar las contraseñas de prueba
$env:POSTGRES_PASSWORD = "<POSTGRES_PASSWORD del .env>"
$env:APP_DB_PASSWORD = "<APP_DB_PASSWORD del .env>"
$env:PGCLIENTENCODING = "UTF8"
psql -U postgres -d postgres -f db/crear_base.sql
```

`db/crear_base.sql` se ejecuta una sola vez, con el superusuario de la instalación. Crea el usuario dueño `imax_owner` y la base `imax` en UTF-8 y con zona horaria UTC.

Conexión desde DBeaver, pgAdmin o `psql`: `localhost:5432`, base `imax`, usuario `imax_owner`, con la contraseña del `.env`.

### Crear las tablas

El script `db/init.sql` crea los esquemas, las tablas, las bitácoras particionadas, los índices, los roles y los datos base. Se puede ejecutar las veces que se quiera: cada vez vuelve a crear todo desde cero.

```powershell
psql -U imax_owner -d imax -v ON_ERROR_STOP=1 -f db/init.sql
```

### Cargar los datos de prueba

Carga los datos de demostración y la carga masiva (millones de filas; tarda unos minutos):

```powershell
psql -U imax_owner -d imax -v ON_ERROR_STOP=1 -f db/seed/cargar.sql
```

Para una carga más chica: `-v salas=20 -v dias=30`. Solo la demostración: `-f db/seed/01_datos_demo.sql`.

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
psql -U imax_owner -d imax -v ON_ERROR_STOP=1 -f db/tests/01_restricciones.sql
psql -U imax_owner -d imax -v ON_ERROR_STOP=1 -f db/tests/02_reglas.sql
```

La primera prueba las restricciones y los permisos; la segunda, las reglas de negocio RN-01 a RN-20. Las dos corren dentro de una transacción que se revierte al final, así que no dejan datos.

### Concurrencia, analíticas y planes de ejecución

La prueba de concurrencia necesita Python con las dependencias de `requirements.txt`:

```powershell
py -m pip install -r requirements.txt
py scripts/concurrencia.py
```

Lanza 25 corridas con 20 y con 50 solicitudes simultáneas por el mismo asiento y verifica que en cada una haya exactamente un ganador.

```powershell
psql -U imax_owner -d imax -v ON_ERROR_STOP=1 -f db/analiticas/ejecutar.sql
psql -U imax_owner -d imax -v ON_ERROR_STOP=1 -f db/analiticas/explain_indices.sql
```

El primero corre las 4 consultas analíticas y sus comprobaciones. El segundo muestra los planes de `EXPLAIN (ANALYZE, BUFFERS)` sin y con los índices, y al final deja los índices creados.

### Aplicación web

Con la base inicializada y los datos cargados:

```powershell
py -m pip install -r requirements.txt
py -m uvicorn app.main:app --port 8000
```

Abrir `http://127.0.0.1:8000` e iniciar sesión con uno de los usuarios de demostración. Cada rol ve solo sus pantallas: cartelera y compra (cliente), taquilla, puerta, reportes (contador) y panel de administración.

Pruebas de la interfaz con Playwright, con la aplicación corriendo:

```powershell
py -m playwright install chromium
py -m pytest app/tests -v
```

El guion de la demostración, paso a paso según la pauta de revisión, está en [docs/documento/11_guia.md](docs/documento/11_guia.md).

### Respaldo y restauración

```powershell
powershell -ExecutionPolicy Bypass -File scripts/respaldo_restauracion.ps1
```

Respalda la base con `pg_dump`, la restaura en una base nueva, compara las filas de las tablas principales y borra la copia (sección 10.6 del documento).

### Reiniciar desde cero

```powershell
powershell -ExecutionPolicy Bypass -File iniciar.ps1 -Reiniciar
```

Vuelve a crear el esquema y a cargar los datos de prueba.

### Sin PostgreSQL instalado

`docker-compose.yml` levanta la misma versión (PostgreSQL 16.15) en Docker, con el usuario y la base ya creados. Hay que poner `POSTGRES_PORT=5433` en el `.env`, ejecutar `docker compose up -d` y después `iniciar.ps1`, que en ese caso necesita igual `psql` en el equipo.

## Documento técnico

El documento final está en [docs/documento/documento_tecnico_imax.docx](docs/documento/documento_tecnico_imax.docx). Sus fuentes son las secciones `docs/documento/01_*.md` a `11_*.md`; después de cambiarlas, se regenera con:

```powershell
py docs/documento/generar_docx.py
```

La correspondencia entre la pauta de revisión, la demostración, las pruebas y las evidencias está en [docs/pauta_revision.md](docs/pauta_revision.md).

## Estructura del repositorio

| Ruta | Contenido |
|---|---|
| `iniciar.ps1` | Arranque completo en Windows con un solo comando |
| `docker-compose.yml` | Opcional: PostgreSQL 16.15 en Docker para un equipo sin PostgreSQL instalado |
| `.env.example` | Variables de entorno de ejemplo (el `.env` real no se versiona) |
| `docs/` | Documento técnico (fuentes y Word), diagramas, cálculos, fuentes de precios y evidencias de pruebas |
| `docs/trazabilidad_rn.md` | Matriz RN-01..RN-20, roles y bitácoras |
| `docs/convenciones.md` | Convención de nombres y estilo |
| `db/` | Scripts SQL: DDL, funciones, datos de prueba, pruebas y consultas analíticas |
| `app/` | Aplicación web: backend FastAPI, plantillas, estilos y pruebas de la interfaz |
| `scripts/` | Prueba de concurrencia y prueba de respaldo y restauración |

## Convención de commits

`tipo(ámbito): descripción en español`, con los tipos `feat`, `fix`, `docs`, `test`, `db`, `chore`, `refactor`. Detalle en [docs/convenciones.md](docs/convenciones.md).

## Seguridad

Nunca se versionan secretos ni datos personales, y ninguna tabla, log, seed o documento guarda el número completo de tarjeta ni el CVV (RN-09): solo un token simulado, los últimos 4 dígitos y la marca.
