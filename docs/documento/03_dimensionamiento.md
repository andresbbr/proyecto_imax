# 3. Dimensionamiento de datos y carga

Esta sección estima la carga del pico de taquilla y el almacenamiento necesario para 5 años de operación y de retención de bitácoras. Todas las cifras salen del script `docs/calculos/dimensionamiento.py`, que tiene los supuestos al inicio y escribe los resultados completos en `docs/calculos/dimensionamiento.md`:

```
py docs/calculos/dimensionamiento.py
```

Unidades: GB = 10^9 bytes y TB = 10^12 bytes.

## 3.1 Datos de partida

| Dato del enunciado | Valor |
|---|---|
| Usuarios concurrentes en el estreno | 8,000,000 |
| Pico de transacciones (compras y lecturas) | 50,000 TPS durante 10 minutos |
| Salas IMAX a nivel mundial | 1,500 |
| Títulos activos | 500 |
| Boletos vendidos por mes (promedio) | 15,000,000 |
| Retención obligatoria de bitácoras | 5 años |

## 3.2 Supuestos principales

| Supuesto | Valor | Justificación |
|---|---|---|
| Funciones por sala y día | 5 | Películas de 2 a 2.5 h más limpieza, de 10:00 a 00:00 |
| Asientos promedio por sala | 300 | Sala IMAX típica: de 250 a 500 asientos |
| Boletos por orden | 2.5 | Compra en pareja o en familia |
| Intentos de pago por orden | 1.15 | Alrededor de 13 % de rechazos o reintentos |
| Bloqueos por boleto vendido | 1.5 | Selecciones abandonadas o cambiadas antes de pagar |
| Escaneos por boleto | 1.05 | Duplicados, rechazos y reintentos en puerta |
| Operaciones administrativas por sala y día | 10 | Cambios de precio y función, cortesías, reembolsos forzados |
| Copias de la base de datos | 4 | Primaria, standby en otra zona y 2 réplicas de lectura |
| Sobrecarga de página | 1.15 | Cabecera de página, espacio libre y tuplas muertas |

El volumen se toma constante: el enunciado da 15 M de boletos como promedio mensual. Los tamaños de fila (de 60 a 1,200 B) y la proporción de índices (de 0.2 a 0.8 del tamaño de datos) de cada tabla están en el script. Se compararán con el tamaño real de las tablas cuando exista la carga de prueba.

## 3.3 Volumen mensual del negocio

| Concepto | Fórmula | Filas por mes |
|---|---|---|
| Funciones | 1,500 salas × 5 funciones × 30 días | 225,000 |
| Órdenes | 15,000,000 boletos ÷ 2.5 | 6,000,000 |
| Pagos (intentos) | 6,000,000 órdenes × 1.15 | 6,900,000 |
| Boletos | Dato del enunciado | 15,000,000 |
| Reembolsos | 1 % de los boletos | 150,000 |
| `transaccion_log` | órdenes × 2 (creación y emisión) + pagos × 2 (solicitud y respuesta) | 25,800,000 |
| `asiento_auditoria_log` | boletos × 1.5 bloqueos × 2 eventos | 45,000,000 |
| `acceso_puerta_log` | boletos × 1.05 escaneos | 15,750,000 |
| `admin_operacion_audit` | 1,500 salas × 10 operaciones × 30 días | 450,000 |

Las bitácoras reciben unos 87 M de filas al mes, casi 6 veces el número de boletos. Por eso se separan de las tablas operativas y se particionan por mes.

## 3.4 Desglose del pico de 50,000 TPS

El pico se reparte según las operaciones que genera cada compra completada:

| Tipo | Operaciones por compra completada |
|---|---|
| Lecturas cacheables | 4 de cartelera + 2 de detalle + 3 sesiones sin compra × 15 lecturas × 0.4 = 24 |
| Lecturas de tiempo real | 40 s en el mapa ÷ sondeo cada 2 s + 2 de confirmación + 3 × 15 × 0.6 = 49 |
| Escrituras | 1.5 bloqueos + 1 orden + 1.15 pagos + 3 bloqueos fallidos de las sesiones sin compra = 6.65 |
| **Total** | **79.65** |

Las 3 sesiones sin compra por cada compra representan a los usuarios que, en un estreno, no consiguen asiento: navegan, miran el mapa y su intento de bloqueo choca con la restricción de unicidad.

