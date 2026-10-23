# 5. Requerimientos funcionales y no funcionales

Los requerimientos salen del flujo de negocio, las reglas RN-01 a RN-20, los procesos de negocio y la matriz de roles del enunciado. Cada uno indica su origen ("Traza") para poder seguirlo hasta su mecanismo en la base de datos y su prueba (ver `docs/trazabilidad_rn.md`).

Roles: **CLI** Cliente / Espectador, **TAQ** Taquillero, **OPE** Operador de Sala (Puerta), **CON** Contador, **ADM** Administrador / Gerente.

Prioridad: **Alta** (obligatorio por el enunciado o la pauta de revisión), **Media** (necesario para la operación, sin verificación directa en la pauta).

## 5.1 Requerimientos funcionales

### Catálogo y cartelera (CAT)

| ID | Requerimiento | Rol | Traza | Prioridad |
|---|---|---|---|---|
| RF-CAT-01 | Mostrar solo las funciones activas cuya fecha y hora de inicio sean futuras. | CLI, TAQ, OPE, CON | RN-01 | Alta |
| RF-CAT-02 | Toda función listada muestra título, sinopsis, clasificación de edad, duración, póster, horario y ubicación exacta de la sala (sede, dirección, sala). | CLI | RN-02 | Alta |
| RF-CAT-03 | Filtrar la cartelera por ubicación (país, ciudad, sede), fecha y género. | CLI, TAQ | Proceso Checkout: búsqueda y exploración | Alta |
| RF-CAT-04 | Alta, baja y modificación de películas con sus metadatos (sinopsis, clasificación, duración, póster, géneros). | ADM | Proceso Programación: definición de catálogo | Alta |

### Programación de salas y funciones (PRG)

| ID | Requerimiento | Rol | Traza | Prioridad |
|---|---|---|---|---|
| RF-PRG-01 | Registrar sedes y salas con su capacidad y su distribución de asientos por zona (platea, preferencial, VIP). | ADM | Proceso Programación: configuración de salas | Alta |
| RF-PRG-02 | Programar funciones asignando película, sala, fecha y hora; rechazar traslapes en la misma sala, incluido el tiempo de limpieza. | ADM | Proceso Programación: scheduling; pauta 1 | Alta |
| RF-PRG-03 | Impedir eliminar o modificar la distribución de asientos de una sala con entradas vendidas o reservadas para funciones programadas. | ADM | RN-18 | Alta |
| RF-PRG-04 | Cancelar una función y disparar el reembolso o la reasignación de sus entradas. | ADM | Panel de administración: cancelaciones | Media |

### Tarifas y promociones (TAR)

| ID | Requerimiento | Rol | Traza | Prioridad |
|---|---|---|---|---|
| RF-TAR-01 | Mantener la matriz de precios por sede, zona de asiento, tipo de tarifa (adulto, niño, tercera edad, estudiante) y tipo de día (entre semana o fin de semana). | ADM | Proceso Programación: tarifas; pauta 1 | Alta |
| RF-TAR-02 | Marcar las tarifas especiales que requieren validar el documento de identidad en puerta. | ADM, OPE | RN-06 | Alta |
| RF-TAR-03 | Definir promociones (2x1, días de descuento) con sus condiciones y aplicarlas automáticamente al armar la compra. | ADM | RN-07 | Alta |
| RF-TAR-04 | Calcular el total de la compra como la suma de las tarifas de los asientos, menos los descuentos de promociones, más los cargos por servicio, y mostrar el desglose. | CLI, TAQ | RN-08 | Alta |

### Selección y bloqueo de asientos (ASI)

| ID | Requerimiento | Rol | Traza | Prioridad |
|---|---|---|---|---|
| RF-ASI-01 | Mostrar el mapa de la sala por zonas con el estado de cada asiento: disponible, ocupado, bloqueado temporalmente y seleccionado por el usuario. | CLI, TAQ | RN-03 | Alta |
| RF-ASI-02 | Actualizar el estado del mapa casi en tiempo real (sondeo corto) para que dos usuarios vean los bloqueos del otro. | CLI, TAQ | RN-03; pauta 2 | Alta |
| RF-ASI-03 | Limitar la cantidad de asientos por transacción a un máximo configurable (6 por defecto). | CLI, TAQ | RN-04 | Alta |
| RF-ASI-04 | Bloquear temporalmente los asientos elegidos durante 2 minutos para ese usuario, con un temporizador visible, y liberarlos automáticamente al expirar. | CLI, TAQ | RN-05; pauta 2 | Alta |
| RF-ASI-05 | Garantizar que dos transacciones simultáneas nunca obtengan el mismo asiento de la misma función: una gana y las demás reciben un rechazo. | CLI, TAQ | RN-05, RN-12; pauta 2 | Alta |

### Pago (PAG)

