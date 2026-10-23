"""Dimensionamiento de la base de datos de la plataforma IMAX.

Con los datos del enunciado y los supuestos del equipo calcula:
- el reparto del pico de 50,000 TPS entre lecturas y escrituras,
- las filas esperadas por tabla y el almacenamiento mensual y a 5 años,
- los volúmenes que se usan en el estimado de costos cloud.

Uso:
    py docs/calculos/dimensionamiento.py

Escribe los resultados en docs/calculos/dimensionamiento.md.
Unidades: GB = 10^9 bytes, TB = 10^12 bytes.
"""

import datetime
import pathlib

GB = 10**9
TB = 10**12

# ---------------------------------------------------------------------------
# Datos del enunciado
# ---------------------------------------------------------------------------
USUARIOS_CONCURRENTES = 8_000_000
TPS_PICO = 50_000
MINUTOS_PICO = 10
SALAS = 1_500
TITULOS_ACTIVOS = 500
BOLETOS_MES = 15_000_000
ANIOS_RETENCION = 5
BYTES_POR_SOLICITUD = 2_048  # 2 KiB
ENLACE_LEGADO_MBPS = 50
REFERENCIA_TB = 45  # cifra referencial del ejemplo de costos

# ---------------------------------------------------------------------------
# Supuestos del equipo: (valor, justificación)
# ---------------------------------------------------------------------------
SUPUESTOS = {
    "dias_mes": (30, "Mes comercial"),
    "funciones_sala_dia": (5, "Películas de 2 a 2.5 h más limpieza, de 10:00 a 00:00"),
    "asientos_sala": (300, "Sala IMAX típica: de 250 a 500 asientos"),
    "salas_por_sede": (1.1, "La mayoría de los complejos tiene una sola sala IMAX"),
    "zonas_por_sala": (3, "Platea, preferencial, VIP"),
    "titulos_nuevos_mes": (40, "Rotación del catálogo"),
    "tipos_tarifa": (5, "Adulto, niño, tercera edad, estudiante, cortesía"),
    "tipos_dia": (2, "Entre semana y fin de semana"),
    "promociones_vigentes": (200, "2x1 y descuentos por día"),
    "boletos_por_orden": (2.5, "Compra en pareja o en familia"),
    "intentos_pago_por_orden": (1.15, "Alrededor de 13 % de rechazos o reintentos"),
    "bloqueos_por_boleto": (1.5, "Selecciones abandonadas o cambiadas antes de pagar"),
    "eventos_por_bloqueo": (2, "Bloqueo más su desenlace: compra, expiración o liberación"),
    "escaneos_por_boleto": (1.05, "Duplicados, rechazos y reintentos en puerta"),
    "ops_admin_sala_dia": (10, "Cambios de precio y función, cortesías, reembolsos forzados"),
    "tasa_reembolso": (0.01, "1 % de los boletos"),
    "usuarios_iniciales": (20_000_000, "Clientes registrados al arrancar"),
    "usuarios_nuevos_mes": (100_000, "Altas mensuales"),
    "sobrecarga_pagina": (1.15, "Cabecera de página, espacio libre y tuplas muertas"),
    "copias": (4, "Primaria, standby multi-AZ y 2 réplicas de lectura"),
    "meses_bitacora_en_linea": (13, "Año fiscal en curso más un mes de margen"),
    "compresion_archivo": (4, "Compresión de bitácoras en almacenamiento de objetos"),
    "compresion_respaldo": (3, "Compresión típica de un respaldo lógico"),
    # Embudo de una compra completada durante el pico
    "lecturas_cartelera": (4, "Búsqueda y filtros de cartelera"),
    "lecturas_detalle": (2, "Detalle de película y función"),
    "segundos_en_mapa": (40, "Tiempo eligiendo asientos"),
    "intervalo_sondeo_mapa": (2, "Polling corto del mapa (RN-03)"),
    "lecturas_confirmacion": (2, "Confirmación y perfil con el QR"),
    "llamadas_bloqueo": (1.5, "Algunas compras cambian la selección"),
    "sesiones_sin_compra": (3, "En un estreno la mayoría no consigue asiento"),
    "lecturas_sesion_sin_compra": (15, "Navegan y miran el mapa"),
    "fraccion_cacheable_sin_compra": (0.4, "Parte de esas lecturas es cartelera"),
    "acierto_cache": (0.95, "Cartelera y detalle servidos por CDN y caché"),
    "segundos_bloqueo": (120, "Bloqueo temporal de 2 minutos (RN-05)"),
    # Volúmenes para el estimado de costos
    "anios_costos": (3, "Horizonte de la proyección financiera"),
    "recursos_estaticos_por_compra": (20, "Pósteres, estilos y scripts que el navegador no tiene en caché"),
    "kib_respuesta_api": (4, "JSON de cartelera, mapa y confirmación"),
    "kib_recurso_estatico": (50, "Pósteres comprimidos y recursos de la interfaz"),
}
S = {k: v[0] for k, v in SUPUESTOS.items()}