| Resultado del pico | Valor |
|---|---|
| Compras completadas por segundo | 627.7 |
| TPS de lectura | 45,825 (91.7 %) |
| TPS de escritura | 4,175 |
| TPS resueltas por CDN y caché (acierto del 95 % en cartelera y detalle) | 14,313 |
| TPS a réplicas de lectura (mapa, confirmación, fallos de caché) | 31,513 |
| TPS a la primaria (escrituras) | 4,175 |
| Boletos vendidos por segundo | 1,569 |
| Boletos vendidos en los 10 minutos | 941,620 |
| Filas de bitácora insertadas por segundo | 9,291 |
| Bloqueos vivos simultáneos en la tabla `ocupacion_asiento` | 282,486 |
| Ancho de banda de entrada (50,000 × 2 KiB) | 819.2 Mbps, 16.4 veces el enlace legado de 50 Mbps |

Conclusiones:

- **La primaria solo recibe las escrituras.** Son unas 4,200 TPS cortas más unas 9,300 filas de bitácora por segundo. Una instancia PostgreSQL bien dimensionada puede atenderlas, siempre que las lecturas no lleguen a ella.
- **Las lecturas se reparten.** La cartelera sale de la CDN y la caché, y el mapa de asientos de las réplicas de lectura. Que una réplica tenga un pequeño retraso no permite vender dos veces el mismo asiento, porque la restricción de unicidad se aplica en la primaria.
- **La mayoría de los 8 M de usuarios tiene que esperar.** 50,000 TPS entre 8 M de usuarios es una solicitud cada 160 segundos por usuario. Por eso hace falta una sala de espera virtual que dosifique la entrada.

## 3.5 Inventario del día de estreno

| Concepto | Valor |
|---|---|
| Asientos disponibles en el día (1,500 salas × 5 funciones × 300 asientos) | 2,250,000 |
| Asientos que piden los usuarios concurrentes (8,000,000 × 2.5) | 20,000,000 |
| Demanda sobre oferta | 8.9 veces |
| Minutos para agotar el día al ritmo del pico | 23.9 |

La demanda supera a la oferta casi 9 veces y el inventario del día se agota en unos 24 minutos. Que varios usuarios pidan el mismo asiento a la vez es el caso normal. Por eso la prueba de concurrencia con 20 y 50 solicitudes simultáneas es central.

## 3.6 Filas esperadas por tabla

| Tabla | Clase | Al inicio | Nuevas por mes | 1 año | 3 años | 5 años |
|---|---|---|---|---|---|---|
| usuario | operativa | 20,000,000 | 100,000 | 21,200,000 | 23,600,000 | 26,000,000 |
| sede | catálogo | 1,364 | 0 | 1,364 | 1,364 | 1,364 |
| sala | catálogo | 1,500 | 0 | 1,500 | 1,500 | 1,500 |
| zona | catálogo | 4,500 | 0 | 4,500 | 4,500 | 4,500 |
| asiento | catálogo | 450,000 | 0 | 450,000 | 450,000 | 450,000 |
| pelicula | catálogo | 500 | 40 | 980 | 1,940 | 2,900 |
| tarifa | catálogo | 40,909 | 0 | 40,909 | 40,909 | 40,909 |
| promocion | catálogo | 200 | 0 | 200 | 200 | 200 |
| funcion | operativa | 0 | 225,000 | 2,700,000 | 8,100,000 | 13,500,000 |
| ocupacion_asiento | viva | 282,486 | 0 | 282,486 | 282,486 | 282,486 |
| orden | operativa | 0 | 6,000,000 | 72,000,000 | 216,000,000 | 360,000,000 |
| pago | operativa | 0 | 6,900,000 | 82,800,000 | 248,400,000 | 414,000,000 |
| boleto | operativa | 0 | 15,000,000 | 180,000,000 | 540,000,000 | 900,000,000 |
| reembolso | operativa | 0 | 150,000 | 1,800,000 | 5,400,000 | 9,000,000 |
| transaccion_log | bitácora | 0 | 25,800,000 | 309,600,000 | 928,800,000 | 1,548,000,000 |
| asiento_auditoria_log | bitácora | 0 | 45,000,000 | 540,000,000 | 1,620,000,000 | 2,700,000,000 |
| acceso_puerta_log | bitácora | 0 | 15,750,000 | 189,000,000 | 567,000,000 | 945,000,000 |
| admin_operacion_audit | bitácora | 0 | 450,000 | 5,400,000 | 16,200,000 | 27,000,000 |

Las tablas de catálogo no crecen con la venta. `ocupacion_asiento` guarda los bloqueos vigentes y los asientos vendidos de las funciones que aún no terminan. Sus filas se borran al terminar cada función, así que no acumula; la tabla muestra los bloqueos simultáneos del pico. La historia de la venta queda en `boleto` y en `asiento_auditoria_log`.

## 3.7 Almacenamiento por tabla