| ID | Requerimiento | Rol | Traza | Prioridad |
|---|---|---|---|---|
| RF-PAG-01 | Procesar el pago con una pasarela simulada que responde aprobado o rechazado, con métodos tarjeta, PayPal, transferencia y billetera digital. | CLI, TAQ | Proceso Checkout: procesamiento de pago | Alta |
| RF-PAG-02 | Guardar del pago solo el token de la pasarela, los últimos 4 dígitos y la marca; nunca el número completo de tarjeta ni el CVV. | CLI, TAQ | RN-09 | Alta |
| RF-PAG-03 | Ante un rechazo: cancelar la orden, no registrar cobro y liberar de inmediato los asientos bloqueados. | CLI, TAQ | RN-10; pauta 2 | Alta |
| RF-PAG-04 | Registrar cada intento de pago y cada respuesta de la pasarela con montos e impuestos. | Sistema | Bitácora `transaccion_log` | Alta |

### Emisión de entradas (EMI)

| ID | Requerimiento | Rol | Traza | Prioridad |
|---|---|---|---|---|
| RF-EMI-01 | Emitir boletos y QR únicamente dentro de la confirmación de un pago aprobado. | Sistema | RN-11; pauta 2 | Alta |
| RF-EMI-02 | Asignar a cada boleto un código único asociado a una función, una zona y un asiento. | Sistema | RN-12 | Alta |
| RF-EMI-03 | Mostrar al cliente sus entradas vigentes y pasadas, con el QR, en su perfil. | CLI | RN-13 | Alta |
| RF-EMI-04 | Emitir boletos en taquilla para ventas presenciales. | TAQ | Matriz de roles | Media |

### Control de acceso en puerta (ACC)

| ID | Requerimiento | Rol | Traza | Prioridad |
|---|---|---|---|---|
| RF-ACC-01 | Validar un QR una sola vez; cualquier intento posterior responde "Entrada ya utilizada". | OPE | RN-14; pauta 3 | Alta |
| RF-ACC-02 | Rechazar entradas de otra función, fecha u hora distinta a la de la puerta, salvo una reprogramación autorizada. | OPE | RN-15; pauta 3 | Alta |
| RF-ACC-03 | Permitir el ingreso solo dentro de la ventana configurable (por defecto, de 30 min antes a 15 min después del inicio). | OPE | RN-16; pauta 3 | Alta |
| RF-ACC-04 | Registrar cada escaneo con su marca de tiempo, el boleto, la puerta o dispositivo y el resultado (exitoso, duplicado, otra función, fuera de horario). | Sistema | Bitácora `acceso_puerta_log` | Alta |
| RF-ACC-05 | Avisar al operador cuando la tarifa del boleto exige validar documento y registrar la incidencia si no se presenta. | OPE | RN-06; proceso Control de acceso: incidencias | Media |

### Finanzas, reembolsos y reportes (FIN)

| ID | Requerimiento | Rol | Traza | Prioridad |
|---|---|---|---|---|
| RF-FIN-01 | Anular una entrada y reembolsar solo según la política (hasta 2 h antes de la función), liberando el asiento. | ADM | RN-19 | Alta |
| RF-FIN-02 | Reporte de ocupación y recaudación por función: porcentaje de asientos vendidos e ingresos totales. | CON, ADM | Consulta analítica 1; pauta 4 | Alta |
| RF-FIN-03 | Top 5 de películas con más boletos vendidos en la última semana, a nivel global. | CON, ADM | Consulta analítica 2; pauta 4 | Alta |
| RF-FIN-04 | Reporte porcentual de los métodos de pago utilizados. | CON, ADM | Consulta analítica 3; pauta 4 | Alta |
| RF-FIN-05 | Corte de caja del taquillero con sus propias ventas. | TAQ | Matriz de roles | Media |
| RF-FIN-06 | Conciliación de pagos registrados contra las confirmaciones de la pasarela y exportación de ingresos. | CON | Proceso Gestión financiera: conciliación | Media |
| RF-FIN-07 | Panel con métricas en tiempo real: ocupación, ingresos por función, métodos de pago. | ADM | Panel de administración: reportes | Alta |

### Administración y auditoría (ADM)

| ID | Requerimiento | Rol | Traza | Prioridad |
|---|---|---|---|---|
| RF-ADM-01 | Autenticación por usuario y autorización por rol según la matriz de privilegio mínimo; el taquillero y el cliente no acceden a la configuración de salas ni de precios. | Todos | RN-17; pauta 5 | Alta |
| RF-ADM-02 | Asignar y revocar roles a los empleados. | ADM | Proceso Administración: RBAC | Media |
| RF-ADM-03 | Registrar toda operación manual (cortesías, cambios de asiento, reembolsos forzados, cambios de configuración crítica) con fecha, hora, IP, rol y usuario responsable. | Sistema | RN-20; pauta 5 | Alta |
| RF-ADM-04 | Consultar la bitácora de auditoría del último mes agrupada por administrador. | ADM | Consulta analítica 4; pauta 4 | Alta |
| RF-ADM-05 | Registrar los bloqueos, expiraciones, liberaciones y compras de asientos. | Sistema | Bitácora `asiento_auditoria_log` | Alta |

