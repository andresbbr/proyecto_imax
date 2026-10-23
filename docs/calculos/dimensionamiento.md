# Resultados del dimensionamiento

Generado el 2026-10-22 con `py docs/calculos/dimensionamiento.py`.

## Supuestos

| Supuesto | Valor | Justificación |
|---|---|---|
| dias_mes | 30 | Mes comercial |
| funciones_sala_dia | 5 | Películas de 2 a 2.5 h más limpieza, de 10:00 a 00:00 |
| asientos_sala | 300 | Sala IMAX típica: de 250 a 500 asientos |
| salas_por_sede | 1.1 | La mayoría de los complejos tiene una sola sala IMAX |
| zonas_por_sala | 3 | Platea, preferencial, VIP |
| titulos_nuevos_mes | 40 | Rotación del catálogo |
| tipos_tarifa | 5 | Adulto, niño, tercera edad, estudiante, cortesía |
| tipos_dia | 2 | Entre semana y fin de semana |
| promociones_vigentes | 200 | 2x1 y descuentos por día |
| boletos_por_orden | 2.5 | Compra en pareja o en familia |
| intentos_pago_por_orden | 1.15 | Alrededor de 13 % de rechazos o reintentos |
| bloqueos_por_boleto | 1.5 | Selecciones abandonadas o cambiadas antes de pagar |
| eventos_por_bloqueo | 2 | Bloqueo más su desenlace: compra, expiración o liberación |
| escaneos_por_boleto | 1.05 | Duplicados, rechazos y reintentos en puerta |
| ops_admin_sala_dia | 10 | Cambios de precio y función, cortesías, reembolsos forzados |
| tasa_reembolso | 0.01 | 1 % de los boletos |
| usuarios_iniciales | 20000000 | Clientes registrados al arrancar |
| usuarios_nuevos_mes | 100000 | Altas mensuales |
| sobrecarga_pagina | 1.15 | Cabecera de página, espacio libre y tuplas muertas |
| copias | 4 | Primaria, standby multi-AZ y 2 réplicas de lectura |
| meses_bitacora_en_linea | 13 | Año fiscal en curso más un mes de margen |
| compresion_archivo | 4 | Compresión de bitácoras en almacenamiento de objetos |
| compresion_respaldo | 3 | Compresión típica de un respaldo lógico |
| lecturas_cartelera | 4 | Búsqueda y filtros de cartelera |
| lecturas_detalle | 2 | Detalle de película y función |
| segundos_en_mapa | 40 | Tiempo eligiendo asientos |
| intervalo_sondeo_mapa | 2 | Polling corto del mapa (RN-03) |
| lecturas_confirmacion | 2 | Confirmación y perfil con el QR |
| llamadas_bloqueo | 1.5 | Algunas compras cambian la selección |
| sesiones_sin_compra | 3 | En un estreno la mayoría no consigue asiento |
| lecturas_sesion_sin_compra | 15 | Navegan y miran el mapa |
| fraccion_cacheable_sin_compra | 0.4 | Parte de esas lecturas es cartelera |
| acierto_cache | 0.95 | Cartelera y detalle servidos por CDN y caché |
| segundos_bloqueo | 120 | Bloqueo temporal de 2 minutos (RN-05) |
| anios_costos | 3 | Horizonte de la proyección financiera |
| recursos_estaticos_por_compra | 20 | Pósteres, estilos y scripts que el navegador no tiene en caché |
| kib_respuesta_api | 4 | JSON de cartelera, mapa y confirmación |
| kib_recurso_estatico | 50 | Pósteres comprimidos y recursos de la interfaz |

## Tamaño de fila por tabla

