"""Cifras de operación de la sección 10: presupuesto de caída del SLA y costo de archivar
los respaldos mensuales.

Uso:
    py docs/calculos/operacion.py

El volumen de respaldos se lee de dimensionamiento.md (hay que correr antes
dimensionamiento.py si cambian los supuestos). El precio del archivo es el de la hoja
Supuestos del estimado de costos (celda B44, S3 Glacier Flexible Retrieval).
"""

import pathlib
import re

MINUTOS_ANIO = 365 * 24 * 60          # 525,600
MINUTOS_MES = MINUTOS_ANIO / 12       # 43,800

SLA_OBJETIVO = 0.9999                 # requisito del enunciado
SLA_PROVEEDOR_BD = 0.9995             # RDS Multi-AZ, compromiso mensual del proveedor
CONMUTACION_MULTI_AZ_MIN = 2          # peor caso típico de la documentación (60 a 120 s)
RTO_MIN = 5                           # requisito del enunciado

PRECIO_ARCHIVO_GB_MES = 0.0036        # Supuestos!B44, US$ por GB-mes
COSTO_MENSUAL_BASE_DR = 9862.28       # sección 4, AWS con reserva de 1 año
TB_RESPALDOS_5_ANIOS = 11.02          # sección 3.8


def caida_permitida(sla, minutos):
    return (1 - sla) * minutos


def respaldos_promedio_gb():
    texto = pathlib.Path(__file__).with_name("dimensionamiento.md").read_text(encoding="utf-8")
    fila = re.search(r"Respaldos mensuales retenidos, promedio de 3 años \(GB\) \| ([\d,]+)", texto)
    return float(fila.group(1).replace(",", ""))


print("Caída permitida")
for nombre, sla in [("Objetivo 99.99 %", SLA_OBJETIVO), ("Proveedor BD 99.95 %", SLA_PROVEEDOR_BD)]:
    print(f"  {nombre}: {caida_permitida(sla, MINUTOS_ANIO):.2f} min al año, "
          f"{caida_permitida(sla, MINUTOS_MES):.2f} min al mes")

presupuesto_mes = caida_permitida(SLA_OBJETIVO, MINUTOS_MES)
print("\nFallas que caben en el presupuesto mensual del 99.99 %")
print(f"  Conmutaciones Multi-AZ de {CONMUTACION_MULTI_AZ_MIN} min: {presupuesto_mes / CONMUTACION_MULTI_AZ_MIN:.1f}")
print(f"  Fallas que agotan el RTO de {RTO_MIN} min: {presupuesto_mes / RTO_MIN:.2f}")
print(f"  Holgura de la conmutación Multi-AZ frente al RTO: {RTO_MIN - CONMUTACION_MULTI_AZ_MIN} min")

promedio = respaldos_promedio_gb()
costo_promedio = promedio * PRECIO_ARCHIVO_GB_MES
costo_anio_5 = TB_RESPALDOS_5_ANIOS * 1000 * PRECIO_ARCHIVO_GB_MES
print("\nRespaldos mensuales en la capa de archivo")
print(f"  Volumen promedio en 3 años: {promedio:,.0f} GB, US${costo_promedio:,.2f} al mes "
      f"({100 * costo_promedio / COSTO_MENSUAL_BASE_DR:.2f} % del costo mensual)")
print(f"  Al cierre del año 5: {TB_RESPALDOS_5_ANIOS} TB, US${costo_anio_5:,.2f} al mes")
print(f"  A 3 años: US${costo_promedio * 36:,.2f}")
