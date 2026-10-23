"""Configuración leída del archivo .env de la raíz del proyecto."""

import pathlib

from psycopg.conninfo import make_conninfo

RAIZ = pathlib.Path(__file__).resolve().parents[1]


def _leer_env():
    valores = {}
    ruta = RAIZ / ".env"
    if ruta.exists():
        for linea in ruta.read_text(encoding="utf-8").splitlines():
            linea = linea.strip()
            if linea and not linea.startswith("#") and "=" in linea:
                clave, valor = linea.split("=", 1)
                valores[clave.strip()] = valor.strip()
    return valores


ENV = _leer_env()

# La aplicación se conecta siempre como imax_app y cambia al rol del usuario en cada petición
CONEXION = make_conninfo(
    host=ENV.get("POSTGRES_HOST", "localhost"),
    port=ENV.get("POSTGRES_PORT", "5432"),
    dbname=ENV.get("POSTGRES_DB", "imax"),
    user="imax_app",
    password=ENV.get("APP_DB_PASSWORD", ""),
)
SECRETO = ENV.get("APP_SECRET", "cambiar_esta_clave_secreta")
