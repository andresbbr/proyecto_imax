# Fuentes de la estimación de costos cloud (AWS vs Azure)

Fecha de consulta: 22/10/2026. Regiones: AWS us-east-1, Azure East US. Moneda: USD. Convención: 730 h/mes y 1 TB = 1,024 GB.

Estado: estimación provisional con precios de lista citados por terceros. No sustituye a las calculadoras oficiales. Las celdas en amarillo de la hoja Supuestos deben verificarse antes de citarlas en el documento.

Marcador para el documento final: `[ESTIMADO, VERIFICAR EN CALCULADORA OFICIAL]`

## Configuración usada (provisional, a reemplazar con la Etapa 1)

| Concepto | Valor |
|---|---|
| Solicitudes al borde | 1,000 millones/mes |
| Salida de datos a clientes | 15 TB/mes |
| BD | 1 TB, primaria 32 vCPU con alta disponibilidad, 2 réplicas de lectura de 16 vCPU |
| Cómputo K8s | 4 nodos base 24/7 de 16 vCPU, 4 nodos de pico durante 36 h/mes |
| Logs | 2 TB en capa caliente, 20 TB en archivo (promedio de 3 años) |
| Crecimiento anual | 10% (ejemplo del enunciado) |
| CAPEX | $15,000 (ejemplo del enunciado) |

## Totales mensuales (USD)

| Concepto | AWS On-Demand | AWS Reserva 1 año | Azure On-Demand | Azure Reserva 1 año |
|---|---|---|---|---|
| Base de datos | 8,806 | 5,176 | 9,211 | 5,707 |
| Cómputo de la aplicación | 2,426 | 1,752 | 2,426 | 1,568 |
| Logs a 5 años | 522 | 522 | 455 | 455 |
| Borde, balanceo y WAF | 3,244 | 3,244 | 3,103 | 3,103 |
| Total base | 14,999 | 10,694 | 15,194 | 10,832 |
| DR entre regiones (opcional) | 1,431 | 826 | 1,578 | 994 |
| Total base + DR | 16,429 | 11,520 | 16,772 | 11,826 |
| Costo acumulado a 3 años (con CAPEX) | 667,578 | 472,572 | 681,184 | 484,709 |

## Fuentes de AWS

| Para qué | URL | Tipo |
|---|---|---|
| Calculadora oficial (verificar aquí) | https://calculator.aws/ | Oficial |
| Estructura de precios RDS PostgreSQL | https://aws.amazon.com/rds/postgresql/pricing/ | Oficial |
| RDS db.r6g.8xlarge | https://www.bytebase.com/dbcost/rds/instance/db.r6g.8xlarge/ | Terceros |
| RDS db.r6g.16xlarge (verificación del factor) | https://www.bytebase.com/dbcost/rds/instance/db.r6g.16xlarge/ | Terceros |
| RDS db.r6i.8xlarge (variante x86) | https://www.bytebase.com/dbcost/rds/instance/db.r6i.8xlarge/ | Terceros |
| RDS: gp3, backup, IOPS, Multi-AZ | https://www.usage.ai/blogs/aws/reserved-instances/rds/pricing-calculator/ | Terceros |
| RDS: Multi-AZ y backup | https://swyftstack.com/blog/aws-rds-pricing-explained | Terceros |
| EC2 m6i.4xlarge | https://calculator.holori.com/aws/ec2/m6i.4xlarge | Terceros |
| EC2 m6i.4xlarge reservado | https://www.devzero.io/instances/aws/m6i.4xlarge | Terceros |
| EKS, plano de control | https://aws.amazon.com/blogs/containers/amazon-eks-extended-support-for-kubernetes-versions-pricing/ | Oficial |
| S3 Standard y Glacier | https://www.devzero.io/blog/aws-s3-pricing | Terceros |
| S3: PUT y recuperación | https://upstash.com/blog/aws-s3-pricing-explained-2026 | Terceros |
| CloudFront: transferencia y solicitudes | https://perfsys.com/blog/cloudfront-pricing-guide/ | Terceros |
| CloudFront: tramos | https://egresscost.com/aws/cloudfront-pricing | Terceros |
| AWS WAF | https://aws.amazon.com/waf/pricing | Oficial |
| AWS WAF: tarifa por millón de solicitudes | https://aws.github.io/aws-security-services-best-practices/ja/guides/waf/waf-cost/docs/ | Oficial |
| ALB y CloudFront (resumen) | https://dev.to/eddiesegal/amazon-infrastructure-services-build-your-budget-for-the-cloud-1852 | Terceros |
| ElastiCache cache.r6g.2xlarge | https://calculator.holori.com/aws/elasticache/cache.r6g.2xlarge | Terceros |

