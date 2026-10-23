# 10. Operación y mantenimiento

Esta sección define cómo se respalda, se recupera y se mantiene la base de datos en la nube elegida en la sección 4 (AWS, región primaria us-east-1 y región de recuperación us-west-2). Las cifras se recalculan con `py docs/calculos/operacion.py`. Los datos del proveedor vienen de su documentación oficial, consultada el 23/10/2026 (fuentes al final).

## 10.1 Política de respaldos

| Mecanismo | Frecuencia | Retención | Dónde | Para qué |
|---|---|---|---|---|
| Standby síncrono en otra zona (Multi-AZ) | Continua: cada transacción confirmada | Siempre al día | Otra zona de us-east-1 | Falla de la instancia o de la zona, sin pérdida de datos |
| Réplica asíncrona entre regiones | Continua, con un retraso de segundos | Siempre al día | us-west-2 | Caída de la región completa |
| Archivado continuo de WAL (registro de transacciones) | El servicio lo sube cada 5 minutos | 35 días | Almacenamiento de objetos del servicio | Restauración a un punto en el tiempo tras un error lógico |
| Snapshot automático | Diario, en el horario de menor venta (madrugada) | 35 días (máximo del servicio) | Almacenamiento de objetos del servicio | Base de la restauración a un punto en el tiempo |
| Respaldo completo mensual | Mensual, el primer día del mes | 5 años | Bóveda de respaldos con paso a la capa de archivo (S3 Glacier) | Retención fiscal y recuperación de un mes cerrado |
| Copia de las particiones de bitácoras | Mensual, al cerrar cada partición | 5 años, inmutable (bloqueo de objetos) | S3, y a los 13 meses en S3 Glacier | Auditoría a 5 años (RN-20) sin cargar la base |

**Frecuencia de respaldo aceptable.** El enunciado pregunta cuál es. La respuesta tiene tres niveles:

1. **Continua**, por replicación, para cumplir el RPO de 5 segundos ante fallas de infraestructura.
2. **Cada 5 minutos**, por el archivado del WAL, para deshacer errores lógicos.
3. **Diaria y mensual**, por snapshots y respaldos completos, para tener copias independientes y la retención de 5 años.

Un respaldo solo diario no alcanza: perdería hasta 24 horas de ventas.

**Volumen y costo.** Los respaldos mensuales retenidos 5 años ocupan 11.02 TB comprimidos al cierre del año 5 (sección 3.8). En la capa de archivo, al precio de la hoja de costos (US$0.0036 por GB-mes), cuestan US$5.15 al mes en promedio durante los primeros 3 años (1,430 GB) y US$39.67 al mes en el año 5. Es el 0.05 % del costo mensual de la sección 4, por eso no cambia la comparación entre nubes. Los snapshots diarios y el WAL entran en el respaldo facturable que ya incluye la hoja.

**Pruebas de los respaldos.** Un respaldo que nunca se restauró no está probado. Cada trimestre se restaura un snapshot y una partición archivada de bitácoras en una instancia aparte, y se comparan los conteos de filas.

## 10.2 Recuperación ante desastres multi-región

La región us-west-2 tiene una réplica de lectura de la primaria, con el mismo esquema, roles y datos. Si cae toda la región us-east-1:

1. **Detectar.** Las alarmas de salud de la base y de la aplicación fallan en las dos zonas de us-east-1. El responsable de guardia declara el desastre siguiendo la guía de operación.
2. **Promover la réplica.** La réplica de us-west-2 se convierte en primaria independiente. Según el proveedor, la promoción toma unos minutos.
3. **Redirigir el tráfico.** Se cambia el registro DNS de la base y el origen de la CDN hacia la aplicación desplegada en us-west-2. La aplicación ya está desplegada ahí con pocos nodos y escala con el tráfico.
4. **Verificar.** Se corre una compra de prueba y una validación en puerta, y se revisa que las bitácoras sigan recibiendo registros.
5. **Volver a proteger.** Se activa Multi-AZ en la nueva primaria y se crea una réplica en otra región.