# Bytes por fila (con la cabecera de la tupla) e índices como fracción de los datos
TABLAS = {
    "usuario":               (220, 0.5, "operativa"),
    "sede":                  (300, 0.3, "catalogo"),
    "sala":                  (120, 0.3, "catalogo"),
    "zona":                  (80, 0.3, "catalogo"),
    "asiento":               (60, 0.6, "catalogo"),
    "pelicula":              (1200, 0.2, "catalogo"),
    "tarifa":                (70, 0.4, "catalogo"),
    "promocion":             (200, 0.3, "catalogo"),
    "funcion":               (90, 0.6, "operativa"),
    "ocupacion_asiento":     (70, 0.8, "viva"),
    "orden":                 (130, 0.5, "operativa"),
    "pago":                  (150, 0.5, "operativa"),
    "boleto":                (140, 0.7, "operativa"),
    "reembolso":             (120, 0.4, "operativa"),
    "transaccion_log":       (200, 0.3, "bitacora"),
    "asiento_auditoria_log": (100, 0.3, "bitacora"),
    "acceso_puerta_log":     (110, 0.3, "bitacora"),
    "admin_operacion_audit": (450, 0.3, "bitacora"),
}

# ---------------------------------------------------------------------------
# Pico de 50,000 TPS
# ---------------------------------------------------------------------------
cacheables = (S["lecturas_cartelera"] + S["lecturas_detalle"]
              + S["sesiones_sin_compra"] * S["lecturas_sesion_sin_compra"] * S["fraccion_cacheable_sin_compra"])
tiempo_real = (S["segundos_en_mapa"] / S["intervalo_sondeo_mapa"] + S["lecturas_confirmacion"]
               + S["sesiones_sin_compra"] * S["lecturas_sesion_sin_compra"] * (1 - S["fraccion_cacheable_sin_compra"]))
# Escrituras: bloqueos, crear la orden, pagos y el intento fallido de cada sesión sin compra
escrituras = S["llamadas_bloqueo"] + 1 + S["intentos_pago_por_orden"] + S["sesiones_sin_compra"]
ops_por_compra = cacheables + tiempo_real + escrituras

compras_s = TPS_PICO / ops_por_compra
tps_lecturas = compras_s * (cacheables + tiempo_real)
tps_escrituras = compras_s * escrituras
tps_cache = compras_s * cacheables * S["acierto_cache"]
tps_replicas = compras_s * cacheables * (1 - S["acierto_cache"]) + compras_s * tiempo_real
boletos_s = compras_s * S["boletos_por_orden"]
eventos_tx_orden = 2 + 2 * S["intentos_pago_por_orden"]  # orden creada, emisión y 2 por intento de pago
eventos_asiento_orden = S["boletos_por_orden"] * S["bloqueos_por_boleto"] * S["eventos_por_bloqueo"] + S["sesiones_sin_compra"]
filas_bitacora_s = compras_s * (eventos_tx_orden + eventos_asiento_orden)
bloqueos_vivos = boletos_s * S["bloqueos_por_boleto"] * S["segundos_bloqueo"]
ancho_banda_mbps = TPS_PICO * BYTES_POR_SOLICITUD * 8 / 10**6
asientos_dia = SALAS * S["funciones_sala_dia"] * S["asientos_sala"]
asientos_pedidos = USUARIOS_CONCURRENTES * S["boletos_por_orden"]

