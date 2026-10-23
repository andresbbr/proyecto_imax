"""Compra en línea y venta en taquilla: mapa de asientos, bloqueo, orden, pago y boletos."""

import datetime

import psycopg
import qrcode
import qrcode.image.svg
from fastapi import APIRouter, Depends, Form, HTTPException, Request
from fastapi.responses import JSONResponse
from pydantic import BaseModel

from app import db, web
from app.seguridad import ip_cliente, requiere_rol

router = APIRouter()
vendedores = requiere_rol("cliente", "taquillero")


def qr_svg(texto: str) -> str:
    """Código QR como SVG en línea."""
    imagen = qrcode.make(texto, image_factory=qrcode.image.svg.SvgPathImage, box_size=10, border=2)
    return imagen.to_string(encoding="unicode")


def tx(usuario, request: Request):
    return db.transaccion(usuario["rol"], usuario["id"], ip_cliente(request))


@router.get("/funcion/{id_funcion}")
def pagina_funcion(id_funcion: int, request: Request, usuario=Depends(vendedores)):
    with tx(usuario, request) as con:
        funcion = con.execute("select * from cine.v_cartelera_activa where id_funcion = %s", (id_funcion,)).fetchone()
        maximo = con.execute("select cine.parametro('max_asientos_por_orden') as m").fetchone()["m"]
    if funcion is None:
        raise HTTPException(404, "La función no existe o ya no está a la venta")
    return web.mostrar(request, "funcion.html", funcion=funcion, maximo=int(maximo))


@router.get("/api/funciones/{id_funcion}/asientos")
def estado_asientos(id_funcion: int, request: Request, usuario=Depends(vendedores)):
    """RN-03: estado actual de cada asiento. La pantalla lo consulta cada 2 segundos."""
    with tx(usuario, request) as con:
        filas = con.execute("""
            select id_asiento, fila, numero, zona, tipo_zona, estado, id_orden_bloqueo
            from cine.v_mapa_asientos where id_funcion = %s
            order by fila, numero""", (id_funcion,)).fetchall()
    return filas


class Seleccion(BaseModel):
    asientos: list[int]


@router.post("/api/funciones/{id_funcion}/bloquear")
def bloquear(id_funcion: int, seleccion: Seleccion, request: Request, usuario=Depends(vendedores)):
    """RN-04 y RN-05: bloquea los asientos por 2 minutos y crea la orden."""
    canal = "taquilla" if usuario["rol"] == "taquillero" else "en_linea"
    try:
        with tx(usuario, request) as con:
            id_orden = con.execute("select cine.bloquear_asientos(%s, %s, %s, %s) as id",
                                   (id_funcion, usuario["id"], seleccion.asientos, canal)).fetchone()["id"]
    except psycopg.Error as e:
        return JSONResponse({"error": db.mensaje_error(e)}, status_code=400)
    if id_orden is None:
        return JSONResponse({"error": "Alguno de los asientos acaba de ser tomado por otra persona. Elija otros."},
                            status_code=409)
    return {"id_orden": id_orden}


def leer_orden(con, id_orden, usuario):
    return con.execute("select cine.resumen_orden(%s, %s) as r", (id_orden, usuario["id"])).fetchone()["r"]


@router.get("/orden/{id_orden}")
def pagina_orden(id_orden: int, request: Request, usuario=Depends(vendedores)):
    try:
        with tx(usuario, request) as con:
            orden = leer_orden(con, id_orden, usuario)
            tarifas = con.execute("select codigo, nombre from cine.tipo_tarifa where not es_cortesia order by id_tipo_tarifa").fetchall()
            metodos = con.execute("select codigo, nombre, es_tarjeta from cine.metodo_pago order by id_metodo_pago").fetchall()
    except psycopg.Error as e:
        raise HTTPException(404, db.mensaje_error(e))
    if orden["estado"] == "pagada":
        return web.ir_a(f"/orden/{id_orden}/confirmacion")
    return web.mostrar(request, "orden.html", orden=orden, tarifas=tarifas, metodos=metodos)


