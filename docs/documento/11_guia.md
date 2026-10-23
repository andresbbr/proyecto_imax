# 11. Guía de ejecución del repositorio y de la demostración

## 11.1 Puesta en marcha

Requisitos: Docker Desktop, Git y Python 3.14. Todos los comandos se ejecutan en PowerShell desde la raíz del repositorio.

```powershell
Copy-Item .env.example .env      # cambiar las contraseñas de prueba
docker compose up -d             # PostgreSQL 16 en el puerto 5433
docker exec imax_db psql -U imax_owner -d imax -v ON_ERROR_STOP=1 -f /db/init.sql
docker exec imax_db psql -U imax_owner -d imax -v ON_ERROR_STOP=1 -f /db/seed/cargar.sql
py -m pip install -r requirements.txt
py -m uvicorn app.main:app --port 8000
```

La aplicación queda en `http://127.0.0.1:8000`. `init.sql` crea el esquema, las funciones, los roles y el usuario de conexión `imax_app`; `cargar.sql` agrega los datos de demostración y la carga masiva. Para empezar de nuevo: `docker compose down -v` y repetir los pasos.

La aplicación se conecta con `imax_app`, que por sí mismo no tiene permisos. En cada petición cambia al rol de base de datos del usuario que inició sesión (`set local role`), así que la base aplica los permisos aunque la interfaz tuviera un error. En las operaciones de empleados registra el usuario y la IP para la bitácora de auditoría. Cada 60 segundos la aplicación llama a `liberar_bloqueos_expirados()`.

Usuarios de demostración, todos con la contraseña de prueba `imax2026`:

| Usuario | Rol | Pantalla inicial |
|---|---|---|
| `cliente@imax.demo`, `cliente2@imax.demo` | Cliente | Cartelera |
| `taquilla@imax.demo` | Taquillero (IMAX San José) | Taquilla |
| `puerta@imax.demo` | Operador de puerta (IMAX San José) | Puerta |
| `contador@imax.demo` | Contador | Reportes |
| `admin@imax.demo` | Administrador | Panel |

En el pago simulado, una tarjeta que termina en `0002` es rechazada; cualquier otra es aprobada. Del número de tarjeta el navegador solo envía al servidor los últimos 4 dígitos y la marca (RN-09).

## 11.2 Pruebas

| Prueba | Comando | Evidencia |
|---|---|---|
| Restricciones y permisos | `docker exec imax_db psql -U imax_owner -d imax -v ON_ERROR_STOP=1 -f /db/tests/01_restricciones.sql` | `pruebas_restricciones_*.txt` |
| Reglas RN-01 a RN-20 | `docker exec imax_db psql -U imax_owner -d imax -v ON_ERROR_STOP=1 -f /db/tests/02_reglas.sql` | `pruebas_reglas_*.txt` |
| Concurrencia | `py scripts/concurrencia.py` | `concurrencia_*.txt` |
| Analíticas | `docker exec imax_db psql -U imax_owner -d imax -v ON_ERROR_STOP=1 -f /db/analiticas/ejecutar.sql` | `analiticas_*.txt` |
| Planes de ejecución | `docker exec imax_db psql -U imax_owner -d imax -v ON_ERROR_STOP=1 -f /db/analiticas/explain_indices.sql` | `explain_antes_despues_*.txt` |
| Interfaz (con la aplicación corriendo) | `py -m playwright install chromium` y luego `py -m pytest app/tests -v` | `pruebas_gui_*.txt` |

Las pruebas de la interfaz recorren en Chromium los flujos de la sección 11.3: filtros de la cartelera, pago rechazado que libera los asientos, pago aprobado con un QR por asiento, el bloqueo visto desde un segundo navegador, la puerta, el acceso por rol y la auditoría. Programan sus propias funciones en la Sala IMAX 2 y al empezar cancelan las de corridas anteriores.

## 11.3 Guion de la demostración

El guion sigue los 5 puntos de la pauta de revisión. Conviene usar dos ventanas del navegador (una normal y otra privada) para tener dos sesiones a la vez. Duración estimada: 15 minutos.

**Preparación (antes de empezar).** Con la aplicación corriendo, entrar como `admin@imax.demo`, ir a *Funciones* y programar una función en *IMAX San José · Sala IMAX 2* que empiece dentro de 10 minutos. Esa función se usa en el punto 3, porque la puerta solo deja entrar desde 30 minutos antes hasta 15 minutos después del inicio (RN-16).

