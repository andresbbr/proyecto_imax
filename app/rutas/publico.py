"""Inicio de sesión y cartelera."""

import datetime

from fastapi import APIRouter, Form, Request

from app import db, web
from app.seguridad import usuario_actual, verificar_contrasena

router = APIRouter()

INICIO_POR_ROL = {
    "cliente": "/",
    "taquillero": "/taquilla",
    "operador_puerta": "/puerta",
    "contador": "/reportes",
    "administrador": "/admin",
}


@router.get("/login")
def formulario_login(request: Request, siguiente: str = ""):
    return web.mostrar(request, "login.html", siguiente=siguiente)


@router.post("/login")
def iniciar_sesion(request: Request, email: str = Form(...), contrasena: str = Form(...), siguiente: str = Form("")):
    with db.sin_rol() as con:
        fila = con.execute("select * from cine.datos_login(%s)", (email.strip(),)).fetchone()
    if fila is None or not verificar_contrasena(contrasena, fila["contrasena_hash"]):
        web.avisar(request, "Correo o contraseña incorrectos.", "error")
        return web.ir_a("/login")
    request.session["usuario"] = {
        "id": fila["id_usuario"], "rol": fila["rol"], "nombre": fila["nombre"], "id_sede": fila["id_sede"],
    }
    destino = siguiente if siguiente.startswith("/") else INICIO_POR_ROL[fila["rol"]]
    return web.ir_a(destino)


@router.get("/logout")
def cerrar_sesion(request: Request):
    request.session.clear()
    return web.ir_a("/")


@router.get("/")
def cartelera(request: Request, ciudad: str = "", fecha: str = "", genero: str = ""):
    """RN-01 y RN-02: funciones activas con inicio futuro, filtradas por ubicación, fecha y género."""
    usuario = usuario_actual(request)
    condiciones, parametros = [], {}
    if ciudad:
        condiciones.append("c.id_ciudad = %(ciudad)s")
        parametros["ciudad"] = int(ciudad)
    if fecha:
        condiciones.append("(c.inicio at time zone 'America/Costa_Rica')::date = %(fecha)s")
        parametros["fecha"] = datetime.date.fromisoformat(fecha)
    if genero:
        condiciones.append("exists (select 1 from cine.pelicula_genero pg where pg.id_pelicula = c.id_pelicula"
                           " and pg.id_genero = %(genero)s)")
        parametros["genero"] = int(genero)
    where = ("where " + " and ".join(condiciones)) if condiciones else ""

    with db.transaccion(usuario["rol"] if usuario else "cliente") as con:
        funciones = con.execute(f"""
            select c.* from cine.v_cartelera_activa c {where}
            order by c.titulo, c.inicio
            limit 400""", parametros).fetchall()
        ciudades = con.execute("""
            select ci.id_ciudad, ci.nombre || ' (' || pa.nombre || ')' as nombre
            from cine.ciudad ci join cine.pais pa on pa.id_pais = ci.id_pais
            order by pa.nombre, ci.nombre""").fetchall()
        generos = con.execute("select id_genero, nombre from cine.genero order by nombre").fetchall()

    # Se agrupan las funciones por película para mostrarlas juntas
    peliculas = {}
    for f in funciones:
        p = peliculas.setdefault(f["id_pelicula"], {**f, "funciones": []})
        p["funciones"].append(f)
    return web.mostrar(request, "cartelera.html", peliculas=list(peliculas.values()), ciudades=ciudades,
                       generos=generos, filtro={"ciudad": ciudad, "fecha": fecha, "genero": genero})
