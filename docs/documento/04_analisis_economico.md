# 4. Análisis económico a 3 años

## 4.1 Alcance y fuente de los precios

Se comparan dos nubes, Amazon Web Services (región us-east-1) y Microsoft Azure (región East US), en los cuatro bloques que pide la licitación: base de datos relacional administrada, almacenamiento de las bitácoras por 5 años, balanceo con WAF y el cómputo de la aplicación. Cada nube se evalúa con precio por uso (On-Demand) y con reserva de 1 año.

**Fuente:** precios de lista públicos de los proveedores y referencias de mercado, consultados el 22/10/2026. El detalle de cada precio unitario, su nivel de confianza y su enlace está en la hoja `docs/fuentes/estimado_cloud_imax.xlsx` (hojas Supuestos y Fuentes) y en `docs/fuentes/fuentes.md`. Moneda: USD. Convenciones de la hoja: 730 horas por mes y 1 TB = 1,024 GB.

**Cómo se obtuvieron las cifras.** La hoja original se guarda sin cambios en `docs/fuentes`. El script `docs/calculos/costos_cloud.py` hace una copia, `docs/calculos/costos_cloud.xlsx`, y reemplaza solo cinco volúmenes de la hoja Supuestos por los del dimensionamiento (sección 3). El libro se recalculó en LibreOffice Calc. Los precios unitarios y las fórmulas no se modificaron.

## 4.2 Configuración y volúmenes evaluados

| Componente | AWS | Azure |
|---|---|---|
| Base de datos primaria | RDS for PostgreSQL db.r6g.8xlarge (32 vCPU), Multi-AZ | PostgreSQL Flexible Server E32ds_v5 (32 vCPU), HA zona-redundante |
| Réplicas de lectura | 2 × db.r6g.4xlarge (16 vCPU) | 2 × E16ds_v5 (16 vCPU) |
| Réplica de DR en otra región | db.r6g.4xlarge en us-west-2 | E16ds_v5 en West US 2 |
| Aplicación | EKS, 4 nodos m6i.4xlarge 24/7 y 4 más durante 36 h de pico al mes | AKS, 4 nodos D16s_v5 24/7 y 4 más durante 36 h de pico al mes |
| Bitácoras a 5 años | S3 Standard (capa caliente) y S3 Glacier Flexible Retrieval (archivo) | Blob Storage Hot y Archive |
| Borde, balanceo y WAF | CloudFront, AWS WAF y Application Load Balancer | Front Door Premium (WAF incluido) y Standard Load Balancer |
| Caché de lectura (informativo) | ElastiCache, 2 nodos cache.r6g.xlarge | Sin precio en la hoja |

Volúmenes escritos en la hoja Supuestos, tomados del dimensionamiento con un horizonte de 3 años:

| Celda | Concepto | Valor | Origen |
|---|---|---|---|
| B9 | Solicitudes mensuales al borde | 597.9 millones | 6 M de órdenes × 79.65 solicitudes a la API por compra, más 20 recursos estáticos por compra |
| B10 | Salida de datos a clientes | 7.91 TB | 4 KiB por respuesta de la API y 50 KiB por recurso estático |
| B13 | Almacenamiento de la BD por copia | 497 GB | Tablas operativas al cierre del año 3 más los últimos 13 meses de bitácoras (sección 3.8, almacenamiento en niveles) |
| B23 | Logs en capa caliente | 43 GB | Copia comprimida e inmutable de los 13 meses de bitácoras que siguen en la BD |
| B24 | Logs en capa de archivo | 26 GB | Promedio, durante los 3 años, de las particiones de más de 13 meses, comprimidas 4:1 |

La hoja factura el almacenamiento de la BD en 5 copias: la primaria y su standby (factor Multi-AZ de 2), las 2 réplicas de lectura y la réplica de DR. La sección 3 contó 4 copias porque no incluía la de DR.

## 4.3 Comparativa de costos mensuales

| Concepto (USD por mes) | AWS On-Demand | AWS Reserva 1 año | Azure On-Demand | Azure Reserva 1 año |
|---|---|---|---|---|
| Base de datos | 8,563.90 | 4,933.90 | 9,028.75 | 5,524.74 |
| Cómputo de la aplicación | 2,426.15 | 1,751.63 | 2,426.15 | 1,567.67 |
| Bitácoras a 5 años | 402.08 | 402.08 | 392.92 | 392.92 |
| Borde, balanceo y WAF | 2,009.51 | 2,009.51 | 1,983.95 | 1,983.95 |
| **Total base (sin DR ni caché)** | **13,401.65** | **9,097.13** | **13,831.76** | **9,469.28** |
| Réplica de DR entre regiones | 1,370.15 | 765.15 | 1,517.15 | 933.15 |
| **Total base + DR (comparable entre nubes)** | **14,771.80** | **9,862.28** | **15,348.92** | **10,402.44** |
| Caché de lectura (informativo) | 599.33 | 407.54 | Pendiente | Pendiente |

