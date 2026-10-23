"""Panel de administración: cartelera, salas, funciones, precios, boletos y auditoría.

Solo para el rol administrador (RN-17). Cada transacción registra el usuario y la IP, de modo
que los triggers de auditoría guardan quién hizo cada cambio (RN-20).
"""

import datetime

import psycopg
from fastapi import APIRouter, Depends, Form, Request

from app import analiticas, db, web
from app.seguridad import ip_cliente, requiere_rol

router = APIRouter(prefix="/admin")
administrador = requiere_rol("administrador")

# Las sedes sintéticas de la carga masiva no se muestran en las listas del panel
SOLO_DEMO = "se.nombre not like 'IMAX Sede %%'"


def tx(request: Request, usuario):
    return db.transaccion("administrador", usuario["id"], ip_cliente(request))


def ejecutar_cambio(request: Request, usuario, sql: str, parametros=(), exito: str = "Cambio guardado."):
    """Ejecuta un cambio y muestra el mensaje de la base de datos si lo rechaza."""
    try:
        with tx(request, usuario) as con:
            con.execute(sql, parametros)
        web.avisar(request, exito)
        return True
    except psycopg.Error as e:
        web.avisar(request, db.mensaje_error(e), "error")
        return False


@router.get("")
def inicio(request: Request, usuario=Depends(administrador)):
    hoy = datetime.datetime.now(web.HORA_LOCAL).date()
    with tx(request, usuario) as con:
        ventas = con.execute("""
            select count(*) as ordenes, coalesce(sum(total), 0) as total
            from cine.orden
            where estado = 'pagada' and (pagada_en at time zone 'America/Costa_Rica')::date = %s""", (hoy,)).fetchone()
        proximas = con.execute(f"""
            select f.id_funcion, p.titulo, se.nombre as sede, s.nombre as sala, f.inicio,
                   (select count(*) from cine.asiento a join cine.zona z on z.id_zona = a.id_zona
                     where z.id_sala = s.id_sala and a.es_habilitado) as capacidad,
                   (select count(*) from cine.ocupacion_asiento o where o.id_funcion = f.id_funcion
                     and (o.estado <> 'bloqueado' or o.expira_en > now())) as ocupados
            from cine.funcion f
            join cine.pelicula p on p.id_pelicula = f.id_pelicula
            join cine.sala s on s.id_sala = f.id_sala
            join cine.sede se on se.id_sede = s.id_sede
            where f.estado = 'programada' and f.inicio > now() and {SOLO_DEMO}
            order by f.inicio limit 12""").fetchall()
        top5 = analiticas.ejecutar(con, "top5")
        metodos = analiticas.ejecutar(con, "metodos")
    return web.mostrar(request, "admin_inicio.html", ventas=ventas, proximas=proximas, top5=top5, metodos=metodos, hoy=hoy)


# Películas -------------------------------------------------------------------------------

@router.get("/peliculas")
def peliculas(request: Request, usuario=Depends(administrador)):
    with tx(request, usuario) as con:
        lista = con.execute("""
            select p.*, c.codigo as clasificacion,
                   (select string_agg(g.nombre, ', ' order by g.nombre) from cine.pelicula_genero pg
                      join cine.genero g on g.id_genero = pg.id_genero where pg.id_pelicula = p.id_pelicula) as generos
            from cine.pelicula p join cine.clasificacion c on c.id_clasificacion = p.id_clasificacion
            order by p.fecha_estreno desc, p.titulo""").fetchall()
        clasificaciones = con.execute("select * from cine.clasificacion order by edad_minima").fetchall()
        generos = con.execute("select * from cine.genero order by nombre").fetchall()
    return web.mostrar(request, "admin_peliculas.html", peliculas=lista, clasificaciones=clasificaciones, generos=generos)


