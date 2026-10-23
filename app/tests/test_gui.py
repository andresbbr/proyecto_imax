"""Pruebas de la interfaz con Playwright (Chromium).

Requisitos: base inicializada con datos de demostración y la aplicación corriendo.

    py -m uvicorn app.main:app --port 8000
    py -m pytest app/tests -v

Las pruebas programan sus propias funciones en la Sala IMAX 2 de San José y al empezar
cancelan las que hayan quedado de una corrida anterior.
"""

import datetime
import os
import re
import time

import psycopg
import pytest
from playwright.sync_api import expect

from app import config

URL = os.environ.get("IMAX_URL", "http://127.0.0.1:8000")
CONTRASENA = "imax2026"
HORA_LOCAL = datetime.timezone(datetime.timedelta(hours=-6))


# Apoyo -----------------------------------------------------------------------------------

def sql(consulta, parametros=()):
    """Consulta directa como dueño de la base, solo para preparar y revisar datos de prueba."""
    with psycopg.connect(host="localhost", port=config.ENV.get("POSTGRES_PORT", "5433"),
                         dbname=config.ENV.get("POSTGRES_DB", "imax"), user=config.ENV["POSTGRES_USER"],
                         password=config.ENV["POSTGRES_PASSWORD"], autocommit=True) as con:
        cur = con.execute(consulta, parametros)
        return cur.fetchall() if cur.description else None


def entrar(page, email):
    page.goto(f"{URL}/login")
    page.fill("input[name=email]", email)
    page.fill("input[name=contrasena]", CONTRASENA)
    page.click("button[type=submit]")
    expect(page.locator(".sesion")).to_contain_text("Salir")


def bloquear(page, id_funcion, cantidad=1):
    """Elige los primeros asientos disponibles del mapa y los bloquea. Devuelve el id de la orden."""
    page.goto(f"{URL}/funcion/{id_funcion}")
    page.wait_for_selector(".asiento.disponible")
    asientos = page.locator(".asiento.disponible")
    elegidos = [asientos.nth(i).get_attribute("data-id") for i in range(cantidad)]
    for id_asiento in elegidos:
        page.click(f".asiento[data-id='{id_asiento}']")
    page.click("#bloquear")
    page.wait_for_url(re.compile(r"/orden/\d+$"))
    return int(page.url.rsplit("/", 1)[1]), elegidos


def pagar(page, numero):
    page.select_option("#metodo", "tarjeta_credito")
    page.fill("#numero-tarjeta", numero)
    page.click("#pagar")


def comprar(page, id_funcion):
    """Compra aprobada de un asiento. Devuelve el código QR del boleto."""
    bloquear(page, id_funcion)
    pagar(page, "4242 4242 4242 4242")
    page.wait_for_url(re.compile(r"/confirmacion$"))
    return page.locator(".boleto .codigo").first.inner_text().strip()


def escanear(page, id_puerta, codigo):
    page.goto(f"{URL}/puerta")
    page.select_option("select[name=id_puerta]", str(id_puerta))
    page.fill("input[name=codigo_qr]", codigo)
    page.click("button[type=submit]")
    return page.locator("#resultado")


def id_admin():
    return sql("select id_usuario from cine.usuario where email = 'admin@imax.demo'")[0][0]


# Datos de prueba ---------------------------------------------------------------------------

@pytest.fixture(scope="module")
def salas():
    filas = sql("""
        select s.nombre, s.id_sala, pu.id_puerta from cine.sala s
        join cine.sede se on se.id_sede = s.id_sede join cine.puerta pu on pu.id_sala = s.id_sala
        where se.nombre = 'IMAX San José'""")
    return {nombre: {"id_sala": id_sala, "id_puerta": id_puerta} for nombre, id_sala, id_puerta in filas}


@pytest.fixture(scope="module", autouse=True)
def sala_2_libre(salas):
    """Cancela las funciones que quedaron de corridas anteriores en la Sala IMAX 2."""
    def limpiar():
        sql(f"""
            select cine.establecer_contexto({id_admin()}, '127.0.0.1'),
                   cine.cancelar_funcion(id_funcion, 'Limpieza de pruebas de la interfaz')
            from cine.funcion where id_sala = %s and estado = 'programada' and fin > now()""",
            (salas["Sala IMAX 2"]["id_sala"],))
    limpiar()
    yield
    limpiar()


@pytest.fixture(scope="module")
def funcion_futura(salas):
    """Una función de la Sala IMAX 1 que empieza en más de 3 horas (fuera de la ventana de ingreso)."""
    return sql("""
        select id_funcion from cine.funcion
        where id_sala = %s and estado = 'programada' and inicio > now() + interval '3 hours'
        order by inicio limit 1""", (salas["Sala IMAX 1"]["id_sala"],))[0][0]