| Tabla | Clase | Bytes por fila | Índices / datos |
|---|---|---|---|
| usuario | operativa | 220 | 0.5 |
| sede | catalogo | 300 | 0.3 |
| sala | catalogo | 120 | 0.3 |
| zona | catalogo | 80 | 0.3 |
| asiento | catalogo | 60 | 0.6 |
| pelicula | catalogo | 1200 | 0.2 |
| tarifa | catalogo | 70 | 0.4 |
| promocion | catalogo | 200 | 0.3 |
| funcion | operativa | 90 | 0.6 |
| ocupacion_asiento | viva | 70 | 0.8 |
| orden | operativa | 130 | 0.5 |
| pago | operativa | 150 | 0.5 |
| boleto | operativa | 140 | 0.7 |
| reembolso | operativa | 120 | 0.4 |
| transaccion_log | bitacora | 200 | 0.3 |
| asiento_auditoria_log | bitacora | 100 | 0.3 |
| acceso_puerta_log | bitacora | 110 | 0.3 |
| admin_operacion_audit | bitacora | 450 | 0.3 |

## Volúmenes por mes

| Tabla | Filas por mes |
|---|---|
| usuario | 100,000 |
| pelicula | 40 |
| funcion | 225,000 |
| orden | 6,000,000 |
| pago | 6,900,000 |
| boleto | 15,000,000 |
| reembolso | 150,000 |
| transaccion_log | 25,800,000 |
| asiento_auditoria_log | 45,000,000 |
| acceso_puerta_log | 15,750,000 |
| admin_operacion_audit | 450,000 |

## Pico de 50,000 TPS

| Concepto | Valor |
|---|---|
| Operaciones por compra completada | 79.65 |
| Compras completadas por segundo | 627.7 |
| TPS de lectura | 45,825 |
| TPS de escritura | 4,175 |
| Porcentaje de lectura | 91.7 % |
| TPS resueltas por CDN y caché | 14,313 |
| TPS a réplicas de lectura | 31,513 |
| TPS a la primaria (escrituras) | 4,175 |
| Boletos vendidos por segundo | 1,569 |
| Boletos vendidos en los 10 minutos | 941,620 |
| Filas de bitácora insertadas por segundo | 9,291 |
| Bloqueos vivos simultáneos | 282,486 |
| Segundos entre solicitudes de un usuario concurrente | 160 |
| Ancho de banda de entrada (Mbps) | 819.2 |
| Veces el enlace legado de 50 Mbps | 16.4 |

## Inventario del día de estreno

| Concepto | Valor |
|---|---|
| Asientos disponibles en el día | 2,250,000 |
| Asientos que piden los usuarios concurrentes | 20,000,000 |
| Demanda sobre oferta | 8.9 |
| Minutos para agotar el día al ritmo del pico | 23.9 |

## Filas por tabla

| Tabla | Clase | Al inicio | Nuevas por mes | 1 año | 3 años | 5 años |
|---|---|---|---|---|---|---|
| usuario | operativa | 20,000,000 | 100,000 | 21,200,000 | 23,600,000 | 26,000,000 |
| sede | catalogo | 1,364 | 0 | 1,364 | 1,364 | 1,364 |
| sala | catalogo | 1,500 | 0 | 1,500 | 1,500 | 1,500 |
| zona | catalogo | 4,500 | 0 | 4,500 | 4,500 | 4,500 |
| asiento | catalogo | 450,000 | 0 | 450,000 | 450,000 | 450,000 |
| pelicula | catalogo | 500 | 40 | 980 | 1,940 | 2,900 |
| tarifa | catalogo | 40,909 | 0 | 40,909 | 40,909 | 40,909 |
| promocion | catalogo | 200 | 0 | 200 | 200 | 200 |
| funcion | operativa | 0 | 225,000 | 2,700,000 | 8,100,000 | 13,500,000 |
| ocupacion_asiento | viva | 282,486 | 0 | 282,486 | 282,486 | 282,486 |
| orden | operativa | 0 | 6,000,000 | 72,000,000 | 216,000,000 | 360,000,000 |
| pago | operativa | 0 | 6,900,000 | 82,800,000 | 248,400,000 | 414,000,000 |
| boleto | operativa | 0 | 15,000,000 | 180,000,000 | 540,000,000 | 900,000,000 |
| reembolso | operativa | 0 | 150,000 | 1,800,000 | 5,400,000 | 9,000,000 |
| transaccion_log | bitacora | 0 | 25,800,000 | 309,600,000 | 928,800,000 | 1,548,000,000 |
| asiento_auditoria_log | bitacora | 0 | 45,000,000 | 540,000,000 | 1,620,000,000 | 2,700,000,000 |
| acceso_puerta_log | bitacora | 0 | 15,750,000 | 189,000,000 | 567,000,000 | 945,000,000 |
| admin_operacion_audit | bitacora | 0 | 450,000 | 5,400,000 | 16,200,000 | 27,000,000 |

