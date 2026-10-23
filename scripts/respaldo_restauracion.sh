#!/usr/bin/env bash
# Prueba local de respaldo y restauración (sección 10.6).
# Respalda la base imax con pg_dump, la restaura en una base nueva (imax_restaurada),
# compara los conteos de filas de las tablas principales y borra la copia.
#
#   bash scripts/respaldo_restauracion.sh
#
# Requiere el contenedor imax_db en marcha. En Git Bash, MSYS_NO_PATHCONV evita que se
# conviertan las rutas del contenedor.

set -euo pipefail
export MSYS_NO_PATHCONV=1

PSQL="docker exec imax_db psql -U imax_owner -v ON_ERROR_STOP=1 -At"
TABLAS="cine.funcion cine.ocupacion_asiento cine.orden cine.orden_detalle cine.pago cine.boleto cine.checkin cine.reembolso bitacora.transaccion_log bitacora.asiento_auditoria_log bitacora.acceso_puerta_log bitacora.admin_operacion_audit"

conteos() {
    for t in $TABLAS; do
        echo "$t $($PSQL -d "$1" -c "select count(*) from $t")"
    done
}

echo "1. Respaldo completo en formato comprimido (pg_dump -Fc)"
inicio=$(date +%s)
docker exec imax_db pg_dump -U imax_owner -d imax -Fc -f /tmp/imax.dump
echo "   Duración: $(( $(date +%s) - inicio )) s"
echo "   Tamaño de la base: $($PSQL -d imax -c "select pg_size_pretty(pg_database_size('imax'))")"
echo "   Tamaño del respaldo: $(docker exec imax_db du -h /tmp/imax.dump | cut -f1)"

echo "2. Restauración en una base nueva (pg_restore)"
$PSQL -d postgres -c "drop database if exists imax_restaurada" > /dev/null
$PSQL -d postgres -c "create database imax_restaurada" > /dev/null
inicio=$(date +%s)
docker exec imax_db pg_restore -U imax_owner -d imax_restaurada --exit-on-error /tmp/imax.dump
echo "   Duración: $(( $(date +%s) - inicio )) s"

echo "3. Comparación de filas (original y restaurada)"
diferencias=0
while read -r tabla original; do
    restaurada=$($PSQL -d imax_restaurada -c "select count(*) from $tabla")
    estado=OK
    [ "$original" = "$restaurada" ] || { estado=DIFERENTE; diferencias=$((diferencias + 1)); }
    printf "   %-32s %10s %10s  %s\n" "$tabla" "$original" "$restaurada" "$estado"
done < <(conteos imax)

echo "4. Limpieza"
$PSQL -d postgres -c "drop database imax_restaurada" > /dev/null
docker exec imax_db rm -f /tmp/imax.dump
echo "   Base restaurada y archivo de respaldo eliminados"

if [ "$diferencias" -eq 0 ]; then
    echo "RESULTADO: la restauración tiene las mismas filas que la base original"
else
    echo "RESULTADO: $diferencias tablas con diferencias"
    exit 1
fi
