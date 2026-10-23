"""Reportes: las 4 consultas analíticas de db/analiticas (contador y administrador)."""

import psycopg
from fastapi import APIRouter, Depends, Request

from app import analiticas, db, web
from app.seguridad import ip_cliente, requiere_rol

router = APIRouter()
lectores = requiere_rol("contador", "administrador")

# Igual que en 01_ocupacion_recaudacion.sql: sin función elegida se usa la ya realizada con más boletos
FUNCION_POR_DEFECTO = """
    select b.id_funcion from cine.boleto b join cine.funcion f on f.id_funcion = b.id_funcion
    where f.inicio < now() and b.estado = 'vigente'
    group by b.id_funcion order by count(*) desc, b.id_funcion limit 1"""


@router.get("/reportes")
def reportes(request: Request, id_funcion: int | None = None, usuario=Depends(lectores)):
    resultados = {}
    try:
        with db.transaccion(usuario["rol"], usuario["id"], ip_cliente(request)) as con:
            if id_funcion is None:
                fila = con.execute(FUNCION_POR_DEFECTO).fetchone()
                id_funcion = fila["id_funcion"] if fila else 0
            resultados["ocupacion"] = analiticas.ejecutar(con, "ocupacion", id_funcion=id_funcion)
            resultados["top5"] = analiticas.ejecutar(con, "top5")
            resultados["metodos"] = analiticas.ejecutar(con, "metodos")
            # La auditoría de administradores solo la ve el administrador (RN-17)
            if usuario["rol"] == "administrador":
                resultados["auditoria"] = analiticas.ejecutar(con, "auditoria")
    except psycopg.Error as e:
        web.avisar(request, db.mensaje_error(e), "error")
    return web.mostrar(request, "reportes.html", id_funcion=id_funcion, **resultados)
