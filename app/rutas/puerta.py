"""Simulador del tótem de puerta: validación de entradas (RN-14, RN-15, RN-16, RN-06)."""

import psycopg
from fastapi import APIRouter, Depends, Form, Request

from app import db, web
from app.seguridad import ip_cliente, requiere_rol

router = APIRouter()
operadores = requiere_rol("operador_puerta", "administrador")


def puertas_disponibles(con, usuario):
    """El operador ve las puertas de su sede; el administrador, todas las de las sedes de demostración."""
    return con.execute("""
        select pu.id_puerta, pu.codigo, s.nombre as sala, se.nombre as sede,
               (select p.titulo || ' · ' || to_char(f.inicio at time zone 'America/Costa_Rica', 'DD/MM HH24:MI')
                  from cine.funcion f join cine.pelicula p on p.id_pelicula = f.id_pelicula
                 where f.id_sala = s.id_sala and f.estado = 'programada' and f.fin > now()
                 order by f.inicio limit 1) as proxima_funcion
        from cine.puerta pu
        join cine.sala s on s.id_sala = pu.id_sala
        join cine.sede se on se.id_sede = s.id_sede
        where pu.es_activa and (se.id_sede = %(sede)s or (%(sede)s is null and se.nombre not like 'IMAX Sede %%'))
        order by se.nombre, s.nombre""", {"sede": usuario["id_sede"]}).fetchall()


@router.get("/puerta")
def pagina_puerta(request: Request, id_puerta: int | None = None, usuario=Depends(operadores)):
    with db.transaccion(usuario["rol"], usuario["id"], ip_cliente(request)) as con:
        puertas = puertas_disponibles(con, usuario)
    return web.mostrar(request, "puerta.html", puertas=puertas, id_puerta=id_puerta, resultado=None)


@router.post("/puerta/validar")
def validar(request: Request, id_puerta: int = Form(...), codigo_qr: str = Form(...), usuario=Depends(operadores)):
    resultado = None
    try:
        with db.transaccion(usuario["rol"], usuario["id"], ip_cliente(request)) as con:
            resultado = con.execute("select * from cine.validar_entrada(%s, %s, %s)",
                                    (codigo_qr.strip(), id_puerta, usuario["id"])).fetchone()
            puertas = puertas_disponibles(con, usuario)
    except psycopg.Error as e:
        web.avisar(request, db.mensaje_error(e), "error")
        return web.ir_a(f"/puerta?id_puerta={id_puerta}")
    return web.mostrar(request, "puerta.html", puertas=puertas, id_puerta=id_puerta, resultado=resultado,
                       codigo_qr=codigo_qr.strip())


@router.post("/puerta/incidencia")
def incidencia(request: Request, id_puerta: int = Form(...), codigo_qr: str = Form(...), detalle: str = Form(...),
               usuario=Depends(operadores)):
    """RN-06: el cliente no presentó el documento de su tarifa especial u otra incidencia."""
    with db.transaccion(usuario["rol"], usuario["id"], ip_cliente(request)) as con:
        con.execute("select cine.registrar_incidencia(%s, %s, %s, %s)", (codigo_qr, id_puerta, usuario["id"], detalle))
    web.avisar(request, "Incidencia registrada en la bitácora de puerta.", "aviso")
    return web.ir_a(f"/puerta?id_puerta={id_puerta}")
