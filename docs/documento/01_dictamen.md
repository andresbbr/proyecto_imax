# 1. Dictamen técnico de rechazo de la infraestructura legada

**Dictamen: se rechaza en su totalidad la infraestructura propuesta por el proveedor saliente.** Ninguno de sus seis elementos soporta la carga del estreno mundial, y dos de ellos (pagos y recuperación ante desastres) exponen a IMAX a incumplimientos normativos y a pérdidas que no se pueden recuperar. Cada punto se refuta con un límite técnico concreto, comparado con las cifras del dimensionamiento (sección 3).

Cifras de referencia de la carga que debe soportar la plataforma:

| Carga | Valor | Fuente |
|---|---|---|
| Usuarios concurrentes en el primer minuto | 8,000,000 | Enunciado |
| Pico de transacciones | 50,000 TPS durante 10 minutos | Enunciado |
| Escrituras en el pico | 4,175 TPS, más 9,291 filas de bitácora por segundo | Sección 3.4 |
| Compras completadas en el pico | 627.7 por segundo; 941,620 boletos en 10 minutos | Sección 3.4 |
| Ancho de banda de entrada en el pico | 819.2 Mbps (50,000 × 2 KiB) | Sección 3.4 |
| Crecimiento de la base de datos, una copia | 24.7 GB por mes | Sección 3.8 |
| Almacenamiento a 5 años con réplicas | 5.95 TB | Sección 3.8 |

## 1.1 Motor de base de datos: Microsoft Access o SQLite en un Core i3 de 2012

**Propuesta legada:** una única instancia local de Access (o un archivo SQLite) en el disco de una computadora de escritorio con un Intel Core i3 de 2012.

**Motivos del rechazo:**

1. **Access no admite la concurrencia ni el volumen.** Según las especificaciones oficiales de Microsoft, una base de Access admite como máximo 255 usuarios concurrentes y 2 GB de tamaño total. Frente a 8,000,000 de usuarios, el límite de conexiones se queda corto 31,373 veces. Con un crecimiento de 24.7 GB por mes, los 2 GB se llenan en unos 2.4 días de operación normal.
2. **SQLite serializa todas las escrituras.** La documentación oficial de SQLite indica que admite un solo escritor a la vez por archivo y recomienda un motor cliente/servidor cuando muchos procesos necesitan escribir al mismo tiempo. El pico exige 4,175 transacciones de escritura por segundo: cada una tendría que confirmar en menos de 0.24 ms, en fila detrás de las demás. Un disco de escritorio que confirma cada transacción en disco (fsync) alcanza, en orden de magnitud, unos cientos de confirmaciones por segundo. Esto es un supuesto del equipo para un disco de consumo, no una medición.
3. **No hay alta disponibilidad.** Una sola máquina, sin réplica, es un punto único de falla: si se apaga, se cae toda la venta mundial.
4. **El hardware no escala.** Un Core i3 de escritorio de esa generación tiene dos núcleos. No existe forma de escalar en vertical ni en horizontal para absorber 50,000 TPS.

**Consecuencia:** colas de escritura, bloqueos de archivo, corrupción ante cortes de energía y caída total en el primer minuto del estreno.

## 1.2 Red: fibra residencial de 50 Mbps con Wi-Fi de 2.4 GHz y un extensor

**Propuesta legada:** enrutar todo el tráfico mundial por una conexión residencial de 50 Mbps, con Wi-Fi de 2.4 GHz y un extensor de señal en el pasillo, sin servicios en la nube.

**Motivos del rechazo:**

1. **El ancho de banda no alcanza.** Solo la entrada del pico es de 50,000 × 2 KiB × 8 = 819.2 Mbps, 16.4 veces la capacidad nominal del enlace, sin contar las respuestas hacia los clientes.
2. **El Wi-Fi con extensor reduce todavía más la capacidad real.** La banda de 2.4 GHz es compartida y sufre interferencias. Un extensor repite la señal en el mismo canal, con lo que el rendimiento útil queda por debajo de los 50 Mbps nominales y la latencia aumenta.
3. **Sin SLA ni redundancia.** Un servicio residencial no tiene acuerdo de nivel de servicio, IP de respaldo ni segundo proveedor, y no puede cumplir el SLA de 99.99 % (52.6 minutos de caída al año).
4. **Sin protección.** No hay CDN, WAF ni mitigación de DDoS. Un ataque o la propia avalancha de usuarios satura el enlace y deja fuera también a las taquillas y a las puertas de acceso.

