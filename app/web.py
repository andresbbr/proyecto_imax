"""Plantillas Jinja y utilidades comunes de las pantallas."""

import datetime
import pathlib

from fastapi import Request
from fastapi.responses import RedirectResponse
from fastapi.templating import Jinja2Templates

CARPETA = pathlib.Path(__file__).parent
templates = Jinja2Templates(directory=CARPETA / "templates")

# Las horas se muestran en la hora de Costa Rica (UTC-6, sin horario de verano)
HORA_LOCAL = datetime.timezone(datetime.timedelta(hours=-6))


def formato_hora(valor, formato="%d/%m/%Y %H:%M"):
    if valor is None:
        return ""
    if isinstance(valor, str):
        valor = datetime.datetime.fromisoformat(valor)
    return valor.astimezone(HORA_LOCAL).strftime(formato)


def formato_dinero(valor):
    return "" if valor is None else f"{float(valor):,.2f}"


templates.env.filters["hora"] = formato_hora
templates.env.filters["dinero"] = formato_dinero


def avisar(request: Request, texto: str, tipo: str = "ok"):
    """Guarda un mensaje para mostrarlo en la siguiente pantalla."""
    request.session.setdefault("avisos", []).append({"texto": texto, "tipo": tipo})


def mostrar(request: Request, plantilla: str, status_code: int = 200, **contexto):
    avisos = request.session.pop("avisos", [])
    return templates.TemplateResponse(
        request, plantilla, {"usuario": request.session.get("usuario"), "avisos": avisos, **contexto},
        status_code=status_code)


def ir_a(url: str):
    return RedirectResponse(url, status_code=303)