## Fuentes de Azure

| Para qué | URL | Tipo |
|---|---|---|
| Calculadora oficial (verificar aquí) | https://azure.microsoft.com/pricing/calculator/ | Oficial |
| API oficial de precios | https://learn.microsoft.com/en-us/rest/api/cost-management/retail-prices/azure-retail-prices | Oficial |
| PostgreSQL Flexible Server E32ds_v5 | https://www.bytebase.com/dbcost/azure-flexible/instance/E32ds_v5/ | Terceros |
| PostgreSQL: comparación de 32 vCPU | https://www.bytebase.com/dbcost/azure-flexible/compare/32-vcpu/ | Terceros |
| PostgreSQL: HA, backups, IOPS | https://www.nops.io/blog/azure-database-postgresql-cost-optimization/ | Terceros |
| VM Standard_D16s_v5 | https://calculator.holori.com/azure/vm/standard-d16s-v5/eastus | Terceros |
| VM Standard_D16s_v5 reservada | https://www.devzero.io/instances/azure/Standard_D16s_v5 | Terceros |
| Front Door: cuotas base | https://learn.microsoft.com/en-us/azure/frontdoor/understanding-pricing | Oficial |
| Front Door: WAF incluido en Premium | https://learn.microsoft.com/en-us/azure/frontdoor/compare-cdn-front-door-price | Oficial |
| Front Door: tarifas por GB y solicitudes | https://us.fitgap.com/products/azure-front-door | Terceros |
| Front Door: solicitudes Premium | https://blog.cdnsun.com/microsoft-azure-front-door-pricing/ | Terceros |
| Blob Hot LRS | https://lucidity.cloud/feeds/blog/azure-storage-cost | Terceros |
| Blob Archive y recuperación | https://learn.microsoft.com/en-us/answers/questions/866712/billing-question-on-azure-blob-storage | Terceros |
| Blob: operaciones | https://cloudtweaks.com/2023/06/understanding-azure-blob-storage-pricing/ | Terceros |
| Standard Load Balancer | https://msandbu.org/azure-standard-load-balancer/ | Terceros |

## Pendiente de verificar en las calculadoras oficiales

1. Azure: precio del almacenamiento de PostgreSQL Flexible Server, del backup y de las IOPS adicionales. Hoy son provisionales (iguales a AWS) o están en cero.
2. Azure: precio de AKS Standard (se asumió $0.10 por hora), y del caché Redis (no incluido).
3. Azure Front Door: tarifa de solicitudes por encima de 250 millones al mes (se aplicó la tarifa del primer tramo a todo el volumen).
4. Azure: operaciones de Blob (fuente de 2023) y Standard Load Balancer (fuente de 2018).
5. Ambas nubes: las cifras de reserva de 1 año parecen tarifas efectivas con pago total adelantado. Sin pago inicial serían mayores.
6. AWS: las IOPS adicionales de gp3 (9,000) pueden ser cero si el volumen ya las incluye.
7. AWS: la transición a Glacier ($0.03 por 1,000) se infirió de una tabla.

## Salvedades de comparabilidad

- AWS usa Graviton (r6g) en la BD y Azure usa Intel (E32ds_v5). En x86, db.r6i.8xlarge y E32ds_v5 cuestan lo mismo en on-demand ($2,920 al mes, single-AZ).
- El Standard Load Balancer de Azure es de capa 4 y el ALB de AWS es de capa 7. En Azure, Front Door Premium cubre la capa 7 y el WAF.
- Las cifras del enunciado ($24,000 y $22,850, 45 TB) son referenciales y no se reproducen aquí.