@router.post("/peliculas")
def alta_pelicula(request: Request, titulo: str = Form(...), sinopsis: str = Form(...), duracion_min: int = Form(...),
                  id_clasificacion: int = Form(...), poster_url: str = Form(...), fecha_estreno: str = Form(...),
                  generos: list[int] = Form(default=[]), usuario=Depends(administrador)):
    try:
        with tx(request, usuario) as con:
            id_pelicula = con.execute("""
                insert into cine.pelicula (id_clasificacion, titulo, sinopsis, duracion_min, poster_url, fecha_estreno)
                values (%s, %s, %s, %s, %s, %s) returning id_pelicula""",
                (id_clasificacion, titulo.strip(), sinopsis.strip(), duracion_min, poster_url.strip(), fecha_estreno)
            ).fetchone()["id_pelicula"]
            for id_genero in generos:
                con.execute("insert into cine.pelicula_genero (id_pelicula, id_genero) values (%s, %s)", (id_pelicula, id_genero))
        web.avisar(request, f"Película «{titulo}» agregada a la cartelera.")
    except psycopg.Error as e:
        web.avisar(request, db.mensaje_error(e), "error")
    return web.ir_a("/admin/peliculas")


# Salas ----------------------------------------------------------------------------------

@router.get("/salas")
def salas(request: Request, usuario=Depends(administrador)):
    with tx(request, usuario) as con:
        lista = con.execute(f"""
            select s.*, se.nombre as sede,
                   (select count(*) from cine.asiento a join cine.zona z on z.id_zona = a.id_zona
                     where z.id_sala = s.id_sala and a.es_habilitado) as capacidad,
                   (select string_agg(z.nombre, ', ' order by z.id_zona) from cine.zona z where z.id_sala = s.id_sala) as zonas,
                   cine.sala_tiene_ventas(s.id_sala) as tiene_ventas
            from cine.sala s join cine.sede se on se.id_sede = s.id_sede
            where {SOLO_DEMO}
            order by se.nombre, s.nombre""").fetchall()
        sedes = con.execute(f"select se.id_sede, se.nombre from cine.sede se where {SOLO_DEMO} order by se.nombre").fetchall()
    return web.mostrar(request, "admin_salas.html", salas=lista, sedes=sedes)


@router.post("/salas")
def alta_sala(request: Request, id_sede: int = Form(...), nombre: str = Form(...), formato: str = Form(...),
              filas_general: int = Form(...), filas_preferencial: int = Form(...), filas_vip: int = Form(...),
              asientos_por_fila: int = Form(...), usuario=Depends(administrador)):
    """Crea la sala con su distribución: las filas se asignan en orden a general, preferencial y VIP."""
    letras = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    zonas = [("general", "General", filas_general), ("preferencial", "Preferencial", filas_preferencial),
             ("vip", "VIP", filas_vip)]
    if sum(z[2] for z in zonas) > len(letras) or asientos_por_fila < 1:
        web.avisar(request, "La sala puede tener como máximo 26 filas y al menos un asiento por fila.", "error")
        return web.ir_a("/admin/salas")
    try:
        with tx(request, usuario) as con:
            id_sala = con.execute("insert into cine.sala (id_sede, nombre, formato) values (%s, %s, %s) returning id_sala",
                                  (id_sede, nombre.strip(), formato.strip())).fetchone()["id_sala"]
            fila = 0
            for codigo, nombre_zona, cantidad in zonas:
                if cantidad <= 0:
                    continue
                id_zona = con.execute("""
                    insert into cine.zona (id_sala, id_tipo_zona, nombre)
                    values (%s, (select id_tipo_zona from cine.tipo_zona where codigo = %s), %s) returning id_zona""",
                    (id_sala, codigo, nombre_zona)).fetchone()["id_zona"]
                for _ in range(cantidad):
                    con.execute("""insert into cine.asiento (id_zona, fila, numero)
                                   select %s, %s, n from generate_series(1, %s) as n""",
                                (id_zona, letras[fila], asientos_por_fila))
                    fila += 1
            con.execute("insert into cine.puerta (id_sala, codigo, tipo) values (%s, %s, 'totem')",
                        (id_sala, f"P-{id_sala}-1"))
        web.avisar(request, f"Sala «{nombre}» creada.")
    except psycopg.Error as e:
        web.avisar(request, db.mensaje_error(e), "error")
    return web.ir_a("/admin/salas")


