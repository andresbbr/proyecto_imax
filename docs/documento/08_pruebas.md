# 8. Pruebas de concurrencia y rendimiento

Todas las cifras de esta sección salen de ejecuciones reales contra la base del proyecto (PostgreSQL 16.15), con los datos de `db/seed/cargar.sql`: unos 1.8 millones de filas, ver `docs/evidencias/carga_datos_2026-10-23.txt`.

## 8.1 Prueba de concurrencia: doble venta

**Objetivo.** Demostrar que, cuando muchos clientes piden el mismo asiento de la misma función en el mismo instante, la base de datos deja pasar exactamente a uno y rechaza al resto.

**Método.** El script `scripts/concurrencia.py` (Python con hilos y `psycopg`) repite este procedimiento:

1. Abre N conexiones a la base, cada una con el rol `rol_cliente`, y elige un asiento libre de una función futura.
2. Los N hilos esperan en una barrera (`threading.Barrier`) y, al liberarse, llaman todos a la vez a `cine.bloquear_asientos(funcion, cliente, [asiento])`, cada uno con un cliente distinto y el **mismo asiento**.
3. Cada llamada es una transacción. La primera que inserta la fila `(id_funcion, id_asiento)` en `ocupacion_asiento` gana. Las demás chocan con la clave primaria: su transacción interna se revierte, la colisión queda en `asiento_auditoria_log` y la función devuelve nulo.
4. Al terminar, el script cuenta los ganadores y verifica en la base:
   - que el asiento tenga una sola fila en `ocupacion_asiento`;
   - que exista una sola orden pendiente con ese asiento;
   - que haya N - 1 colisiones registradas.

Se hicieron 25 corridas con 20 hilos y 25 corridas con 50 hilos, cada una con un asiento distinto:

```
py scripts/concurrencia.py --corridas 25 --salida docs/evidencias/concurrencia_2026-10-23.txt
```

**Resultados** (`docs/evidencias/concurrencia_2026-10-23.txt`):

| Hilos simultáneos | Corridas | Ganadores por corrida | Rechazados por corrida | Errores | Filas del asiento | Colisiones registradas | Duración de la corrida |
|---|---|---|---|---|---|---|---|
| 20 | 25 | 1 en las 25 | 19 en las 25 | 0 | 1 en las 25 | 19 en las 25 | 0.037 a 0.045 s (promedio 0.040 s) |
| 50 | 25 | 1 en las 25 | 49 en las 25 | 0 | 1 en las 25 | 49 en las 25 | 0.087 a 0.221 s (promedio 0.106 s) |

En las 50 corridas hubo **exactamente un ganador y cero duplicados**. El mecanismo no necesita bloqueos explícitos: basta con una transacción y la restricción de unicidad (la clave primaria de `ocupacion_asiento`). Cuando dos transacciones insertan la misma clave, PostgreSQL hace esperar a la segunda hasta que la primera confirma, y entonces la rechaza por clave duplicada.

## 8.2 Planes de ejecución antes y después de los índices

**Método.** El script `db/analiticas/explain_indices.sql` mide 6 consultas con `EXPLAIN (ANALYZE, BUFFERS)` en dos fases:

1. **Antes:** sin los 11 índices de `db/ddl/05_indices.sql`. Siguen existiendo los índices de las claves primarias y de las restricciones UNIQUE, que son parte de la integridad del modelo.
2. **Después:** con los índices creados otra vez.

En cada fase se hace `ANALYZE` y cada consulta se ejecuta una vez antes de medirla, para que en las dos fases los datos estén en memoria y la comparación sea justa.

```
docker exec imax_db psql -U imax_owner -d imax -v ON_ERROR_STOP=1 -f /db/analiticas/explain_indices.sql
```

**Resultados** (`docs/evidencias/explain_antes_despues_2026-10-23.txt`; costo estimado del nodo raíz, tiempo de ejecución y páginas leídas en memoria):

| Consulta | Lectura antes | Lectura después | Costo antes | Costo después | Tiempo antes | Tiempo después | Páginas antes | Páginas después |
|---|---|---|---|---|---|---|---|---|
| Asientos libres de las funciones de una sala en 7 días | Seq Scan en `funcion` | Bitmap Index Scan en `ix_funcion_sala_inicio` | 2,418.80 | 1,362.83 | 7.683 ms | 6.199 ms | 602 | 266 |
| Ocupación y recaudación de una función | Seq Scan en `orden` | Index Scan en `ix_orden_funcion` | 4,145.37 | 289.60 | 6.375 ms | 0.230 ms | 2,090 | 79 |
| Top 5 de películas de la última semana | Parallel Seq Scan en `boleto` | Bitmap Index Scan en `ix_boleto_emitido_en` | 7,407.63 | 5,530.48 | 24.773 ms | 14.879 ms | 4,446 | 1,105 |
| Mapa de asientos de una función | Index Scan en `uq_asiento_zona_fila_numero` y PK de `ocupacion_asiento` | Igual | 96.50 | 96.50 | 0.230 ms | 0.239 ms | 326 | 326 |
| Métodos de pago | Parallel Seq Scan en `pago` | Igual | 5,225.39 | 5,228.35 | 20.162 ms | 20.523 ms | 2,498 | 2,498 |
| Auditoría del último mes | Seq Scan solo en las particiones del último mes (10 particiones descartadas) | Igual | 779.26 | 779.26 | 2.862 ms | 2.939 ms | 191 | 191 |

**Lectura de los resultados:**

- **Ocupación y recaudación de una función.** Sin índice, PostgreSQL recorre las 124 mil órdenes para encontrar las 8 de la función. Con `ix_orden_funcion` va directo a ellas: el costo baja de 4,145 a 290 y el tiempo de 6.4 ms a 0.23 ms, unas 28 veces menos.
- **Top 5 de la semana.** Sin índice se leen los 234 mil boletos. Con `ix_boleto_emitido_en` solo se leen los unos 24 mil emitidos en los últimos 7 días: un cuarto de las páginas y un 40 % menos de tiempo.
- **Asientos libres por sala.** El índice `ix_funcion_sala_inicio` reemplaza la lectura de las 29 mil funciones por la búsqueda de las 34 de esa sala en la semana. El tiempo total baja menos (de 7.7 a 6.2 ms) porque el resto de la consulta, el cruce con la ocupación, no cambia.
- **Mapa de asientos de una función.** Ya usa índices antes de crear los de `05_indices.sql`: el UNIQUE `(id_zona, fila, numero)` de `asiento` y la clave primaria `(id_funcion, id_asiento)` de `ocupacion_asiento` sirven para buscar por su primera columna. Por eso no se crearon índices aparte sobre `asiento(id_zona)` ni `zona(id_sala)`: serían redundantes.
- **Métodos de pago.** Suma todos los pagos aprobados, así que tiene que leer la tabla completa. La lectura secuencial (en paralelo) es el plan correcto y ningún índice lo mejora.
- **Auditoría del último mes.** Lo que acelera esta consulta es el particionamiento por mes: PostgreSQL descarta las particiones de meses anteriores y solo lee las del último mes. El índice `ix_admin_audit_usuario_fecha` sirve para consultar el historial de un administrador en particular.

**Escala.** Con el volumen de producción (15 millones de boletos al mes, sección 3) la diferencia crece: el costo de una lectura secuencial crece con el tamaño de la tabla, mientras que una búsqueda por índice depende sobre todo de cuántas filas devuelve. La carga de prueba se limitó a unos 1.8 millones de filas por la capacidad de disco del equipo de desarrollo; con más espacio se puede subir con `-v salas=... -v dias=...`.