El procedimiento se ensaya antes de cada estreno importante, junto con la prueba de carga (sección 2.4), y se mide el tiempo real de cada paso.

## 10.3 Justificación de RPO, RTO y SLA

| Escenario | Mecanismo | RPO | RTO | Riesgo (sección 2.5) |
|---|---|---|---|---|
| Falla de la instancia primaria o de su zona | Conmutación automática al standby síncrono | 0: el standby ya tiene cada transacción confirmada | 60 a 120 s según el proveedor; menor a 5 min | R-01 |
| Caída de la región completa | Promoción de la réplica en us-west-2 | Segundos: el retraso de la réplica, con alarma si pasa de 5 s | Unos minutos de promoción más el cambio de DNS; objetivo menor a 5 min | R-02 |
| Error lógico (borrado, defecto en una versión) | Restauración a un punto en el tiempo en una instancia nueva | Hasta 5 min: frecuencia del archivado del WAL | Menor a 1 h | R-09 |
| Pérdida de bitácoras antiguas | Copia inmutable en almacenamiento de objetos | 0 | Menor a 12 h para consultar el archivo | R-10 |

**RPO ≤ 5 s (ideal 0).** Ante fallas de infraestructura se cumple con replicación, no con respaldos. Dentro de la región el RPO es 0 porque la replicación es síncrona. Entre regiones la replicación es asíncrona, así que el RPO es el retraso de la réplica: se vigila y dispara una alarma si supera 5 segundos. La restauración a un punto en el tiempo es para errores humanos o defectos, que la replicación copiaría también. Su RPO es de hasta 5 minutos, por la frecuencia con que el servicio sube el WAL.

**RTO < 5 min.** La conmutación Multi-AZ, que cubre la falla más probable, tarda de 60 a 120 segundos y deja 3 minutos de holgura. La caída de una región es poco probable; su RTO depende de una promoción que el proveedor estima en unos minutos. Por eso ese paso debe estar automatizado y ensayado: es el escenario con menos margen. La restauración tras un error lógico se ofrece con RTO de 1 hora, porque exige crear una instancia nueva desde el respaldo.

**SLA 99.99 %.** Significa como máximo 52.56 minutos de caída al año, o 4.38 minutos al mes. El servicio administrado de base de datos compromete por contrato un 99.95 % mensual en Multi-AZ (21.9 minutos al mes). El 99.99 % es entonces un objetivo de diseño de la plataforma, que se alcanza con lo siguiente:

- **Ningún punto único de falla.** La base es multi-zona, la aplicación tiene varios nodos detrás del balanceador y el borde (CDN y WAF) es global.
- **Conmutación rápida.** Cada conmutación de la base consume unos 2 minutos del presupuesto mensual, así que caben 2 por mes sin romper el objetivo.
- **Recuperación regional preparada.** La réplica en otra región está siempre al día y su promoción se ensaya.
- **Mantenimiento sin caída.** Los parches se aplican primero al standby y después se conmuta, en el horario de menor venta y nunca en semana de estreno.

Una sola falla que agote el RTO de 5 minutos ya supera el presupuesto de un mes (4.38 minutos). El SLA se mide por año y se informa cada mes.

## 10.4 Mantenimiento

| Tarea | Frecuencia | Detalle |
|---|---|---|
| Autovacuum y estadísticas | Continua, y `ANALYZE` después de cada carga grande | Mantiene los planes de ejecución con índices (sección 8.2) |
| Particiones de bitácoras | Una vez al año, en diciembre | Crear las 12 particiones mensuales del año siguiente. Hoy existen hasta diciembre de 2027; la partición `DEFAULT` recibe cualquier fila fuera de rango mientras tanto |
| Archivado de bitácoras | Mensual | Copiar y verificar la partición de hace 13 meses en el archivo, y después separarla de la base (`detach partition`) |
| Revisión de índices | Trimestral | `EXPLAIN (ANALYZE, BUFFERS)` de las consultas críticas y retiro de índices que no se usan |
| Barrido de bloqueos vencidos | Cada minuto | La aplicación llama a `liberar_bloqueos_expirados()` |
| Pruebas antes de cada versión | En cada despliegue | Pruebas SQL, prueba de concurrencia (1 ganador por asiento) y pruebas de la interfaz |
| Parches del motor | Mensual, en la ventana de mantenimiento | Primero en el standby, luego conmutación |