def programar_funcion(page, id_sala, minutos):
    """Programa desde el panel una función en la sala indicada que empieza en `minutos`."""
    inicio = datetime.datetime.now(HORA_LOCAL) + datetime.timedelta(minutes=minutos)
    page.goto(f"{URL}/admin/funciones")
    page.select_option("select[name=id_sala]", str(id_sala))
    page.fill("input[name=inicio]", inicio.strftime("%Y-%m-%dT%H:%M"))
    page.click("button:has-text('Programar')")
    return page.locator(".aviso").first


@pytest.fixture(scope="module")
def funcion_en_ventana(browser, salas):
    """Función de la Sala IMAX 2 que empieza en 10 minutos, creada desde el panel de administración."""
    contexto = browser.new_context()
    page = contexto.new_page()
    entrar(page, "admin@imax.demo")
    expect(programar_funcion(page, salas["Sala IMAX 2"]["id_sala"], 10)).to_contain_text("Función programada")
    contexto.close()
    return sql("select max(id_funcion) from cine.funcion where id_sala = %s and estado = 'programada'",
               (salas["Sala IMAX 2"]["id_sala"],))[0][0]


# Pruebas -----------------------------------------------------------------------------------

def test_cartelera_filtrada_por_ciudad_y_genero(page):
    page.goto(URL)
    page.select_option("select[name=ciudad]", label="San José (Costa Rica)")
    page.select_option("select[name=genero]", label="Ciencia ficción")
    page.click("text=Filtrar")
    peliculas = page.locator("article.pelicula")
    assert peliculas.count() > 0
    for i in range(peliculas.count()):
        expect(peliculas.nth(i).locator(".detalle")).to_contain_text("Ciencia ficción")
        sedes = peliculas.nth(i).locator("table.funciones td:nth-child(2)")
        for j in range(sedes.count()):
            expect(sedes.nth(j)).to_contain_text("(San José)")


def test_pago_rechazado_libera_los_asientos(page, funcion_futura):
    entrar(page, "cliente@imax.demo")
    id_orden, elegidos = bloquear(page, funcion_futura, 2)
    expect(page.locator("#temporizador")).to_have_text(re.compile(r"^0[01]:\d\d$"))
    pagar(page, "4000 0000 0000 0002")
    page.wait_for_url(re.compile(rf"/funcion/{funcion_futura}$"))
    expect(page.locator(".aviso.error:not([hidden])")).to_contain_text("rechazado")
    for id_asiento in elegidos:
        expect(page.locator(f".asiento[data-id='{id_asiento}']")).to_have_class(re.compile("disponible"))
    assert sql("select estado from cine.orden where id_orden = %s", (id_orden,))[0][0] == "rechazada"
    assert sql("select count(*) from cine.boleto where id_orden = %s", (id_orden,))[0][0] == 0


def test_pago_aprobado_muestra_un_qr_por_asiento_y_no_envia_la_tarjeta(page, funcion_futura):
    enviados = []
    page.on("request", lambda r: enviados.append(r.post_data or "") if r.method == "POST" else None)
    entrar(page, "cliente@imax.demo")
    bloquear(page, funcion_futura, 2)
    pagar(page, "4242 4242 4242 4242")
    page.wait_for_url(re.compile(r"/confirmacion$"))
    expect(page.locator(".boleto svg")).to_have_count(2)
    pago = [d for d in enviados if "ultimos4" in d]
    assert pago and "ultimos4=4242" in pago[0]
    assert all("4242424242424242" not in d and "4242+4242" not in d for d in enviados)  # RN-09


def test_dos_navegadores_ven_el_bloqueo(browser, funcion_futura):
    a, b = browser.new_context(), browser.new_context()
    pa, pb = a.new_page(), b.new_page()
    entrar(pa, "cliente@imax.demo")
    entrar(pb, "cliente2@imax.demo")
    pb.goto(f"{URL}/funcion/{funcion_futura}")
    pb.wait_for_selector(".asiento.disponible")
    inicio = time.monotonic()
    _, elegidos = bloquear(pa, funcion_futura)
    expect(pb.locator(f".asiento[data-id='{elegidos[0]}']")).to_have_class(re.compile("bloqueado"), timeout=5000)
    assert time.monotonic() - inicio < 5
    a.close()
    b.close()


