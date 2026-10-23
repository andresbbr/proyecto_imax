# Checklist de la pauta de revisión

Cada punto de la pauta indica dónde se demuestra en la interfaz (guion de la sección 11.3 del documento), qué prueba automatizada lo comprueba y en qué archivo de `docs/evidencias` está la salida real.

Pruebas:

| Abreviatura | Prueba |
|---|---|
| SQL-R | `db/tests/01_restricciones.sql` (115 pruebas) |
| SQL-N | `db/tests/02_reglas.sql` (67 pruebas, RN-01 a RN-20) |
| GUI | `app/tests/test_gui.py` (9 pruebas con Playwright) |
| CONC | `scripts/concurrencia.py` |

## 1. Cartelera y funciones

- [x] **Alta de película con metadatos** (título, sinopsis, duración, clasificación, póster, géneros).
  - Demostración: guion 1.1, *Películas*.
  - Prueba: GUI `test_administracion_queda_en_la_auditoria`; SQL-N T-RN02-P y T-RN02-N.
  - Evidencia: `pruebas_gui_2026-10-23.txt`, `pruebas_reglas_2026-10-23.txt`.
- [x] **Asignación de sala y horario sin traslapes.**
  - Demostración: guion 1.2 y 1.3, *Funciones*; la función que se traslapa se rechaza.
  - Prueba: GUI `test_administracion_queda_en_la_auditoria`; SQL-R (trigger de traslape).
  - Evidencia: `pruebas_gui_2026-10-23.txt`, `pruebas_restricciones_2026-10-23.txt`.
- [x] **Matriz de precios** por sede, zona, tipo de entrada y tipo de día, con promociones 2x1.
  - Demostración: guion 1.4, *Precios*.
  - Prueba: GUI (cambio de precio); SQL-N T-RN07 y T-RN08.
  - Evidencia: `pruebas_gui_2026-10-23.txt`, `pruebas_reglas_2026-10-23.txt`.

## 2. Checkout

- [x] **Filtrado por ubicación, fecha y género.**
  - Demostración: guion 2.1, cartelera.
  - Prueba: GUI `test_cartelera_filtrada_por_ciudad_y_genero`; SQL-N T-RN01.
  - Evidencia: `pruebas_gui_2026-10-23.txt`.
- [x] **Bloqueo temporal con temporizador de 2 minutos**, visible desde otro navegador.
  - Demostración: guion 2.2 a 2.4 y 2.7.
  - Prueba: GUI `test_dos_navegadores_ven_el_bloqueo`; SQL-N T-RN03, T-RN04 y T-RN05.
  - Evidencia: `pruebas_gui_2026-10-23.txt`, `pruebas_reglas_2026-10-23.txt`.
- [x] **Pago simulado: el fallo libera los asientos de inmediato.**
  - Demostración: guion 2.5, tarjeta terminada en 0002.
  - Prueba: GUI `test_pago_rechazado_libera_los_asientos`; SQL-N T-RN10-P.
  - Evidencia: `pruebas_gui_2026-10-23.txt`, `pruebas_reglas_2026-10-23.txt`.
- [x] **QR y comprobante solo tras el pago exitoso.**
  - Demostración: guion 2.6, confirmación y *Mis entradas*.
  - Prueba: GUI `test_pago_aprobado_muestra_un_qr_por_asiento_y_no_envia_la_tarjeta`; SQL-N T-RN11, T-RN12 y T-RN13.
  - Evidencia: `pruebas_gui_2026-10-23.txt`, `pruebas_reglas_2026-10-23.txt`.

## 3. Puerta

- [x] **El primer escaneo entra y el segundo da "Entrada ya utilizada".**
  - Demostración: guion 3.1 y 3.2.
  - Prueba: GUI `test_puerta_un_solo_ingreso_y_rechazos`; SQL-N T-RN14.
  - Evidencia: `pruebas_gui_2026-10-23.txt`, `pruebas_reglas_2026-10-23.txt`.
- [x] **Rechazo por otra función o fuera de tolerancia** (30 minutos antes a 15 después).
  - Demostración: guion 3.3 y 3.4.
  - Prueba: GUI `test_puerta_un_solo_ingreso_y_rechazos`; SQL-N T-RN15 y T-RN16.
  - Evidencia: `pruebas_gui_2026-10-23.txt`, `pruebas_reglas_2026-10-23.txt`.

## 4. Finanzas y analíticas

- [x] **Las 4 consultas analíticas corren sin error** y cuadran con los datos.
  - Demostración: guion 4.1, *Reportes*.
  - Prueba: `db/analiticas/ejecutar.sql`; GUI `test_reportes_muestran_las_cuatro_analiticas`.
  - Evidencia: `analiticas_2026-10-23.txt`, `pruebas_gui_2026-10-23.txt`.
- [x] **EXPLAIN ANALYZE muestra el uso de índices** (antes Seq Scan, después Index Scan o Bitmap).
  - Demostración: guion 4.2.
  - Prueba: `db/analiticas/explain_indices.sql`.
  - Evidencia: `explain_antes_despues_2026-10-23.txt` (sección 8.2).

## 5. Administración

- [x] **El taquillero y el cliente no acceden a la configuración** de salas ni de precios.
  - Demostración: guion 5.1, respuesta 403.
  - Prueba: GUI `test_taquillero_y_cliente_no_entran_a_la_configuracion`; SQL-N T-RN17; SQL-R (permisos por rol).
  - Evidencia: `pruebas_gui_2026-10-23.txt`, `pruebas_reglas_2026-10-23.txt`.
- [x] **Toda alteración manual queda en la bitácora con fecha, hora y responsable** (además de rol e IP).
  - Demostración: guion 5.2 a 5.4: sala con ventas no modificable, cambio de asiento, reembolso forzado, cortesía y *Auditoría*.
  - Prueba: GUI `test_administracion_queda_en_la_auditoria`; SQL-N T-RN18, T-RN19 y T-RN20.
  - Evidencia: `pruebas_gui_2026-10-23.txt`, `pruebas_reglas_2026-10-23.txt`.

## Criterios "Deficiente" que se evitan

- [x] **Sin fallos de concurrencia.**
  - Prueba: CONC, 25 corridas con 20 y 25 con 50 solicitudes simultáneas por el mismo asiento; en todas, exactamente 1 ganador y 0 duplicados.
  - Evidencia: `concurrencia_2026-10-23.txt`.
- [x] **Sin QR reutilizables.**
  - Garantías: el código QR es único, el check-in tiene como clave el boleto y la validación es un UPDATE condicional.
  - Prueba: SQL-N T-RN12 y T-RN14; GUI de puerta.
- [x] **Consultas analíticas sin errores de sintaxis.**
  - Prueba: las 4 corren desde `psql` y desde la aplicación.
  - Evidencia: `analiticas_2026-10-23.txt`.
