"""Prueba de concurrencia: muchas solicitudes simultáneas por el mismo asiento.

En cada corrida se abren N conexiones con el rol de cliente. Todas esperan en una barrera y
llaman al mismo tiempo a cine.bloquear_asientos() por el mismo asiento de la misma función.
La base de datos debe dejar pasar exactamente una: la PK (id_funcion, id_asiento) de
ocupacion_asiento rechaza a las demás, que reciben nulo y quedan registradas como colisión.

Uso:
    py scripts/concurrencia.py
    py scripts/concurrencia.py --corridas 25 --salida docs/evidencias/concurrencia.txt

Requiere la base inicializada con db/init.sql y los datos de db/seed/01_datos_demo.sql.
"""

import argparse
import datetime
import pathlib
import sys
import threading
import time

import psycopg

RAIZ = pathlib.Path(__file__).resolve().parents[1]


def leer_env():
    valores = {}
    for linea in (RAIZ / ".env").read_text(encoding="utf-8").splitlines():
        linea = linea.strip()
        if linea and not linea.startswith("#") and "=" in linea:
            clave, valor = linea.split("=", 1)
            valores[clave.strip()] = valor.strip()
    return valores


ENV = leer_env()
CONEXION = {
    "host": "localhost",
    "port": ENV.get("POSTGRES_PORT", "5433"),
    "dbname": ENV["POSTGRES_DB"],
    "user": ENV["POSTGRES_USER"],
    "password": ENV["POSTGRES_PASSWORD"],
}


def preparar(con, asientos_necesarios, clientes_necesarios):
    """Elige una función futura de la demostración, asientos libres y clientes."""
    id_funcion = con.execute("""
        select c.id_funcion
        from cine.v_cartelera_activa c
        where c.sede = 'IMAX San José' and c.inicio > now() + interval '1 hour'
        order by c.inicio
        limit 1""").fetchone()[0]
    asientos = [f[0] for f in con.execute("""
        select id_asiento from cine.v_mapa_asientos
        where id_funcion = %s and estado = 'disponible'
        order by id_asiento limit %s""", (id_funcion, asientos_necesarios))]
    clientes = [f[0] for f in con.execute("""
        select u.id_usuario from cine.usuario u join cine.rol r on r.id_rol = u.id_rol
        where r.codigo = 'cliente' order by u.id_usuario limit %s""", (clientes_necesarios,))]
    if len(asientos) < asientos_necesarios or len(clientes) < clientes_necesarios:
        sys.exit("No hay suficientes asientos libres o clientes para la prueba")
    return id_funcion, asientos, clientes


def corrida(id_funcion, id_asiento, clientes):
    """Lanza una solicitud por cliente, todas a la vez, por el mismo asiento."""
    n = len(clientes)
    conexiones = []
    for _ in range(n):
        c = psycopg.connect(**CONEXION)
        c.execute("set role rol_cliente")  # cada hilo actúa como un cliente
        c.commit()
        conexiones.append(c)

    barrera = threading.Barrier(n)
    ordenes = [None] * n
    errores = [None] * n

    def solicitar(i):
        con = conexiones[i]
        try:
            barrera.wait()
            fila = con.execute("select cine.bloquear_asientos(%s, %s, %s)",
                               (id_funcion, clientes[i], [id_asiento])).fetchone()
            con.commit()
            ordenes[i] = fila[0]
        except Exception as e:  # cualquier error cuenta como fallo de la prueba
            con.rollback()
            errores[i] = str(e)

    hilos = [threading.Thread(target=solicitar, args=(i,)) for i in range(n)]
    inicio = time.perf_counter()
    for h in hilos:
        h.start()
    for h in hilos:
        h.join()
    duracion = time.perf_counter() - inicio
    for c in conexiones:
        c.close()

    ganadores = [o for o in ordenes if o is not None]
    return ganadores, [e for e in errores if e], duracion