## 1.3 Hoja de cálculo compartida en Google Drive como registro de ventas

**Propuesta legada:** registrar las compras de los 8 millones de usuarios en una sola hoja de cálculo donde cada cliente escribe a mano su nombre en el asiento que quiere.

**Motivos del rechazo:**

1. **No hay atomicidad ni restricciones de integridad.** Una hoja de cálculo no tiene transacciones (BEGIN, COMMIT, ROLLBACK) ni restricciones de unicidad. Dos clientes pueden escribir en la misma celda y gana el último en guardar: la doble venta queda garantizada, no evitada. El pago y la asignación del asiento no se pueden confirmar ni revertir juntos.
2. **El límite de usuarios simultáneos.** La ayuda oficial de Google Workspace indica que hasta 100 personas con permiso de ver, comentar o editar pueden trabajar a la vez en un archivo de Hojas de cálculo. Frente a 8,000,000 de usuarios concurrentes, eso es 80,000 veces menos.
3. **El límite de tamaño.** Google fijó el máximo en 10 millones de celdas por hoja de cálculo. Si cada venta ocupa una fila de 5 columnas (función, asiento, nombre, fecha y estado; supuesto del equipo), el límite admite 2 millones de ventas: se llena en unos 4 días de operación normal (500,000 boletos por día) o en unos 21 minutos al ritmo del pico (1,569 boletos por segundo).
4. **Sin control de acceso ni auditoría.** Cualquier cliente con permiso de edición puede borrar o cambiar las compras de otros, y no hay una bitácora inalterable como exige la RN-20.

## 1.4 Pagos: tarjetas y CVV enviados a un chat de WhatsApp

**Propuesta legada:** reemplazar la pasarela bancaria por un formulario estático que envía el número completo de la tarjeta y su CVV a un chat grupal de WhatsApp, donde un pasante los digita en un datáfono físico.

**Motivos del rechazo:**

1. **Viola PCI DSS de forma directa.**
   - **Requisito 3.3.1.2:** el código de verificación no puede conservarse después de la autorización. El historial del chat lo guarda de forma indefinida.
   - **Requisito 3.5.1:** el PAN debe ser ilegible dondequiera que se almacene. En los teléfonos del grupo y en sus respaldos queda legible.
   - **Requisito 7:** el acceso a los datos de tarjeta se limita a quien lo necesita. Todos los miembros del grupo ven todas las tarjetas.
   - **Requisito 4.2.2:** el envío de PAN por mensajería de usuario final está regulado. El PCI SSC aclara que, si se usa ese canal, entra en el alcance de la norma y debe cumplir todos sus requisitos, algo que un chat grupal no puede demostrar.
2. **Viola la RN-09 del propio negocio,** que prohíbe almacenar datos sensibles de tarjeta.
3. **No escala.** El pico completa 627.7 compras por segundo, unas 37,662 por minuto. Si un pasante procesa una tarjeta por minuto en el datáfono (supuesto del equipo), se necesitarían más de 37,000 pasantes trabajando a la vez.
4. **Rompe la atomicidad.** El cobro manual ocurre fuera del sistema y sin respuesta en línea, así que no se puede liberar el asiento si el pago falla (RN-10) ni emitir el QR solo tras la aprobación (RN-11).

**Consecuencia:** exposición a fraude masivo, multas de las marcas de tarjeta, pérdida de la capacidad de procesar pagos y daño reputacional.

## 1.5 Recuperación ante desastres: "reiniciarla y cruzar los dedos"

**Propuesta legada:** si la computadora se sobrecalienta, se apaga o hay un apagón, reiniciarla y asumir que los clientes esperarán.

**Motivos del rechazo:**