@router.post("/salas/{id_sala}/activa")
def cambiar_estado_sala(id_sala: int, request: Request, activa: bool = Form(...), usuario=Depends(administrador)):
    """RN-18: el trigger rechaza desactivar una sala con entradas vendidas o reservadas."""
    ejecutar_cambio(request, usuario, "update cine.sala set es_activa = %s where id_sala = %s", (activa, id_sala),
                    "Sala activada." if activa else "Sala desactivada.")
    return web.ir_a("/admin/salas")


# Funciones ------------------------------------------------------------------------------

@router.get("/funciones")
def funciones(request: Request, usuario=Depends(administrador)):
    with tx(request, usuario) as con:
        lista = con.execute(f"""
            select f.*, p.titulo, s.nombre as sala, se.nombre as sede
            from cine.funcion f
            join cine.pelicula p on p.id_pelicula = f.id_pelicula
            join cine.sala s on s.id_sala = f.id_sala
            join cine.sede se on se.id_sede = s.id_sede
            where f.fin > now() and {SOLO_DEMO}
            order by f.inicio limit 120""").fetchall()
        peliculas_activas = con.execute("select id_pelicula, titulo, duracion_min from cine.pelicula where es_activa order by titulo").fetchall()
        salas_activas = con.execute(f"""
            select s.id_sala, se.nombre || ' · ' || s.nombre as nombre
            from cine.sala s join cine.sede se on se.id_sede = s.id_sede
            where s.es_activa and {SOLO_DEMO} order by se.nombre, s.nombre""").fetchall()
        limpieza = con.execute("select cine.parametro('minutos_limpieza') as m").fetchone()["m"]
    return web.mostrar(request, "admin_funciones.html", funciones=lista, peliculas=peliculas_activas,
                       salas=salas_activas, limpieza=int(limpieza))


@router.post("/funciones")
def alta_funcion(request: Request, id_pelicula: int = Form(...), id_sala: int = Form(...), inicio: str = Form(...),
                 idioma: str = Form(...), usuario=Depends(administrador)):
    """El fin se calcula con la duración de la película y el tiempo de limpieza; el trigger rechaza traslapes."""
    hora = datetime.datetime.fromisoformat(inicio).replace(tzinfo=web.HORA_LOCAL)
    ejecutar_cambio(request, usuario, """
        insert into cine.funcion (id_pelicula, id_sala, inicio, fin, idioma)
        select p.id_pelicula, %(sala)s, %(inicio)s,
               %(inicio)s + make_interval(mins => p.duracion_min + cine.parametro('minutos_limpieza')::int), %(idioma)s
        from cine.pelicula p where p.id_pelicula = %(pelicula)s""",
        {"sala": id_sala, "inicio": hora, "idioma": idioma, "pelicula": id_pelicula},
        f"Función programada para el {hora:%d/%m/%Y %H:%M}.")
    return web.ir_a("/admin/funciones")


@router.post("/funciones/{id_funcion}/cancelar")
def cancelar_funcion(id_funcion: int, request: Request, motivo: str = Form(...), usuario=Depends(administrador)):
    try:
        with tx(request, usuario) as con:
            n = con.execute("select cine.cancelar_funcion(%s, %s) as n", (id_funcion, motivo)).fetchone()["n"]
        web.avisar(request, f"Función cancelada. Boletos reembolsados: {n}.")
    except psycopg.Error as e:
        web.avisar(request, db.mensaje_error(e), "error")
    return web.ir_a("/admin/funciones")


# Matriz de precios ----------------------------------------------------------------------