## 10.5 Privacidad de los datos

- **Datos de tarjeta (PCI DSS).** El sistema nunca recibe el número completo ni el CVV: los captura la pasarela certificada y devuelve un token. La base solo guarda el token, los últimos 4 dígitos y la marca (RN-09). Así, la plataforma queda fuera de la mayor parte del alcance de PCI DSS.
- **Datos personales (Ley 8968 de Costa Rica y GDPR para clientes de la Unión Europea).**
  - Se piden solo los datos necesarios para vender: nombre, apellidos y correo.
  - Las contraseñas se guardan con hash PBKDF2 y sal, nunca en texto plano.
  - Ningún dato personal viaja en la URL ni aparece en los logs de la aplicación.
- **Acceso.** Cada perfil tiene su rol de base de datos con privilegio mínimo (RN-17). Las bitácoras solo admiten inserciones. Toda operación manual queda registrada con responsable e IP (RN-20).
- **Cifrado.** La base, sus réplicas, los snapshots y los archivos se cifran en reposo con llaves administradas por el proveedor. Las conexiones de la aplicación y de los clientes usan TLS.
- **Derecho de supresión.** Si un cliente pide borrar su cuenta, se anonimizan su nombre, apellidos y correo, y se desactiva el usuario. Las órdenes, los pagos y los boletos se conservan sin datos personales durante los 5 años de retención fiscal. Los respaldos vencen solos al cumplir su retención.
- **Respaldos.** Heredan el cifrado y los mismos controles de acceso de la base. Solo el rol de operación puede restaurarlos.

## 10.6 Prueba local de respaldo y restauración

Para comprobar que un respaldo completo se puede restaurar, `scripts/respaldo_restauracion.ps1` respalda la base de desarrollo con `pg_dump` y la restaura en una base nueva con `pg_restore`. Luego compara las filas de las 12 tablas principales y al final borra la copia. Salida real en `docs/evidencias/respaldo_restauracion_2026-10-23.txt`:

| Medida | Resultado |
|---|---|
| Tamaño de la base, con índices | 303 MB |
| Tamaño del respaldo comprimido | 40 MB |
| Duración del respaldo | 7 s |
| Duración de la restauración | 9 s |
| Tablas comparadas | 12 de 12 con las mismas filas (orden, pago, boleto, check-in, reembolso y las 4 bitácoras, entre otras) |

La prueba se hizo con las herramientas cliente de PostgreSQL 18 contra el servidor 16. Por eso `pg_restore` avisa de un parámetro que la versión 16 no conoce (`transaction_timeout`). El aviso no afecta los datos, como muestra la comparación de filas; con las herramientas de la misma versión no aparece.

El respaldo ocupa unas 7 veces menos que la base, porque no copia los índices (se reconstruyen al restaurar) y va comprimido. El dimensionamiento usa una compresión más conservadora, de 3 a 1 sobre los datos sin índices. En producción el respaldo mensual lo hace el servicio administrado, pero el procedimiento de comprobación es el mismo: restaurar en una instancia aparte y comparar.

## 10.7 Fuentes

Documentación oficial de Amazon RDS, consultada el 23/10/2026:

- Conmutación Multi-AZ ("Failover times are typically 60–120 seconds"): https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Concepts.MultiAZ.Failover.html
- Replicación síncrona al standby: https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Concepts.MultiAZSingleStandby.html
- Restauración a un punto en el tiempo y subida del registro de transacciones cada 5 minutos: https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_PIT.html
- Retención de los respaldos automáticos (0 a 35 días): https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_WorkingWithAutomatedBackups.BackupRetention.html
- Promoción de una réplica de lectura: https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_ReadRepl.Promote.html
- Acuerdo de nivel de servicio de Amazon RDS (99.95 % mensual en Multi-AZ, actualizado el 22/01/2024): https://aws.amazon.com/rds/sla/