La reserva de 1 año se aplica a la base de datos y a los nodos base de la aplicación. Los nodos de pico, las bitácoras y el borde quedan a precio de lista.

## 4.4 Proyección a 3 años: CAPEX y OPEX

El OPEX se calcula sobre el total mensual base + DR, con un crecimiento de volumen del 10 % anual, igual que en el ejemplo del enunciado. El CAPEX inicial de US$15,000, por consultoría de arquitectura e implementación, también es el valor de referencia del enunciado.

| Concepto (USD) | AWS On-Demand | AWS Reserva 1 año | Azure On-Demand | Azure Reserva 1 año |
|---|---|---|---|---|
| OPEX año 1 | 177,261.61 | 118,347.37 | 184,187.03 | 124,829.27 |
| OPEX año 2 | 194,987.77 | 130,182.11 | 202,605.73 | 137,312.19 |
| OPEX año 3 | 214,486.55 | 143,200.32 | 222,866.30 | 151,043.41 |
| OPEX acumulado a 3 años | 586,735.94 | 391,729.80 | 609,659.06 | 413,184.87 |
| CAPEX inicial | 15,000.00 | 15,000.00 | 15,000.00 | 15,000.00 |
| **Costo total a 3 años** | **601,735.94** | **406,729.80** | **624,659.06** | **428,184.87** |

## 4.5 Costo por millón de transacciones y por boleto

| Costo unitario (sobre el total mensual base + DR) | AWS On-Demand | AWS Reserva 1 año | Azure On-Demand | Azure Reserva 1 año |
|---|---|---|---|---|
| USD por millón de solicitudes (transacciones al borde) | 24.71 | 16.49 | 25.67 | 17.40 |
| USD por millón de boletos | 984.79 | 657.49 | 1,023.26 | 693.50 |
| USD por boleto | 0.000985 | 0.000657 | 0.001023 | 0.000693 |

## 4.6 Elección de proveedor

| Comparación | Valor |
|---|---|
| Azure frente a AWS, On-Demand | +3.9 % mensual |
| Azure frente a AWS, reserva 1 año | +5.5 % mensual; US$21,455.07 más a 3 años |
| Ahorro de la reserva 1 año en AWS | 33.2 % mensual; US$195,006.13 a 3 años |
| Ahorro de la reserva 1 año en Azure | 32.2 % mensual |

**Se recomienda AWS con reserva de 1 año** para la base de datos y los nodos base, con un costo de US$9,862.28 por mes y US$406,729.80 a 3 años. Las razones:

1. **La diferencia entre nubes es pequeña.** Azure cuesta un 5.5 % más con reserva y un 3.9 % más On-Demand.
2. **El factor decisivo es la modalidad de pago, no la nube.** Pasar de On-Demand a reserva de 1 año ahorra un tercio del costo, US$195,006 a 3 años en AWS: unas nueve veces la diferencia entre nubes. Por eso la recomendación va acompañada de comprometer la capacidad base con reserva y dejar solo los picos a precio por uso.
3. **AWS ofrece en la hoja la caché de lectura con precio** (US$407.54 al mes con reserva). En Azure ese componente sigue sin precio.

Las salvedades de la sección 4.9 (procesador de la BD y capa del balanceador) afectan la comparación en ambos sentidos, y ninguna alcanza para invertir una diferencia del 5 %. La decisión debe revalidarse con una cotización formal antes de firmar.

## 4.7 Retorno de la inversión (ROI)

- **Costo por boleto.** Con AWS y reserva de 1 año, la infraestructura completa (BD, aplicación, bitácoras a 5 años, borde, WAF y DR) cuesta US$0.000657 por boleto, unos US$657 por millón de boletos. Es menos de la mitad de la referencia del enunciado (US$0.0015 por boleto).
- **Costo de no tenerla.** Al ritmo del pico se venden unos 94,000 boletos por minuto (sección 3.4). El costo de todo un mes de infraestructura (US$9,862.28) es menor que la venta perdida en un solo minuto de caída del estreno, siempre que el boleto valga más de US$0.105 (9,862.28 ÷ 94,162 boletos). El costo total a 3 años, CAPEX incluido (US$406,729.80), equivale a la venta de un minuto de pico si el boleto promedio vale US$4.32 (406,729.80 ÷ 94,162).
- **Frente a la propuesta legada.** El escenario legado no tiene costo de nube, pero se cae en el primer minuto (sección 1). La inversión propuesta paga la continuidad de la venta, la integridad de los pagos (PCI DSS) y la retención fiscal de 5 años.

## 4.8 Supuestos declarados

Las celdas marcadas en amarillo en la hoja son supuestos del equipo. Se presentan así: **Supuesto del equipo, precio de lista público de referencia.** No son cifras oficiales de las calculadoras de los proveedores.