def verificar(con, id_funcion, id_asiento, desde):
    """Lo que quedó en la base: filas del asiento, órdenes pendientes y colisiones registradas."""
    return con.execute("""
        select (select count(*) from cine.ocupacion_asiento where id_funcion = %(f)s and id_asiento = %(a)s),
               (select count(*) from cine.orden_detalle d join cine.orden o on o.id_orden = d.id_orden
                 where o.id_funcion = %(f)s and d.id_asiento = %(a)s and o.estado = 'pendiente'),
               (select count(*) from bitacora.asiento_auditoria_log
                 where id_funcion = %(f)s and id_asiento = %(a)s and evento = 'colision' and ocurrido_en >= %(d)s)
        """, {"f": id_funcion, "a": id_asiento, "d": desde}).fetchone()


def main():
    p = argparse.ArgumentParser(description="Prueba de concurrencia de doble venta")
    p.add_argument("--corridas", type=int, default=25, help="corridas por cada cantidad de hilos")
    p.add_argument("--hilos", type=int, nargs="+", default=[20, 50])
    p.add_argument("--salida", type=pathlib.Path, help="archivo donde guardar el resultado")
    args = p.parse_args()

    lineas = []

    def mostrar(texto=""):
        print(texto)
        lineas.append(texto)

    admin = psycopg.connect(**CONEXION, autocommit=True)
    total = args.corridas * len(args.hilos)
    id_funcion, asientos, clientes = preparar(admin, total, max(args.hilos))
    pg = admin.execute("select version()").fetchone()[0].split(",")[0]

    mostrar("Prueba de concurrencia de doble venta")
    mostrar(f"Fecha: {datetime.datetime.now().astimezone():%Y-%m-%d %H:%M:%S %z}")
    mostrar(f"Base: {pg}")
    mostrar("Comando: py scripts/concurrencia.py " + " ".join(sys.argv[1:]))
    mostrar(f"Función: {id_funcion}. Cada corrida usa un asiento distinto y todos los hilos piden ese mismo asiento.")
    mostrar()
    mostrar(f"{'Corrida':>7} {'Hilos':>5} {'Asiento':>8} {'Ganadores':>9} {'Rechazos':>8} {'Errores':>7} "
            f"{'Filas asiento':>13} {'Órdenes':>7} {'Colisiones':>10} {'Duración (s)':>12}  Resultado")

    resumen = {n: {"ok": 0, "corridas": 0} for n in args.hilos}
    ganadoras = []
    numero = 0
    falla = False
    for n in args.hilos:
        for _ in range(args.corridas):
            id_asiento = asientos[numero]
            numero += 1
            desde = admin.execute("select clock_timestamp()").fetchone()[0]
            ganadores, errores, duracion = corrida(id_funcion, id_asiento, clientes[:n])
            filas, ordenes, colisiones = verificar(admin, id_funcion, id_asiento, desde)
            ok = len(ganadores) == 1 and not errores and filas == 1 and ordenes == 1 and colisiones == n - 1
            resumen[n]["corridas"] += 1
            resumen[n]["ok"] += ok
            ganadoras += ganadores
            mostrar(f"{numero:>7} {n:>5} {id_asiento:>8} {len(ganadores):>9} {n - len(ganadores) - len(errores):>8} "
                    f"{len(errores):>7} {filas:>13} {ordenes:>7} {colisiones:>10} {duracion:>12.3f}  "
                    f"{'OK' if ok else 'FALLO'}")
            if errores:
                mostrar(f"        Error: {errores[0]}")
            if len(ganadores) > 1 or filas > 1:
                falla = True
                break
        if falla:
            break

    mostrar()
    mostrar("Resumen:")
    for n, r in resumen.items():
        mostrar(f"  {n} hilos: {r['ok']} de {r['corridas']} corridas con exactamente 1 ganador y 0 duplicados")

    # Se liberan los bloqueos de la prueba para dejar los asientos disponibles otra vez
    for id_orden in ganadoras:
        admin.execute("select cine.liberar_asientos(%s)", (id_orden,))
    mostrar(f"Bloqueos de prueba liberados: {len(ganadoras)}")

    exito = all(r["ok"] == r["corridas"] == args.corridas for r in resumen.values())
    mostrar("RESULTADO: " + ("todas las corridas correctas" if exito
                             else "FALLO: hubo corridas con más o menos de un ganador"))
    admin.close()

    if args.salida:
        args.salida.write_text("\n".join(lineas) + "\n", encoding="utf-8", newline="\n")
    sys.exit(0 if exito else 1)


if __name__ == "__main__":
    main()