def test_puerta_un_solo_ingreso_y_rechazos(browser, salas, funcion_en_ventana, funcion_futura):
    cliente = browser.new_context().new_page()
    entrar(cliente, "cliente@imax.demo")
    qr_ventana = comprar(cliente, funcion_en_ventana)
    qr_futura = comprar(cliente, funcion_futura)

    operador = browser.new_context().new_page()
    entrar(operador, "puerta@imax.demo")
    sala_2, sala_1 = salas["Sala IMAX 2"]["id_puerta"], salas["Sala IMAX 1"]["id_puerta"]
    expect(escanear(operador, sala_2, qr_ventana)).to_contain_text("Acceso permitido")
    expect(escanear(operador, sala_2, qr_ventana)).to_have_text("Entrada ya utilizada")
    expect(escanear(operador, sala_2, qr_futura)).to_have_text("La entrada es de otra función o sala")
    expect(escanear(operador, sala_1, qr_futura)).to_have_text("Fuera del horario de ingreso")
    resultados = sql("""
        select l.resultado from bitacora.acceso_puerta_log l join cine.boleto b on b.id_boleto = l.id_boleto
        where b.codigo_qr = %s order by l.id""", (qr_ventana,))
    assert [r[0] for r in resultados] == ["exitoso", "duplicado"]


@pytest.mark.parametrize("email", ["taquilla@imax.demo", "cliente@imax.demo"])
def test_taquillero_y_cliente_no_entran_a_la_configuracion(page, email):
    entrar(page, email)
    for ruta in ["/admin/precios", "/admin/salas", "/admin/funciones"]:
        respuesta = page.goto(f"{URL}{ruta}")
        assert respuesta.status == 403
    expect(page.locator("header nav")).not_to_contain_text("Precios")


def test_administracion_queda_en_la_auditoria(browser, page, salas, funcion_futura):
    entrar(page, "admin@imax.demo")

    # Alta de película con metadatos
    titulo = f"Prueba GUI {int(time.time())}"
    page.goto(f"{URL}/admin/peliculas")
    page.fill("input[name=titulo]", titulo)
    page.fill("textarea[name=sinopsis]", "Película creada por la prueba de la interfaz.")
    page.fill("input[name=duracion_min]", "100")
    page.fill("input[name=fecha_estreno]", datetime.date.today().isoformat())
    page.fill("input[name=poster_url]", "https://ejemplo.org/poster.jpg")
    page.check("fieldset input[type=checkbox] >> nth=0")
    page.click("text=Agregar a la cartelera")
    expect(page.locator(".aviso.ok")).to_contain_text(titulo)

    # Función sin traslape y luego una que se traslapa
    sala_2 = salas["Sala IMAX 2"]["id_sala"]
    expect(programar_funcion(page, sala_2, 300)).to_contain_text("Función programada")
    expect(programar_funcion(page, sala_2, 330)).to_contain_text("se traslapa")

    # RN-18: la Sala IMAX 1 tiene ventas y no se puede desactivar
    page.goto(f"{URL}/admin/salas")
    page.locator("tr", has_text="IMAX San José").filter(has_text="Sala IMAX 1").locator("button", has_text="Desactivar").click()
    expect(page.locator(".aviso.error")).to_contain_text("RN-18")

    # Cambio de precio
    page.goto(f"{URL}/admin/precios")
    campo = page.locator("td input[type=number]").first
    anterior = campo.input_value()
    campo.fill(f"{float(anterior) + 1:.2f}")
    page.click("text=Guardar precios")
    expect(page.locator(".aviso.ok")).to_contain_text("Precios actualizados: 1")

    # Reembolso forzado de un boleto vendido
    cliente = browser.new_context().new_page()
    entrar(cliente, "cliente@imax.demo")
    qr = comprar(cliente, funcion_futura)
    page.goto(f"{URL}/admin/boletos?qr={qr}")
    page.select_option("select[name=tipo]", "forzado")
    page.fill("form:has-text('Anular') input[name=motivo]", "Prueba de reembolso forzado")
    page.click("text=Anular boleto")
    expect(page.locator(".aviso.ok")).to_contain_text("Boleto anulado")
    expect(page.locator("#estado-boleto")).to_contain_text("anulado")

    # La auditoría muestra las operaciones con fecha, responsable, rol e IP
    page.goto(f"{URL}/admin/auditoria")
    tabla = page.locator("#auditoria")
    for operacion in ["alta_pelicula", "alta_funcion", "cambio_tarifa", "reembolso_forzado"]:
        fila = tabla.locator("tr", has_text=operacion).first
        expect(fila).to_contain_text("Administrador")
        expect(fila).to_contain_text("127.0.0.1")

    # Se deja el precio como estaba
    page.goto(f"{URL}/admin/precios")
    page.locator("td input[type=number]").first.fill(anterior)
    page.click("text=Guardar precios")


def test_reportes_muestran_las_cuatro_analiticas(page):
    entrar(page, "admin@imax.demo")
    page.goto(f"{URL}/reportes")
    for tabla in ["#ocupacion", "#top5", "#metodos", "#auditoria-mes"]:
        assert page.locator(f"{tabla} tr").count() > 1, tabla
    expect(page.locator(".aviso.error")).to_have_count(0)