| Celda | Concepto | Valor | Tipo |
|---|---|---|---|
| Supuestos!B33 | RDS db.r6g.8xlarge, reserva 1 año, tarifa efectiva | US$1,416 por mes | Supuesto del equipo, precio de lista público de referencia |
| Supuestos!B46 | Transición de ciclo de vida a Glacier | US$0.03 por 1,000 | Supuesto del equipo, precio de lista público de referencia |
| Supuestos!B67 | Almacenamiento de PostgreSQL Flexible Server (Azure) | US$0.115 por GB-mes (igual al de AWS) | Supuesto del equipo, precio de lista público de referencia |
| Supuestos!B68 | Backup de PostgreSQL Flexible Server (Azure) | US$0.095 por GB-mes (igual al de AWS) | Supuesto del equipo, precio de lista público de referencia |
| Supuestos!B70 | VM D16s_v5, reserva 1 año | US$0.474 por hora | Supuesto del equipo, precio de lista público de referencia |
| Supuestos!B71 | AKS, plano de control Standard | US$0.10 por hora | Supuesto del equipo, precio de lista público de referencia |
| Supuestos!B74 a B76 | Operaciones de Blob Hot y Archive, recuperación de Archive | US$0.065 y US$0.13 por 10,000; US$0.02 por GB | Supuesto del equipo, precio de lista público de referencia |
| Supuestos!B78 | Front Door Premium, solicitudes (tarifa del primer tramo aplicada a todo el volumen) | US$0.015 por 10,000 | Supuesto del equipo, precio de lista público de referencia |
| Supuestos!B83 y B84 | Standard Load Balancer, horas y datos procesados | US$0.025 por hora; US$0.005 por GB | Supuesto del equipo, precio de lista público de referencia |
| Supuestos!B11, B14 a B22, B25 a B28 | Configuración: tráfico al origen, réplicas, backup facturable, IOPS, nodos, horas de pico, LCU, reglas de WAF, nodos de caché, operaciones de logs | Ver la hoja | Supuesto del equipo |
| Supuestos!B9, B10, B13, B23, B24 | Volúmenes | Ver la sección 4.2 | Calculado en el dimensionamiento (sección 3) |
| Supuestos!B30 | CAPEX inicial | US$15,000 | Valor de referencia del enunciado |

## 4.9 Limitaciones

- **Graviton frente a Intel.** En la base de datos, AWS usa procesadores Graviton (ARM, db.r6g) y Azure usa Intel (x86, E32ds_v5), porque Azure no ofrece ARM en la familia optimizada para memoria. En x86, db.r6i.8xlarge y E32ds_v5 cuestan lo mismo en On-Demand (US$2,920 por mes en una sola zona). Parte de la ventaja de AWS viene de usar Graviton.
- **Balanceador de capa 4 frente a capa 7.** El Standard Load Balancer de Azure es de capa 4 y no equivale al Application Load Balancer de AWS, que es de capa 7. En Azure la capa 7 y el WAF los cubre Front Door Premium.
- **Azure sin precio de Redis ni de IOPS.** La caché de lectura de Azure no tiene precio en la hoja, y las IOPS adicionales de la BD están en cero. Por eso el total comparable excluye la caché, y el costo de Azure podría subir.
- **Reservas de 1 año como tarifa efectiva.** Las cifras de reserva parecen tarifas efectivas con pago total por adelantado, que no es lo mismo que la tarifa sin pago inicial. Sin pago inicial, el costo mensual sería mayor y el ahorro frente a On-Demand, menor.
- **Respaldos mensuales a 5 años.** La hoja factura 1 TB de respaldo por encima del gratuito, pero no el respaldo completo mensual retenido 5 años en la capa de archivo. Al precio de archivo de la misma hoja suma unos US$5 al mes en promedio durante los 3 años (sección 10.1), el 0.05 % del total, así que no cambia la comparación.
- **Instancias sin redimensionar.** Se recalcularon solo los volúmenes. La configuración de instancias (32 vCPU en la primaria, 2 réplicas de 16 vCPU, 8 nodos de aplicación en el pico) es la de la hoja, y se valida con las pruebas de rendimiento del modelo físico.

## 4.10 Fuentes

Precios de lista públicos de los proveedores y referencias de mercado, consultados el 22/10/2026. La lista completa de enlaces, por precio y con su tipo (oficial o de terceros), está en `docs/fuentes/fuentes.md` y en la hoja Fuentes de `docs/fuentes/estimado_cloud_imax.xlsx`. Las páginas oficiales de referencia son:

- AWS Pricing Calculator: https://calculator.aws/
- Amazon RDS for PostgreSQL, precios: https://aws.amazon.com/rds/postgresql/pricing/
- AWS WAF, precios: https://aws.amazon.com/waf/pricing
- Azure Pricing Calculator: https://azure.microsoft.com/pricing/calculator/
- Azure Retail Prices API: https://learn.microsoft.com/en-us/rest/api/cost-management/retail-prices/azure-retail-prices
- Azure Front Door, precios: https://learn.microsoft.com/en-us/azure/frontdoor/understanding-pricing
