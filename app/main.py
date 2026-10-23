"""Aplicación web de la plataforma IMAX.

Se inicia desde la raíz del proyecto, con la base de datos ya creada y cargada:
    py -m uvicorn app.main:app
y se abre en http://127.0.0.1:8000
"""

import asyncio
import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException, Request
from fastapi.staticfiles import StaticFiles
from starlette.middleware.sessions import SessionMiddleware

from app import config, db, web
from app.rutas import admin, compra, publico, puerta, reportes
from app.seguridad import NoAutenticado

log = logging.getLogger("imax")


def barrer_bloqueos():
    with db.transaccion("administrador") as con:
        return con.execute("select cine.liberar_bloqueos_expirados() as n").fetchone()["n"]


async def barrido_periodico():
    """Libera cada minuto los bloqueos de asientos vencidos (RN-05)."""
    while True:
        try:
            liberados = await asyncio.to_thread(barrer_bloqueos)
            if liberados:
                log.info("Bloqueos vencidos liberados: %s", liberados)
        except Exception:
            log.exception("Error en el barrido de bloqueos")
        await asyncio.sleep(60)


@asynccontextmanager
async def ciclo_de_vida(app: FastAPI):
    db.pool.open(wait=True)
    tarea = asyncio.create_task(barrido_periodico())
    yield
    tarea.cancel()
    db.pool.close()


app = FastAPI(title="IMAX", lifespan=ciclo_de_vida)
app.add_middleware(SessionMiddleware, secret_key=config.SECRETO, same_site="lax")
app.mount("/static", StaticFiles(directory=web.CARPETA / "static"), name="static")

for modulo in (publico, compra, puerta, admin, reportes):
    app.include_router(modulo.router)


@app.exception_handler(NoAutenticado)
async def pedir_inicio_de_sesion(request: Request, exc: NoAutenticado):
    web.avisar(request, "Inicie sesión para continuar.", "aviso")
    return web.ir_a(f"/login?siguiente={request.url.path}")


@app.exception_handler(HTTPException)
async def pagina_de_error(request: Request, exc: HTTPException):
    if request.url.path.startswith("/api/"):
        from fastapi.responses import JSONResponse
        return JSONResponse({"error": exc.detail}, status_code=exc.status_code)
    return web.mostrar(request, "error.html", status_code=exc.status_code, codigo=exc.status_code, detalle=exc.detail)
