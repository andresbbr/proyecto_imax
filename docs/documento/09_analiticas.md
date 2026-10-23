# 9. Consultas analíticas y resultados

Las 4 consultas que la gerencia consultará regularmente están en `db/analiticas`, una por archivo. `db/analiticas/ejecutar.sql` las corre juntas y además comprueba que sus resultados cuadran con los datos, calculando lo mismo por otro camino:

```
docker exec imax_db psql -U imax_owner -d imax -v ON_ERROR_STOP=1 -f /db/analiticas/ejecutar.sql
```

Los resultados de esta sección son la salida real sobre los datos de prueba (`docs/evidencias/analiticas_2026-10-23.txt`). Sus planes de ejecución están en la sección 8.2.

## 9.1 Ocupación y recaudación por función

Porcentaje de asientos vendidos frente a la capacidad de la sala e ingresos totales de una función específica. La función se elige con `-v id_funcion=...`; si no se indica, se usa la función ya realizada con más boletos vendidos.

```sql
select f.id_funcion, p.titulo, se.nombre as sede, s.nombre as sala, f.inicio,
       cap.capacidad, ven.vendidos,
       round(100.0 * ven.vendidos / cap.capacidad, 2) as porcentaje_ocupacion,
       ing.ventas - ing.reembolsos as ingresos_totales
from cine.funcion f
join cine.pelicula p on p.id_pelicula = f.id_pelicula
join cine.sala s on s.id_sala = f.id_sala
join cine.sede se on se.id_sede = s.id_sede
cross join lateral (select count(*) as capacidad from cine.asiento a join cine.zona z on z.id_zona = a.id_zona
                    where z.id_sala = f.id_sala and a.es_habilitado) as cap
cross join lateral (select count(*) as vendidos from cine.boleto b
                    where b.id_funcion = f.id_funcion and b.estado = 'vigente') as ven
cross join lateral (
    select coalesce((select sum(o.total) from cine.orden o
                     where o.id_funcion = f.id_funcion and o.estado = 'pagada'), 0) as ventas,
           coalesce((select sum(r.monto) from cine.reembolso r join cine.boleto b on b.id_boleto = r.id_boleto
                     where b.id_funcion = f.id_funcion), 0) as reembolsos) as ing
where f.id_funcion = :id_funcion;
```

| Función | Película | Sede | Inicio | Capacidad | Vendidos | Ocupación | Ingresos totales (USD) |
|---|---|---|---|---|---|---|---|
| 341 | Aventura en la selva | IMAX Sede 059 | 2026-07-25 16:00 UTC | 300 | 16 | 5.33 % | 286.58 |

Los ingresos son el total cobrado de las órdenes pagadas (tarifas menos descuentos, más cargo por servicio e impuesto) menos los reembolsos de la función. La ocupación es baja porque la carga de prueba vende como máximo 16 asientos por función.

## 9.2 Top 5 de películas de la última semana

Las 5 películas con más boletos vendidos en los últimos 7 días, a nivel global. Se cuentan los boletos vigentes (sin los anulados) emitidos en ese período; un boleto se emite en el momento en que se aprueba su pago.

```sql
select p.titulo, count(*) as boletos_vendidos
from cine.boleto b
join cine.funcion f on f.id_funcion = b.id_funcion
join cine.pelicula p on p.id_pelicula = f.id_pelicula
where b.estado = 'vigente'
  and b.emitido_en >= now() - interval '7 days'
group by p.id_pelicula, p.titulo
order by boletos_vendidos desc, p.titulo
limit 5;
```

| Posición | Película | Boletos vendidos |
|---|---|---|
| 1 | Noche de risas | 2,185 |
| 2 | Bosque de cristal | 2,097 |
| 3 | Ecos del pasado | 2,096 |
| 4 | Dragones de hielo | 2,044 |
| 5 | Ruta en llamas | 2,041 |

## 9.3 Métodos de pago preferidos

Porcentaje de pagos aprobados por método de pago, y porcentaje del monto cobrado.

```sql
select m.nombre as metodo_pago,
       count(*) as pagos,
       round(100.0 * count(*) / sum(count(*)) over (), 2) as porcentaje_pagos,
       sum(p.monto) as monto,
       round(100.0 * sum(p.monto) / sum(sum(p.monto)) over (), 2) as porcentaje_monto
from cine.pago p
join cine.metodo_pago m on m.id_metodo_pago = p.id_metodo_pago
where p.estado = 'aprobado'
group by m.id_metodo_pago, m.nombre
order by pagos desc;
```