## 5.2 Requerimientos no funcionales

Las cifras de carga vienen del dimensionamiento (sección 3, `docs/calculos/dimensionamiento.py`).

| ID | Categoría | Requerimiento | Métrica de aceptación | Cómo se verifica | Traza |
|---|---|---|---|---|---|
| RNF-01 | Integridad | Toda compra es atómica: el estado de los asientos, la orden, el pago y los boletos cambian juntos o no cambian. | Ninguna orden aprobada sin boletos, ni boletos sin pago aprobado. | Pruebas SQL de las ramas aprobada y rechazada | RN-10, RN-11 |
| RNF-02 | Concurrencia | Cero doble venta: la restricción de unicidad impide que dos transacciones tomen el mismo asiento de la misma función. | En cada corrida de 20 y 50 solicitudes simultáneas idénticas: exactamente 1 ganador y 0 duplicados. | Script Python multihilo, muchas corridas | RN-05, RN-12; pauta 2 |
| RNF-03 | Rendimiento | Responder rápido las operaciones críticas aun con millones de filas. | p95 del bloqueo de asientos < 200 ms; p95 del mapa de asientos < 300 ms; p95 de la validación en puerta < 500 ms. | `EXPLAIN (ANALYZE, BUFFERS)` antes y después de los índices, sobre la carga masiva | Fase 3 diseño físico; pauta 4 |
| RNF-04 | Capacidad | Soportar el pico de 50,000 TPS durante los primeros 10 minutos de taquilla. | 45,825 TPS de lectura y 4,175 TPS de escritura, repartidos entre caché, réplicas y primaria. | Dimensionamiento y arquitectura propuesta | Escenario legado punto 6 |
| RNF-05 | Escalabilidad | Escalar las lecturas horizontalmente sin tocar la primaria. | Las lecturas de cartelera se sirven desde caché y CDN; el mapa, desde réplicas de lectura. | Diseño de arquitectura | RN-03 |
| RNF-06 | Disponibilidad | SLA del 99.99 %. | Como máximo 52.6 minutos de caída al año. | Arquitectura multi-AZ y DR multi-región | Fase 5 |
| RNF-07 | Recuperación | Pérdida de datos y tiempo de recuperación acotados. | RPO ≤ 5 s (ideal 0); RTO < 5 min. | Replicación síncrona, archivado continuo de WAL y failover automático | Fase 5 |
| RNF-08 | Seguridad de pagos | Cumplir PCI-DSS sacando del alcance los datos de tarjeta. | Ninguna tabla, log, seed ni documento tiene columnas o valores de PAN o CVV; solo token, últimos 4 y marca. | Revisión del DDL y búsqueda en el repositorio | RN-09 |
| RNF-09 | Control de acceso | Privilegio mínimo en la aplicación y en la base de datos. | Cada rol de BD tiene solo los GRANT de su columna de la matriz; los accesos no permitidos fallan. | Pruebas SQL por rol y pruebas de la GUI por perfil | RN-17; pauta 5 |
| RNF-10 | Auditoría | Bitácoras inalterables y separadas por dominio. | Los roles de aplicación no pueden hacer UPDATE ni DELETE en las 4 bitácoras; están particionadas por fecha. | Pruebas SQL de permisos | RN-20 |
| RNF-11 | Retención | Conservar las bitácoras y los registros fiscales por un mínimo de 5 años. | Particiones mensuales, con las de más de 13 meses archivadas en almacenamiento de objetos. | Política de respaldo y archivado | RN-20; escenario legado punto 6 |
| RNF-12 | Privacidad | Tratar los datos personales según la Ley 8968 de Costa Rica y el GDPR para clientes de la UE. | Datos mínimos del cliente, contraseñas con hash, ningún dato personal en URL ni en logs de aplicación. | Revisión del modelo y de la API | Fase 5: privacidad |
| RNF-13 | Mantenibilidad | El sistema se reconstruye desde cero sin pasos manuales. | `iniciar.ps1 -Reiniciar` (o `db/init.sql` seguido de `db/seed/cargar.sql`) deja la base lista desde cero. | Ejecución desde un clon limpio | Entrega: repositorio Git |
| RNF-14 | Usabilidad | La GUI es funcional y de soporte, con códigos de color estándar. | Verde disponible, gris ocupado, amarillo bloqueado, azul seleccionado; todos los flujos de la pauta se hacen desde la GUI. | Pruebas end-to-end con Playwright | Entregable GUI; pauta |
