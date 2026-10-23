"""Lee las consultas analíticas de db/analiticas para mostrarlas en el panel y en los reportes.

Así la aplicación ejecuta exactamente las mismas consultas que se entregan como scripts SQL.
Se quitan los comandos de psql (líneas que empiezan con "\\") y el parámetro :id_funcion se
convierte en un parámetro de psycopg.
"""

from app import config

CARPETA = config.RAIZ / "db" / "analiticas"
ARCHIVOS = {
    "ocupacion": "01_ocupacion_recaudacion.sql",
    "top5": "02_top5_semana.sql",
    "metodos": "03_metodos_pago.sql",
    "auditoria": "04_auditoria_mes.sql",
}


def consulta(nombre: str) -> str:
    lineas, dentro_de_if = [], False
    for linea in (CARPETA / ARCHIVOS[nombre]).read_text(encoding="utf-8").splitlines():
        texto = linea.strip()
        if texto.startswith("\\if"):
            dentro_de_if = True
        if not dentro_de_if and not texto.startswith("\\"):
            lineas.append(linea)
        if texto.startswith("\\endif"):
            dentro_de_if = False
    sql = "\n".join(lineas).replace("%", "%%").replace(":id_funcion", "%(id_funcion)s")
    return sql.rstrip().rstrip(";")


def ejecutar(con, nombre: str, **parametros):
    return con.execute(consulta(nombre), parametros).fetchall()
