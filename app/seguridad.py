"""Contraseñas, sesión y control de acceso por rol (RN-17)."""

import base64
import hashlib
import hmac

from fastapi import HTTPException, Request


def verificar_contrasena(contrasena: str, almacenado: str) -> bool:
    """Compara con un hash pbkdf2_sha256$iteraciones$sal$hash_base64."""
    try:
        algoritmo, iteraciones, sal, esperado = almacenado.split("$")
    except ValueError:
        return False
    if algoritmo != "pbkdf2_sha256":
        return False
    calculado = hashlib.pbkdf2_hmac("sha256", contrasena.encode(), sal.encode(), int(iteraciones))
    return hmac.compare_digest(base64.b64encode(calculado).decode(), esperado)


def usuario_actual(request: Request):
    return request.session.get("usuario")


def ip_cliente(request: Request) -> str:
    return request.client.host if request.client else "127.0.0.1"


class NoAutenticado(Exception):
    """El usuario debe iniciar sesión."""


def requiere_rol(*roles):
    """Dependencia de FastAPI: exige sesión iniciada con alguno de los roles indicados."""
    def dependencia(request: Request):
        usuario = usuario_actual(request)
        if usuario is None:
            raise NoAutenticado()
        if roles and usuario["rol"] not in roles:
            raise HTTPException(status_code=403, detail="Su rol no tiene acceso a esta sección")
        return usuario
    return dependencia
