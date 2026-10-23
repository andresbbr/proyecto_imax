# Matriz de trazabilidad

Relaciona cada regla de negocio (RN) del enunciado con su mecanismo en la base de datos, los objetos que la implementan y sus pruebas.

Estados: `Pendiente`, `Diseñada`, `Implementada`, `Probada` (prueba positiva y negativa en verde).

Las pruebas se identifican como `T-RNxx-P` (positiva: el caso válido se acepta) y `T-RNxx-N` (negativa: el caso inválido se rechaza). Vivirán en `db/tests/`.

## 1. Reglas de negocio

| RN | Regla (resumen) | Mecanismo en BD (propuesto) | Objetos previstos | Prueba + | Prueba - | Estado |
|---|---|---|---|---|---|---|
| RN-01 | Solo se muestran funciones activas con inicio futuro | Vista con filtro de estado e `inicio > now()` | `v_cartelera_activa`, `funcion.estado`, `funcion.inicio` | T-RN01-P | T-RN01-N | Pendiente |
| RN-02 | Toda función lista título, sinopsis, clasificación, horarios y ubicación de sala | `NOT NULL` en película, sala y sede; vista de cartelera que las une | `pelicula`, `sala`, `sede`, `v_cartelera_activa` | T-RN02-P | T-RN02-N | Pendiente |
| RN-03 | El mapa refleja en tiempo real: disponible, ocupado, reservado, bloqueado | Estado derivado por función y asiento; la GUI consulta con polling corto | `v_mapa_asientos`, `bloqueo_asiento`, `boleto` | T-RN03-P | T-RN03-N | Pendiente |
| RN-04 | Máximo de asientos por transacción (6) | Parámetro de configuración validado dentro de la función de bloqueo | `parametro_sistema`, `bloquear_asientos()` | T-RN04-P | T-RN04-N | Pendiente |
| RN-05 | Bloqueo temporal de 2 minutos, se libera solo al expirar | Tabla de bloqueos con `expira_en`; `UNIQUE (id_funcion, id_asiento)`; limpieza de expirados en la misma transacción y por barrido periódico | `bloqueo_asiento`, `uq_bloqueo_asiento_funcion_asiento`, `liberar_bloqueos_expirados()` | T-RN05-P | T-RN05-N | Pendiente |
| RN-06 | Tarifas especiales sujetas a validación de documento en puerta | Bandera en el tipo de tarifa; incidencia registrada en puerta | `tipo_tarifa.requiere_validacion_documento`, `acceso_puerta_log` | T-RN06-P | T-RN06-N | Pendiente |
| RN-07 | Promociones (2x1) se aplican automáticamente según condiciones | Tabla de promociones con condiciones (cantidad par, día de la semana) y función de cálculo | `promocion`, `calcular_total()` | T-RN07-P | T-RN07-N | Pendiente |
| RN-08 | Total = suma de tarifas, menos descuentos, más cargos de servicio | Función de cálculo; `CHECK` de coherencia en la orden | `calcular_total()`, `ck_orden_total_coherente` | T-RN08-P | T-RN08-N | Pendiente |
| RN-09 | Sin datos sensibles de tarjeta en la BD (PCI-DSS) | Modelo sin columnas de PAN ni CVV; solo token simulado, últimos 4 dígitos y marca | `pago.token_pasarela`, `pago.ultimos4`, `pago.marca` | T-RN09-P | T-RN09-N | Pendiente |
| RN-10 | Pago rechazado: se cancela, no se debita y se liberan los asientos | Procedimiento con rama de rechazo que libera bloqueos y registra en bitácora | `procesar_pago()`, `transaccion_log`, `asiento_auditoria_log` | T-RN10-P | T-RN10-N | Pendiente |
| RN-11 | Ni QR ni comprobante antes de la aprobación del pago | La emisión ocurre solo en la rama aprobada; trigger o `CHECK` que exige pago aprobado | `emitir_boletos()`, trigger sobre `boleto` | T-RN11-P | T-RN11-N | Pendiente |
| RN-12 | Identificador único por entrada ligado a función, localidad y asiento | `UNIQUE` del código QR; `UNIQUE (id_funcion, id_asiento)` en boletos vigentes | `uq_boleto_codigo_qr`, índice único parcial en `boleto` | T-RN12-P | T-RN12-N | Pendiente |
| RN-13 | Comprobante accesible en el perfil del cliente | Vista filtrada por usuario | `v_mis_entradas` | T-RN13-P | T-RN13-N | Pendiente |
| RN-14 | Un QR se valida una sola vez; el reintento responde "Entrada ya utilizada" | `UPDATE` condicional atómico sobre el estado del boleto | `validar_entrada()`, `acceso_puerta_log` | T-RN14-P | T-RN14-N | Pendiente |
| RN-15 | Se rechaza una entrada de otra función, fecha u hora | Comparación del boleto contra la función en curso de la puerta | `validar_entrada()` | T-RN15-P | T-RN15-N | Pendiente |
| RN-16 | Ventana de ingreso: de 30 min antes a 15 min después del inicio | Parámetros configurables aplicados en la validación | `parametro_sistema`, `validar_entrada()` | T-RN16-P | T-RN16-N | Pendiente |
| RN-17 | RBAC: solo perfiles autorizados hacen acciones críticas | Roles de BD con `GRANT` mínimo y validación por rol en la API | `rol_*`, `usuario`, `rol` (sección 2) | T-RN17-P | T-RN17-N | Pendiente |
| RN-18 | No se modifica ni elimina una sala (o su mapa de asientos) con ventas activas | Trigger `BEFORE UPDATE/DELETE` en sala y asiento | `trg_sala_before_update`, `trg_asiento_before_update` | T-RN18-P | T-RN18-N | Pendiente |
| RN-19 | Reembolso solo según política (hasta 2 h antes) y libera el asiento | Función con regla de tiempo y liberación del asiento | `anular_boleto()`, `reembolso` | T-RN19-P | T-RN19-N | Pendiente |
| RN-20 | Auditoría de operaciones manuales con retención de 5 años | Bitácora append-only particionada; fecha, hora, IP, rol y usuario obligatorios | `admin_operacion_audit` (y las otras 3 bitácoras, sección 3) | T-RN20-P | T-RN20-N | Pendiente |