## Almacenamiento por tabla (GB)

| Tabla | Crecimiento por mes | Datos 5 años | Índices 5 años | Una copia 5 años | 4 copias 5 años |
|---|---|---|---|---|---|
| usuario | 0.04 | 6.6 | 3.3 | 9.9 | 39.5 |
| sede | 0.00 | 0.0 | 0.0 | 0.0 | 0.0 |
| sala | 0.00 | 0.0 | 0.0 | 0.0 | 0.0 |
| zona | 0.00 | 0.0 | 0.0 | 0.0 | 0.0 |
| asiento | 0.00 | 0.0 | 0.0 | 0.0 | 0.2 |
| pelicula | 0.00 | 0.0 | 0.0 | 0.0 | 0.0 |
| tarifa | 0.00 | 0.0 | 0.0 | 0.0 | 0.0 |
| promocion | 0.00 | 0.0 | 0.0 | 0.0 | 0.0 |
| funcion | 0.04 | 1.4 | 0.8 | 2.2 | 8.9 |
| ocupacion_asiento | 0.00 | 0.0 | 0.0 | 0.0 | 0.2 |
| orden | 1.35 | 53.8 | 26.9 | 80.7 | 322.9 |
| pago | 1.79 | 71.4 | 35.7 | 107.1 | 428.5 |
| boleto | 4.11 | 144.9 | 101.4 | 246.3 | 985.3 |
| reembolso | 0.03 | 1.2 | 0.5 | 1.7 | 7.0 |
| transaccion_log | 7.71 | 356.0 | 106.8 | 462.9 | 1,851.4 |
| asiento_auditoria_log | 6.73 | 310.5 | 93.2 | 403.6 | 1,614.6 |
| acceso_puerta_log | 2.59 | 119.5 | 35.9 | 155.4 | 621.6 |
| admin_operacion_audit | 0.30 | 14.0 | 4.2 | 18.2 | 72.7 |

## Acumulado por año (con copias)

| Año | TB |
|---|---|
| 1 | 1.22 |
| 2 | 2.40 |
| 3 | 3.58 |
| 4 | 4.77 |
| 5 | 5.95 |

## Resumen de almacenamiento

| Concepto | Valor |
|---|---|
| Crecimiento por mes, una copia (GB) | 24.7 |
| Crecimiento por mes, 4 copias (GB) | 98.7 |
| Acumulado 5 años, una copia (TB) | 1.49 |
| Acumulado 5 años, 4 copias (TB) | 5.95 |
|   de ello, bitácoras (TB) | 4.16 |
|   de ello, tablas operativas y catálogo (TB) | 1.79 |
| En niveles: BD con 13 meses de bitácoras (TB) | 2.69 |
| En niveles: archivo comprimido de bitácoras (TB) | 0.16 |
| Referencia: respaldos completos mensuales retenidos 5 años, comprimidos (TB) | 11.02 |
| Acumulado con copias frente a los 45 TB del enunciado | 0.13 veces |

## Volúmenes para el estimado de costos (hoja Supuestos)

| Celda | Concepto | Valor | Unidad |
|---|---|---|---|
| B9 | Solicitudes mensuales al borde (API + recursos estáticos) | 597.9 | millones/mes |
| B10 | Salida de datos a clientes | 7.91 | TB/mes (1 TB = 1,024 GB) |
| B13 | BD por copia al cierre del año 3, con niveles | 497 | GB |
| B23 | Logs en capa caliente: copia comprimida de 13 meses | 43 | GB |
| B24 | Logs en capa de archivo: promedio de 3 años | 26 | GB |