assert abs(tps_lecturas + tps_escrituras - TPS_PICO) < 1e-6
assert abs(tps_cache + tps_replicas + tps_escrituras - TPS_PICO) < 1e-6

# ---------------------------------------------------------------------------
# Filas por tabla: existentes al inicio y nuevas por mes (volumen constante)
# ---------------------------------------------------------------------------
sedes = SALAS / S["salas_por_sede"]
ordenes_mes = BOLETOS_MES / S["boletos_por_orden"]
pagos_mes = ordenes_mes * S["intentos_pago_por_orden"]

iniciales = {
    "usuario": S["usuarios_iniciales"], "sede": sedes, "sala": SALAS,
    "zona": SALAS * S["zonas_por_sala"], "asiento": SALAS * S["asientos_sala"],
    "pelicula": TITULOS_ACTIVOS, "tarifa": sedes * S["zonas_por_sala"] * S["tipos_tarifa"] * S["tipos_dia"],
    "promocion": S["promociones_vigentes"],
    "ocupacion_asiento": bloqueos_vivos,  # bloqueos simultáneos del pico; no acumula
}
por_mes = {
    "usuario": S["usuarios_nuevos_mes"], "pelicula": S["titulos_nuevos_mes"],
    "funcion": SALAS * S["funciones_sala_dia"] * S["dias_mes"],
    "orden": ordenes_mes, "pago": pagos_mes, "boleto": BOLETOS_MES,
    "reembolso": BOLETOS_MES * S["tasa_reembolso"],
    "transaccion_log": ordenes_mes * 2 + pagos_mes * 2,
    "asiento_auditoria_log": BOLETOS_MES * S["bloqueos_por_boleto"] * S["eventos_por_bloqueo"],
    "acceso_puerta_log": BOLETOS_MES * S["escaneos_por_boleto"],
    "admin_operacion_audit": SALAS * S["ops_admin_sala_dia"] * S["dias_mes"],
}


def filas(tabla, meses):
    return iniciales.get(tabla, 0) + por_mes.get(tabla, 0) * meses


def bytes_una_copia(tabla, n_filas, con_indices=True):
    tam, indices, _ = TABLAS[tabla]
    datos = n_filas * tam * S["sobrecarga_pagina"]
    return datos * (1 + indices) if con_indices else datos


def bitacoras_comprimidas(meses):
    """GB de datos de bitácora (sin índices) de una cantidad de meses, comprimidos."""
    b = sum(bytes_una_copia(t, por_mes[t] * meses, False) for t in TABLAS if TABLAS[t][2] == "bitacora")
    return b / S["compresion_archivo"] / GB


meses_total = ANIOS_RETENCION * 12
copias = S["copias"]
gb_mes = sum(bytes_una_copia(t, por_mes.get(t, 0)) for t in TABLAS) / GB
tb_anio = [sum(bytes_una_copia(t, filas(t, a * 12)) for t in TABLAS) * copias / TB for a in range(1, 6)]
tb_5_bitacoras = sum(bytes_una_copia(t, filas(t, meses_total)) for t in TABLAS if TABLAS[t][2] == "bitacora") * copias / TB

# Variante en niveles: la BD guarda 13 meses de bitácoras; el resto va comprimido a archivo
en_linea = S["meses_bitacora_en_linea"]
tb_niveles_bd = sum(bytes_una_copia(t, por_mes[t] * en_linea) if TABLAS[t][2] == "bitacora"
                    else bytes_una_copia(t, filas(t, meses_total)) for t in TABLAS) * copias / TB