@router.post("/orden/{id_orden}/tarifa")
def cambiar_tarifa(id_orden: int, request: Request, id_asiento: int = Form(...), tipo: str = Form(...),
                   usuario=Depends(vendedores)):
    try:
        with tx(usuario, request) as con:
            leer_orden(con, id_orden, usuario)  # verifica que la orden sea del usuario
            con.execute("select cine.elegir_tarifa(%s, %s, %s)", (id_orden, id_asiento, tipo))
    except psycopg.Error as e:
        web.avisar(request, db.mensaje_error(e), "error")
    return web.ir_a(f"/orden/{id_orden}")


@router.post("/orden/{id_orden}/pagar")
def pagar(id_orden: int, request: Request, metodo: str = Form(...), ultimos4: str = Form(""), marca: str = Form(""),
          usuario=Depends(vendedores)):
    """Pago simulado. El navegador solo envía los últimos 4 dígitos y la marca (RN-09)."""
    try:
        with tx(usuario, request) as con:
            orden = leer_orden(con, id_orden, usuario)
            respuesta = con.execute("select cine.procesar_pago(%s, %s, %s, %s) as r",
                                    (id_orden, metodo, ultimos4 or None, marca or None)).fetchone()["r"]
    except psycopg.Error as e:
        web.avisar(request, db.mensaje_error(e), "error")
        return web.ir_a(f"/orden/{id_orden}")
    if respuesta == "aprobado":
        web.avisar(request, "Pago aprobado. Sus entradas ya están disponibles.")
        return web.ir_a(f"/orden/{id_orden}/confirmacion")
    # RN-10: el pago rechazado libera los asientos de inmediato
    web.avisar(request, f"Pago {respuesta}. Los asientos se liberaron.", "error")
    return web.ir_a(f"/funcion/{orden['id_funcion']}")


@router.post("/orden/{id_orden}/liberar")
def liberar(id_orden: int, request: Request, usuario=Depends(vendedores)):
    with tx(usuario, request) as con:
        orden = leer_orden(con, id_orden, usuario)
        con.execute("select cine.liberar_asientos(%s)", (id_orden,))
    web.avisar(request, "Se liberaron los asientos.", "aviso")
    return web.ir_a(f"/funcion/{orden['id_funcion']}")


@router.get("/orden/{id_orden}/confirmacion")
def confirmacion(id_orden: int, request: Request, usuario=Depends(vendedores)):
    """RN-11: los boletos y sus QR solo existen si el pago fue aprobado."""
    try:
        with tx(usuario, request) as con:
            orden = leer_orden(con, id_orden, usuario)
            boletos = con.execute("select * from cine.boletos_de_orden(%s, %s)", (id_orden, usuario["id"])).fetchall()
    except psycopg.Error as e:
        web.avisar(request, db.mensaje_error(e), "error")
        return web.ir_a(f"/orden/{id_orden}")
    for b in boletos:
        b["qr"] = qr_svg(b["codigo_qr"])
    return web.mostrar(request, "confirmacion.html", orden=orden, boletos=boletos)


@router.get("/mis-entradas")
def mis_entradas(request: Request, usuario=Depends(requiere_rol("cliente"))):
    """RN-13: entradas del cliente en su perfil."""
    with tx(usuario, request) as con:
        entradas = con.execute("""
            select * from cine.v_mis_entradas where id_usuario = %s
            order by inicio desc limit 50""", (usuario["id"],)).fetchall()
    for e in entradas:
        e["qr"] = qr_svg(e["codigo_qr"]) if e["estado"] == "vigente" else None
    return web.mostrar(request, "mis_entradas.html", entradas=entradas)


@router.get("/taquilla")
def taquilla(request: Request, usuario=Depends(requiere_rol("taquillero"))):
    """Venta presencial en la sede del taquillero y su corte de caja del día."""
    hoy = datetime.datetime.now(web.HORA_LOCAL).date()
    with tx(usuario, request) as con:
        funciones = con.execute("""
            select * from cine.v_cartelera_activa
            where id_sede = %s and inicio < now() + interval '3 days'
            order by inicio""", (usuario["id_sede"],)).fetchall()
        corte = con.execute("select * from cine.corte_de_caja(%s, %s)", (usuario["id"], hoy)).fetchone()
    return web.mostrar(request, "taquilla.html", funciones=funciones, corte=corte, hoy=hoy)