1. **El RPO no tiene límite.** Sin respaldos ni réplicas, un fallo de disco pierde todas las ventas desde siempre. El requisito es un RPO de 5 segundos como máximo (ideal 0).
2. **El RTO no tiene límite.** Un reinicio con revisión de disco ya consume minutos, y una falla de hardware deja el sistema fuera por días. El requisito es un RTO menor a 5 minutos.
3. **Incumple el SLA.** El 99.99 % permite unos 52.6 minutos de caída al año. Una sola falla de hardware lo agota.
4. **Cada minuto de caída en el pico cuesta caro.** Al ritmo del pico se venden unos 94,000 boletos por minuto (941,620 en 10 minutos). Los clientes no esperan: se van o lo intentan de nuevo, y multiplican la carga al volver.

## 1.6 Dimensionamiento: la infraestructura legada no puede alojar los volúmenes proyectados

**Requisito del enunciado:** dimensionar 8 M de usuarios concurrentes, 50,000 TPS durante 10 minutos, 500 títulos en 1,500 salas, 15 M de boletos al mes y 5 años de bitácoras.

**Motivos del rechazo:** la propuesta legada no dimensiona nada. Contra las cifras calculadas en la sección 3, cada elemento queda muy por debajo de lo necesario:

| Necesidad (sección 3) | Capacidad legada | Déficit |
|---|---|---|
| 8,000,000 de usuarios concurrentes | 255 usuarios (Access) o 100 personas a la vez (Hojas de cálculo) | 31,373 a 80,000 veces |
| 4,175 escrituras por segundo | 1 escritor a la vez (SQLite) en un disco de escritorio | Varios órdenes de magnitud |
| 819.2 Mbps de entrada en el pico | 50 Mbps nominales por Wi-Fi | 16.4 veces |
| 1.49 TB a 5 años en una copia; 5.95 TB con réplicas | 2 GB por archivo (Access); 10 M de celdas (Hojas de cálculo) | Se llena en días |
| RPO ≤ 5 s, RTO < 5 min, SLA 99.99 % | Sin respaldo, sin réplica, sin SLA | No se cumple |
| Pagos bajo PCI DSS | Tarjetas y CVV en un chat | Incumplimiento directo |

## 1.7 Conclusión

La infraestructura legada no es una opción de bajo costo: es inviable. Fallaría en el primer minuto del estreno, permitiría la doble venta, incumpliría PCI DSS y no tendría forma de recuperarse. La sección 2 presenta la arquitectura que la reemplaza y su factibilidad, y la sección 4 muestra que su costo mensual, con reserva de 1 año, es de US$9,862, unos US$0.00066 por boleto.

## Fuentes del dictamen

- Microsoft, *Access specifications* (tamaño máximo de 2 GB y 255 usuarios concurrentes): https://support.microsoft.com/en-us/office/access-specifications-0cf3c66f-9cf2-4e32-9568-98c1025bb47c
- SQLite, *Appropriate Uses For SQLite* (un escritor a la vez; usar cliente/servidor con muchos escritores): https://www.sqlite.org/whentouse.html
- Google Workspace Updates, límite de 10 millones de celdas en Hojas de cálculo (marzo de 2022): https://workspaceupdates.googleblog.com/2022/03/ten-million-cells-google-sheets.html
- Google Workspace Learning Center, *Document sharing basics* (hasta 100 personas a la vez en un archivo de Docs, Sheets o Slides): https://support.google.com/a/users/answer/9305685
- PCI Security Standards Council, preguntas frecuentes sobre el envío de datos de tarjeta por mensajería de usuario final (requisito 4.2.2): https://www.pcisecuritystandards.org/faqs/are-entities-allowed-to-request-that-cardholder-data-be-provided-over-end-user-messaging-technologies/
- PCI Security Standards Council, preguntas frecuentes sobre el almacenamiento de códigos de verificación (requisito 3.3.1.2): https://www.pcisecuritystandards.org/faqs/are-merchants-allowed-to-request-card-verification-codes-values-from-cardholders/

Consultadas el 22/10/2026.