tb_niveles_archivo = bitacoras_comprimidas(meses_total - en_linea) / 1000

# Referencia: un respaldo completo por mes, retenido 5 años (sin índices, comprimido)
tb_respaldos = sum(sum(bytes_una_copia(t, filas(t, m), False) for t in TABLAS)
                   for m in range(1, meses_total + 1)) / S["compresion_respaldo"] / TB

# Volúmenes para el estimado de costos (al cierre del año 3)
meses_c = S["anios_costos"] * 12
sol_api = ordenes_mes * ops_por_compra
sol_estaticas = ordenes_mes * S["recursos_estaticos_por_compra"]
salida_gb = (sol_api * S["kib_respuesta_api"] + sol_estaticas * S["kib_recurso_estatico"]) * 1024 / GB
bd_gb_por_copia = sum(bytes_una_copia(t, por_mes[t] * en_linea) if TABLAS[t][2] == "bitacora"
                      else bytes_una_copia(t, filas(t, meses_c)) for t in TABLAS) / GB
logs_caliente_gb = bitacoras_comprimidas(en_linea)
logs_archivo_gb = sum(bitacoras_comprimidas(max(0, m - en_linea)) for m in range(1, meses_c + 1)) / meses_c

# ---------------------------------------------------------------------------
# Salida
# ---------------------------------------------------------------------------
salida = []


def n(x, dec=0):
    return f"{x:,.{dec}f}"


def tabla(titulo, encabezados, filas_tabla):
    salida.extend([f"## {titulo}", "", "| " + " | ".join(encabezados) + " |", "|" + "---|" * len(encabezados)])
    salida.extend("| " + " | ".join(str(c) for c in f) + " |" for f in filas_tabla)
    salida.append("")


tabla("Supuestos", ["Supuesto", "Valor", "Justificación"], [[k, v[0], v[1]] for k, v in SUPUESTOS.items()])
tabla("Tamaño de fila por tabla", ["Tabla", "Clase", "Bytes por fila", "Índices / datos"],
      [[t, v[2], v[0], v[1]] for t, v in TABLAS.items()])
tabla("Volúmenes por mes", ["Tabla", "Filas por mes"], [[t, n(v)] for t, v in por_mes.items()])
tabla("Pico de 50,000 TPS", ["Concepto", "Valor"], [
    ["Operaciones por compra completada", n(ops_por_compra, 2)],
    ["Compras completadas por segundo", n(compras_s, 1)],
    ["TPS de lectura", n(tps_lecturas)],
    ["TPS de escritura", n(tps_escrituras)],
    ["Porcentaje de lectura", n(100 * tps_lecturas / TPS_PICO, 1) + " %"],
    ["TPS resueltas por CDN y caché", n(tps_cache)],
    ["TPS a réplicas de lectura", n(tps_replicas)],
    ["TPS a la primaria (escrituras)", n(tps_escrituras)],
    ["Boletos vendidos por segundo", n(boletos_s)],
    ["Boletos vendidos en los 10 minutos", n(boletos_s * MINUTOS_PICO * 60)],
    ["Filas de bitácora insertadas por segundo", n(filas_bitacora_s)],
    ["Bloqueos vivos simultáneos", n(bloqueos_vivos)],
    ["Segundos entre solicitudes de un usuario concurrente", n(USUARIOS_CONCURRENTES / TPS_PICO)],
    ["Ancho de banda de entrada (Mbps)", n(ancho_banda_mbps, 1)],
    ["Veces el enlace legado de 50 Mbps", n(ancho_banda_mbps / ENLACE_LEGADO_MBPS, 1)],
])
tabla("Inventario del día de estreno", ["Concepto", "Valor"], [
    ["Asientos disponibles en el día", n(asientos_dia)],
    ["Asientos que piden los usuarios concurrentes", n(asientos_pedidos)],
    ["Demanda sobre oferta", n(asientos_pedidos / asientos_dia, 1)],
    ["Minutos para agotar el día al ritmo del pico", n(asientos_dia / boletos_s / 60, 1)],
])
tabla("Filas por tabla", ["Tabla", "Clase", "Al inicio", "Nuevas por mes", "1 año", "3 años", "5 años"],
      [[t, v[2], n(iniciales.get(t, 0)), n(por_mes.get(t, 0)), n(filas(t, 12)), n(filas(t, 36)), n(filas(t, 60))]
       for t, v in TABLAS.items()])