## 2. Matriz de roles con privilegio mínimo (RN-17)

Tomada del enunciado. La columna "Rol de BD" es el rol de grupo que se creará en el DDL.

| Módulo / funcionalidad | Cliente / Espectador | Taquillero | Operador de Sala (Puerta) | Contador | Administrador / Gerente |
|---|---|---|---|---|---|
| Catálogo y cartelera | Lectura (funciones activas) | Lectura | Lectura | Lectura | Lectura y escritura (CRUD completo) |
| Selección de asientos y pago | Ejecución (compra en línea) | Ejecución (venta presencial) | Sin acceso | Sin acceso | Configuración de reglas y precios |
| Emisión y acceso (QR) | Lectura (sus propios QR) | Lectura (emitir boletos físicos o digitales) | Ejecución (validar y escanear QR) | Sin acceso | Gestión de incidencias y reasignaciones |
| Reportes y finanzas | Sin acceso | Lectura (corte de caja propio) | Sin acceso | Lectura y exportación (conciliación, ingresos) | Lectura total (métricas globales) |
| Configuración de salas y funciones | Sin acceso | Sin acceso | Sin acceso | Sin acceso | Lectura y escritura (restringido por RN-18) |
| Auditoría y gestión de roles | Sin acceso | Sin acceso | Sin acceso | Sin acceso | Lectura total (bitácora de operaciones y RBAC) |
| **Rol de BD** | `rol_cliente` | `rol_taquillero` | `rol_operador_puerta` | `rol_contador` | `rol_administrador` |
| **RN relacionadas** | RN-01, RN-13 | RN-04, RN-19 | RN-14, RN-15, RN-16 | Analíticas | RN-17, RN-18, RN-20 |

Criterios de privilegio mínimo:

1. **Cliente:** solo su flujo de compra, la cartelera y sus propias entradas.
2. **Taquillero:** vende y emite boletos; sin acceso a precios globales, salas ni auditoría.
3. **Operador de puerta:** solo valida QR; no vende, no maneja dinero, no configura.
4. **Contador:** conciliación, recaudación e informes; no toca programación ni estructura de cines.
5. **Administrador / Gerente:** control total, sujeto a la RN-18; único rol que ve la bitácora de auditoría.

Ningún rol de aplicación tiene `UPDATE` ni `DELETE` sobre las bitácoras (sección 3).

## 3. Bitácoras (retención mínima de 5 años)

El enunciado dice "tres categorías" pero describe cuatro; se implementan las cuatro, para cubrir también la auditoría administrativa que pide la RN-20. Todas van particionadas por fecha y son append-only.

| Bitácora | Qué registra | Campos obligatorios mínimos | RN que alimenta |
|---|---|---|---|
| `transaccion_log` | Intentos de pago, respuesta de la pasarela, montos, impuestos, emisión de boletos | fecha, orden, monto, resultado | RN-08, RN-10, RN-11 |
| `asiento_auditoria_log` | Bloqueo, liberación por expiración, liberación por rechazo, compra definitiva | fecha, función, asiento, evento | RN-03, RN-05, RN-10, RN-19 |
| `acceso_puerta_log` | Cada escaneo: boleto, puerta o dispositivo, resultado (exitoso, duplicado, otra función, fuera de horario) | timestamp, boleto, dispositivo, resultado | RN-06, RN-14, RN-15, RN-16 |
| `admin_operacion_audit` | Cortesías, cambios manuales de asiento, reembolsos forzados, cambios de configuración crítica | fecha y hora, IP, ID de rol, ID de usuario responsable, operación | RN-18, RN-19, RN-20 |

## 4. Relación con la pauta de revisión

| Punto de la pauta | Qué se verifica | RN |
|---|---|---|
| 1. Cartelera y funciones | Alta de película con metadatos, sala y horario sin traslapes, matriz de precios | RN-01, RN-02, RN-07, RN-18 |
| 2. Checkout | Filtros por ubicación, fecha y género; bloqueo con temporizador; pago simulado que libera al fallar; QR solo tras pago exitoso | RN-03, RN-04, RN-05, RN-08, RN-09, RN-10, RN-11, RN-12, RN-13 |
| 3. Puerta | Primer escaneo entra, segundo da "Entrada ya utilizada"; rechazo por otra función o fuera de tolerancia | RN-06, RN-14, RN-15, RN-16 |
| 4. Finanzas y analíticas | Las 4 consultas sin error; EXPLAIN ANALYZE con uso de índices | RN-08, RN-20 |
| 5. Administración | Taquillero y cliente sin acceso a salas ni precios; alteraciones manuales en bitácora | RN-17, RN-19, RN-20 |
