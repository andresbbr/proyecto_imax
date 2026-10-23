"""Acceso a la base de datos.

Cada petición abre una transacción y cambia al rol de base de datos del usuario con
"set local role". Así los permisos los aplica PostgreSQL: si la aplicación se equivocara,
la base rechazaría la operación igual. En las operaciones de empleados también se registra
quién las hace y desde qué IP, para la bitácora de auditoría.
"""

from contextlib import contextmanager

import psycopg
from psycopg.rows import dict_row
from psycopg_pool import ConnectionPool

from app import config

ROLES_BD = {
    "cliente": "rol_cliente",
    "taquillero": "rol_taquillero",
    "operador_puerta": "rol_operador_puerta",
    "contador": "rol_contador",
    "administrador": "rol_administrador",
}

pool = ConnectionPool(config.CONEXION, min_size=1, max_size=10, open=False, kwargs={"row_factory": dict_row})


@contextmanager
def transaccion(rol="cliente", id_usuario=None, ip=None):
    """Transacción con el rol de la sesión. Hace commit al salir o rollback si hay un error."""
    with pool.connection() as con:
        with con.transaction():
            con.execute(f"set local role {ROLES_BD[rol]}")
            if id_usuario is not None and rol != "cliente":
                con.execute("select cine.establecer_contexto(%s, %s)", (id_usuario, ip or "127.0.0.1"))
            yield con


@contextmanager
def sin_rol():
    """Conexión como imax_app sin cambiar de rol: solo sirve para el inicio de sesión."""
    with pool.connection() as con:
        with con.transaction():
            yield con


def mensaje_error(error: psycopg.Error) -> str:
    """Mensaje legible de un error de la base de datos (por ejemplo, un raise exception)."""
    if error.diag and error.diag.message_primary:
        return error.diag.message_primary
    return str(error)