**1. Cartelera y funciones** (administrador)

1. *Películas*: agregar una película con título, sinopsis, duración, clasificación, póster y géneros. Aparece en el catálogo.
2. *Funciones*: programarla en la Sala IMAX 2 en un horario libre. El fin se calcula con la duración más el tiempo de limpieza.
3. Programar otra función en la misma sala que empiece 30 minutos después: la base la rechaza con "La sala ya tiene una función programada que se traslapa con ese horario".
4. *Precios*: mostrar la matriz de la sede (zona, tipo de entrada, entre semana y fin de semana), cambiar un precio y guardar. Mostrar la tabla de promociones (2x1).

**2. Checkout** (cliente)

1. En la cartelera, filtrar por ubicación *San José*, una fecha y un género.
2. Elegir una función de la Sala IMAX 1 que empiece en más de 2 horas. El mapa muestra los asientos en verde (disponible), gris (ocupado), amarillo (bloqueado por otra persona) y azul (seleccionado).
3. Abrir la misma función en la segunda ventana con `cliente2@imax.demo`. En la primera, elegir 2 asientos y presionar *Bloquear asientos y continuar*: en menos de 2 segundos esos asientos se ven amarillos en la segunda ventana.
4. En la orden aparece el temporizador de 2 minutos y el desglose: tarifas, descuentos (2x1), cargo por servicio, impuesto y total. Cambiar un asiento a la tarifa *Niño* y ver el total recalculado.
5. Pagar con la tarjeta `4000 0000 0000 0002`: el pago se rechaza, vuelve al mapa y los asientos están verdes otra vez. No se generó ningún QR.
6. Repetir con `4242 4242 4242 4242`: el pago se aprueba y la confirmación muestra un boleto con QR por asiento. El mismo boleto aparece en *Mis entradas*.
7. Opcional: dejar una orden sin pagar y esperar 2 minutos; los asientos se liberan solos.
8. Comprar también un boleto para la función de la Sala IMAX 2 preparada al inicio y copiar su código (el texto bajo el QR).

**3. Puerta** (operador, `puerta@imax.demo`)

1. Elegir la puerta de la Sala IMAX 2, pegar el código del boleto de esa función y validar: fondo verde, "Acceso permitido".
2. Validar el mismo código otra vez: fondo rojo, "Entrada ya utilizada".
3. Validar en la misma puerta el código del boleto de la Sala IMAX 1: "La entrada es de otra función o sala".
4. Elegir la puerta de la Sala IMAX 1 y validar ese mismo boleto: "Fuera del horario de ingreso", porque la función empieza en más de 30 minutos.
5. Si la entrada es de una tarifa especial (niño, estudiante, tercera edad), el mensaje pide validar el documento y aparece el botón para registrar una incidencia.

**4. Finanzas y analíticas** (contador, `contador@imax.demo`)

1. *Reportes* muestra las 4 consultas de `db/analiticas`: ocupación y recaudación de una función (se puede cambiar el número de función), top 5 de la última semana y métodos de pago. La cuarta (auditoría por administrador) solo la ve el administrador.
2. Mostrar en la terminal los planes de `explain_indices.sql` o la evidencia `docs/evidencias/explain_antes_despues_2026-10-23.txt`: antes un Seq Scan y después un Index Scan o Bitmap Index Scan, con menos tiempo (sección 8.2).

**5. Administración y auditoría**

1. Entrar como `taquilla@imax.demo` y escribir en la barra de direcciones `/admin/precios` y `/admin/salas`: la respuesta es 403, "Su rol no tiene acceso a esta sección". Lo mismo con `cliente@imax.demo`.
2. Como administrador, en *Salas*, intentar desactivar la Sala IMAX 1: se rechaza porque tiene entradas vendidas (RN-18).
3. En *Boletos*, buscar por su código el boleto de la Sala IMAX 1 comprado en el punto 2: cambiarlo de asiento y después anularlo con *Reembolso forzado*. El asiento vuelve a quedar libre. Otorgar una cortesía a `cliente2@imax.demo`.
4. *Auditoría* muestra cada operación manual (alta de película y de función, cambio de precio, cambio de asiento, reembolso forzado, cortesía) con fecha y hora, responsable, rol, IP, valores anteriores y nuevos y motivo. Se puede filtrar por administrador.