@router.get("/precios")
def precios(request: Request, sede: int | None = None, usuario=Depends(administrador)):
    with tx(request, usuario) as con:
        sedes = con.execute(f"select se.id_sede, se.nombre from cine.sede se where {SOLO_DEMO} order by se.nombre").fetchall()
        id_sede = sede or sedes[0]["id_sede"]
        tarifas = con.execute("""
            select t.id_tarifa, t.precio, t.tipo_dia, tz.nombre as zona, tt.nombre as tipo
            from cine.tarifa t
            join cine.tipo_zona tz on tz.id_tipo_zona = t.id_tipo_zona
            join cine.tipo_tarifa tt on tt.id_tipo_tarifa = t.id_tipo_tarifa
            where t.id_sede = %s
            order by tz.id_tipo_zona, tt.id_tipo_tarifa, t.tipo_dia""", (id_sede,)).fetchall()
        promociones = con.execute("""
            select pr.*, tt.nombre as tipo_tarifa from cine.promocion pr
            left join cine.tipo_tarifa tt on tt.id_tipo_tarifa = pr.id_tipo_tarifa order by pr.id_promocion""").fetchall()
    # Una fila por zona y tipo de entrada, con una columna por tipo de día
    filas = {}
    for t in tarifas:
        filas.setdefault((t["zona"], t["tipo"]), {"zona": t["zona"], "tipo": t["tipo"]})[t["tipo_dia"]] = t
    return web.mostrar(request, "admin_precios.html", sedes=sedes, id_sede=id_sede, filas=list(filas.values()),
                       promociones=promociones)


@router.post("/precios")
async def guardar_precios(request: Request, usuario=Depends(administrador)):
    formulario = await request.form()
    id_sede = int(formulario["sede"])
    nuevos = {int(k.split("_")[1]): v for k, v in formulario.items() if k.startswith("precio_")}
    cambiados = 0
    try:
        with tx(request, usuario) as con:
            actuales = {f["id_tarifa"]: f["precio"] for f in con.execute(
                "select id_tarifa, precio from cine.tarifa where id_sede = %s", (id_sede,)).fetchall()}
            for id_tarifa, valor in nuevos.items():
                if id_tarifa in actuales and float(valor) != float(actuales[id_tarifa]):
                    con.execute("update cine.tarifa set precio = %s where id_tarifa = %s", (valor, id_tarifa))
                    cambiados += 1
        web.avisar(request, f"Precios actualizados: {cambiados}. Cada cambio quedó en la auditoría.")
    except (psycopg.Error, ValueError) as e:
        web.avisar(request, db.mensaje_error(e) if isinstance(e, psycopg.Error) else "Precio inválido.", "error")
    return web.ir_a(f"/admin/precios?sede={id_sede}")


# Boletos: anulaciones, reembolsos, cambios de asiento y cortesías -------------------------

@router.get("/boletos")
def boletos(request: Request, qr: str = "", usuario=Depends(administrador)):
    boleto, asientos_libres = None, []
    with tx(request, usuario) as con:
        if qr:
            boleto = con.execute("""
                select b.*, p.titulo, f.inicio, s.nombre as sala, se.nombre as sede, a.fila, a.numero, z.nombre as zona,
                       o.id_usuario_cliente, (select email from cine.usuario where id_usuario = o.id_usuario_cliente) as cliente,
                       exists (select 1 from cine.checkin c where c.id_boleto = b.id_boleto) as utilizado
                from cine.boleto b
                join cine.orden o on o.id_orden = b.id_orden
                join cine.funcion f on f.id_funcion = b.id_funcion
                join cine.pelicula p on p.id_pelicula = f.id_pelicula
                join cine.sala s on s.id_sala = f.id_sala
                join cine.sede se on se.id_sede = s.id_sede
                join cine.asiento a on a.id_asiento = b.id_asiento
                join cine.zona z on z.id_zona = a.id_zona
                where b.codigo_qr = %s""", (qr.strip(),)).fetchone()
            if boleto is None:
                web.avisar(request, "No existe un boleto con ese código.", "error")
            else:
                asientos_libres = con.execute("""
                    select id_asiento, fila, numero, zona from cine.v_mapa_asientos
                    where id_funcion = %s and estado = 'disponible' order by fila, numero""", (boleto["id_funcion"],)).fetchall()
        funciones_demo = con.execute(f"""
            select f.id_funcion, p.titulo, se.nombre as sede, s.nombre as sala, f.inicio
            from cine.funcion f join cine.pelicula p on p.id_pelicula = f.id_pelicula
            join cine.sala s on s.id_sala = f.id_sala join cine.sede se on se.id_sede = s.id_sede
            where f.estado = 'programada' and f.inicio > now() and {SOLO_DEMO}
            order by f.inicio limit 40""").fetchall()
    return web.mostrar(request, "admin_boletos.html", qr=qr, boleto=boleto, asientos_libres=asientos_libres,
                       funciones=funciones_demo)