| Método de pago | Pagos aprobados | % de pagos | Monto (USD) | % del monto |
|---|---|---|---|---|
| Tarjeta de crédito | 55,405 | 44.94 % | 1,544,535.75 | 44.90 % |
| Tarjeta de débito | 30,751 | 24.94 % | 858,097.55 | 24.94 % |
| PayPal | 18,479 | 14.99 % | 516,046.72 | 15.00 % |
| Billetera digital | 12,398 | 10.06 % | 345,275.69 | 10.04 % |
| Transferencia | 6,262 | 5.08 % | 176,201.30 | 5.12 % |

Los porcentajes reproducen la distribución con que se generaron los datos de prueba (45 %, 25 %, 15 %, 10 % y 5 %), lo que confirma que la consulta cuenta bien.

## 9.4 Auditoría de operaciones críticas del último mes

Operaciones manuales (cortesías, reembolsos, cambios de asiento y otros cambios de configuración) registradas en `bitacora.admin_operacion_audit` durante el último mes, agrupadas por administrador.

```sql
select a.id_usuario,
       u.nombre || ' ' || u.apellidos as administrador,
       count(*) as operaciones,
       count(*) filter (where a.operacion = 'cortesia') as cortesias,
       count(*) filter (where a.operacion like 'reembolso%') as reembolsos,
       count(*) filter (where a.operacion = 'cambio_asiento') as cambios_asiento,
       count(*) filter (where a.operacion <> 'cortesia' and a.operacion not like 'reembolso%'
                          and a.operacion <> 'cambio_asiento') as otros_cambios,
       min(a.ocurrido_en) as primera,
       max(a.ocurrido_en) as ultima
from bitacora.admin_operacion_audit a
join cine.usuario u on u.id_usuario = a.id_usuario
where a.ocurrido_en >= now() - interval '1 month'
  and a.id_rol = (select id_rol from cine.rol where codigo = 'administrador')
group by a.id_usuario, u.nombre, u.apellidos
order by operaciones desc, a.id_usuario;
```

| Id | Administrador | Operaciones | Cortesías | Reembolsos | Cambios de asiento | Otros cambios |
|---|---|---|---|---|---|---|
| 50015 | Administrador Sintético 9 | 716 | 108 | 136 | 111 | 361 |
| 50014 | Administrador Sintético 8 | 703 | 103 | 116 | 124 | 360 |
| 50008 | Administrador Sintético 2 | 689 | 103 | 108 | 115 | 363 |
| 6 | Fabián Jiménez | 686 | 101 | 126 | 130 | 329 |
| 50012 | Administrador Sintético 6 | 685 | 130 | 101 | 122 | 332 |
| 50009 | Administrador Sintético 3 | 659 | 107 | 108 | 118 | 326 |
| 50007 | Administrador Sintético 1 | 650 | 117 | 97 | 112 | 324 |
| 50011 | Administrador Sintético 5 | 648 | 91 | 123 | 102 | 332 |
| 50010 | Administrador Sintético 4 | 635 | 92 | 106 | 115 | 322 |
| 50013 | Administrador Sintético 7 | 623 | 101 | 118 | 102 | 302 |

Cada fila de la bitácora tiene además la fecha y hora, la IP y el rol del responsable (RN-20). Gracias al particionamiento por mes, la consulta solo lee las particiones del último mes (sección 8.2).

## 9.5 Comprobaciones

| Comprobación | Resultado |
|---|---|
| Ocupación: los boletos vendidos coinciden con las líneas de órdenes pagadas que no se reembolsaron | Cumple |
| Recaudación: las ventas de la función coinciden con los pagos aprobados de sus órdenes | Cumple |
| Top 5: los boletos emitidos en la semana coinciden con los de las órdenes pagadas en la semana | Cumple |
| Métodos de pago: los porcentajes suman 100 % | Cumple |
| Métodos de pago: hay un pago aprobado por cada orden pagada con monto | Cumple |
| Auditoría: la suma de las filas agrupadas coincide con las operaciones del último mes | Cumple |

Las 4 consultas corren sin errores y sus resultados cuadran con los datos.