Fórmula por tabla: `filas × bytes por fila × 1.15 × (1 + proporción de índices)`, multiplicada por el número de copias.

| Tabla | Crecimiento por mes (GB) | Datos 5 años (GB) | Índices 5 años (GB) | Una copia 5 años (GB) | 4 copias 5 años (GB) |
|---|---|---|---|---|---|
| usuario | 0.04 | 6.6 | 3.3 | 9.9 | 39.5 |
| funcion | 0.04 | 1.4 | 0.8 | 2.2 | 8.9 |
| orden | 1.35 | 53.8 | 26.9 | 80.7 | 322.9 |
| pago | 1.79 | 71.4 | 35.7 | 107.1 | 428.5 |
| boleto | 4.11 | 144.9 | 101.4 | 246.3 | 985.3 |
| reembolso | 0.03 | 1.2 | 0.5 | 1.7 | 7.0 |
| transaccion_log | 7.71 | 356.0 | 106.8 | 462.9 | 1,851.4 |
| asiento_auditoria_log | 6.73 | 310.5 | 93.2 | 403.6 | 1,614.6 |
| acceso_puerta_log | 2.59 | 119.5 | 35.9 | 155.4 | 621.6 |
| admin_operacion_audit | 0.30 | 14.0 | 4.2 | 18.2 | 72.7 |
| Catálogo y `ocupacion_asiento` | 0.00 | menos de 0.1 | menos de 0.1 | 0.1 | 0.4 |

## 3.8 Almacenamiento mensual y acumulado

| Concepto | Valor |
|---|---|
| Crecimiento por mes, una copia | 24.7 GB |
| Crecimiento por mes, 4 copias | 98.7 GB |
| Acumulado año 1, 4 copias | 1.22 TB |
| Acumulado año 2, 4 copias | 2.40 TB |
| Acumulado año 3, 4 copias | 3.58 TB |
| Acumulado año 4, 4 copias | 4.77 TB |
| **Acumulado año 5, 4 copias** | **5.95 TB** |
| Acumulado 5 años, una copia | 1.49 TB |
| De los 5 años: bitácoras | 4.16 TB |
| De los 5 años: tablas operativas y catálogo | 1.79 TB |

Las bitácoras son el 70 % del almacenamiento. Guardar 5 años de bitácoras en todas las copias de la base de datos es lo que más espacio ocupa, y por eso se propone separarlas en niveles.

### Almacenamiento en niveles (propuesta)

La base de datos conserva solo los últimos 13 meses de bitácoras: el año fiscal en curso más un mes de margen. Las particiones más antiguas se exportan comprimidas a almacenamiento de objetos en un nivel de archivo.

| Concepto al cierre del año 5 | Valor |
|---|---|
| Base de datos con 13 meses de bitácoras, 4 copias | 2.69 TB |
| Archivo comprimido de bitácoras (compresión 4:1) | 0.16 TB |
| Respaldos completos mensuales retenidos 5 años, comprimidos 3:1 (fuera de la BD) | 11.02 TB |

Con niveles, la base de datos baja de 5.95 TB a 2.69 TB al quinto año. El análisis económico (sección 4) usa esta variante.

## 3.9 Comparación con la cifra referencial de 45 TB

El ejemplo de costos del enunciado menciona unos 45 TB acumulados a 5 años. El cálculo propio da **5.95 TB**, 0.13 veces esa cifra. No se forzó el número; la diferencia se explica por lo que se cuenta en cada caso:

1. **Tamaño de los eventos.** Con filas compactas (de 100 a 450 B), las bitácoras ocupan 4.16 TB. Si cada evento guardara la respuesta completa de la pasarela en JSON (alrededor de 1 KB), `transaccion_log` pasaría de 200 a unos 1,200 B por fila y ocuparía unas 6 veces más.
2. **Respaldos.** Retener un respaldo completo por mes durante 5 años suma otros 11.02 TB fuera de la base de datos.
3. **Copias y crecimiento.** Más réplicas o un crecimiento anual del volumen multiplican el total.
4. **Lo que no es base de datos.** No se incluyen los logs HTTP y de aplicación, los registros de WAF y CDN, ni los pósteres e imágenes.

La cifra de 45 TB es razonable si incluye respaldos retenidos, eventos de bitácora pesados y más copias. Para la base de datos de esta propuesta, el tamaño a 5 años es de 5.95 TB, o de 2.69 TB en línea con el almacenamiento en niveles.

## 3.10 Limitaciones

- Los tamaños de fila son estimaciones. Se compararán con el tamaño real de las tablas cuando exista la carga de prueba.
- El reparto del pico es un modelo. El reparto real depende de la frecuencia del sondeo del mapa y de la sala de espera virtual.