@router.post("/boletos/{id_boleto}/anular")
def anular(id_boleto: int, request: Request, qr: str = Form(...), motivo: str = Form(...), tipo: str = Form(...),
           usuario=Depends(administrador)):
    """RN-19: por política solo hasta 2 horas antes; el reembolso forzado queda auditado (RN-20)."""
    try:
        with tx(request, usuario) as con:
            monto = con.execute("select cine.anular_boleto(%s, %s, %s) as m", (id_boleto, motivo, tipo)).fetchone()["m"]
        web.avisar(request, f"Boleto anulado. Reembolso: {monto} USD. El asiento quedó libre.")
    except psycopg.Error as e:
        web.avisar(request, db.mensaje_error(e), "error")
    return web.ir_a(f"/admin/boletos?qr={qr}")


@router.post("/boletos/{id_boleto}/cambiar-asiento")
def cambiar_asiento(id_boleto: int, request: Request, qr: str = Form(...), id_asiento: int = Form(...),
                    motivo: str = Form(...), usuario=Depends(administrador)):
    ejecutar_cambio(request, usuario, "select cine.cambiar_asiento(%s, %s, %s)", (id_boleto, id_asiento, motivo),
                    "Asiento cambiado. La operación quedó en la auditoría.")
    return web.ir_a(f"/admin/boletos?qr={qr}")


@router.post("/cortesia")
def cortesia(request: Request, id_funcion: int = Form(...), fila: str = Form(...), numero: int = Form(...),
             email: str = Form(...), motivo: str = Form(...), usuario=Depends(administrador)):
    try:
        with tx(request, usuario) as con:
            asiento = con.execute("""
                select id_asiento from cine.v_mapa_asientos where id_funcion = %s and fila = %s and numero = %s""",
                (id_funcion, fila.strip().upper(), numero)).fetchone()
            cliente = con.execute("select id_usuario from cine.usuario where lower(email) = lower(%s)", (email.strip(),)).fetchone()
            if asiento is None or cliente is None:
                raise ValueError("El asiento o el cliente no existen.")
            id_boleto = con.execute("select cine.otorgar_cortesia(%s, %s, %s, %s) as b",
                                    (id_funcion, asiento["id_asiento"], cliente["id_usuario"], motivo)).fetchone()["b"]
            qr = con.execute("select codigo_qr from cine.boleto where id_boleto = %s", (id_boleto,)).fetchone()["codigo_qr"]
        web.avisar(request, "Cortesía otorgada. La operación quedó en la auditoría.")
        return web.ir_a(f"/admin/boletos?qr={qr}")
    except (psycopg.Error, ValueError) as e:
        web.avisar(request, db.mensaje_error(e) if isinstance(e, psycopg.Error) else str(e), "error")
        return web.ir_a("/admin/boletos")


# Auditoría ------------------------------------------------------------------------------

@router.get("/auditoria")
def auditoria(request: Request, admin: int | None = None, usuario=Depends(administrador)):
    """RN-20: operaciones manuales con fecha y hora, IP, rol y usuario responsable."""
    with tx(request, usuario) as con:
        registros = con.execute("""
            select a.ocurrido_en, a.id_usuario, u.nombre || ' ' || u.apellidos as responsable, r.nombre as rol, a.ip,
                   a.operacion, a.entidad, a.id_entidad, a.valores_anteriores, a.valores_nuevos, a.motivo
            from bitacora.admin_operacion_audit a
            join cine.usuario u on u.id_usuario = a.id_usuario
            join cine.rol r on r.id_rol = a.id_rol
            where (%(admin)s::bigint is null or a.id_usuario = %(admin)s)
              and a.ocurrido_en >= now() - interval '1 month'
            order by a.ocurrido_en desc limit 100""", {"admin": admin}).fetchall()
        administradores = con.execute("""
            select u.id_usuario, u.nombre || ' ' || u.apellidos as nombre from cine.usuario u
            join cine.rol r on r.id_rol = u.id_rol where r.codigo = 'administrador' order by u.id_usuario""").fetchall()
    return web.mostrar(request, "admin_auditoria.html", registros=registros, administradores=administradores, admin=admin)