tabla("Almacenamiento por tabla (GB)",
      ["Tabla", "Crecimiento por mes", "Datos 5 años", "Índices 5 años", "Una copia 5 años", f"{copias} copias 5 años"],
      [[t, n(bytes_una_copia(t, por_mes.get(t, 0)) / GB, 2),
        n(bytes_una_copia(t, filas(t, 60), False) / GB, 1),
        n((bytes_una_copia(t, filas(t, 60)) - bytes_una_copia(t, filas(t, 60), False)) / GB, 1),
        n(bytes_una_copia(t, filas(t, 60)) / GB, 1), n(bytes_una_copia(t, filas(t, 60)) * copias / GB, 1)]
       for t in TABLAS])
tabla("Acumulado por año (con copias)", ["Año", "TB"], [[a + 1, n(tb, 2)] for a, tb in enumerate(tb_anio)])
tabla("Resumen de almacenamiento", ["Concepto", "Valor"], [
    ["Crecimiento por mes, una copia (GB)", n(gb_mes, 1)],
    [f"Crecimiento por mes, {copias} copias (GB)", n(gb_mes * copias, 1)],
    ["Acumulado 5 años, una copia (TB)", n(tb_anio[-1] / copias, 2)],
    [f"Acumulado 5 años, {copias} copias (TB)", n(tb_anio[-1], 2)],
    ["  de ello, bitácoras (TB)", n(tb_5_bitacoras, 2)],
    ["  de ello, tablas operativas y catálogo (TB)", n(tb_anio[-1] - tb_5_bitacoras, 2)],
    [f"En niveles: BD con {en_linea} meses de bitácoras (TB)", n(tb_niveles_bd, 2)],
    ["En niveles: archivo comprimido de bitácoras (TB)", n(tb_niveles_archivo, 2)],
    ["Referencia: respaldos completos mensuales retenidos 5 años, comprimidos (TB)", n(tb_respaldos, 2)],
    ["Acumulado con copias frente a los 45 TB del enunciado", n(tb_anio[-1] / REFERENCIA_TB, 2) + " veces"],
])
tabla("Volúmenes para el estimado de costos (hoja Supuestos)", ["Celda", "Concepto", "Valor", "Unidad"], [
    ["B9", "Solicitudes mensuales al borde (API + recursos estáticos)", n((sol_api + sol_estaticas) / 10**6, 1), "millones/mes"],
    ["B10", "Salida de datos a clientes", n(salida_gb / 1024, 2), "TB/mes (1 TB = 1,024 GB)"],
    ["B13", f"BD por copia al cierre del año {S['anios_costos']}, con niveles", n(bd_gb_por_copia), "GB"],
    ["B23", f"Logs en capa caliente: copia comprimida de {en_linea} meses", n(logs_caliente_gb), "GB"],
    ["B24", f"Logs en capa de archivo: promedio de {S['anios_costos']} años", n(logs_archivo_gb), "GB"],
])

ruta = pathlib.Path(__file__).with_name("dimensionamiento.md")
encabezado = ["# Resultados del dimensionamiento", "",
              f"Generado el {datetime.date.today().isoformat()} con `py docs/calculos/dimensionamiento.py`.", ""]
ruta.write_text("\n".join(encabezado + salida), encoding="utf-8", newline="\n")
print("Escrito", ruta)
