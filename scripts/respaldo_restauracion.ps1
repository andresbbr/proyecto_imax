# Prueba local de respaldo y restauración (sección 10.6).
# Respalda la base imax con pg_dump, la restaura en una base nueva (imax_restaurada),
# compara los conteos de filas de las tablas principales y borra la copia.
#
#   powershell -ExecutionPolicy Bypass -File scripts/respaldo_restauracion.ps1
#
# Usa el PostgreSQL instalado y la conexión del archivo .env.

# Los errores de psql se revisan con su código de salida: sus avisos en stderr no detienen el script
$ErrorActionPreference = "Continue"
Set-Location (Split-Path $PSScriptRoot -Parent)

$config = @{}
foreach ($linea in Get-Content .env -Encoding UTF8) {
    if ($linea -match '^\s*([A-Z_]+)\s*=\s*(.*)$') { $config[$Matches[1]] = $Matches[2].Trim() }
}
$env:PGHOST = if ($config.POSTGRES_HOST) { $config.POSTGRES_HOST } else { "localhost" }
$env:PGPORT = if ($config.POSTGRES_PORT) { $config.POSTGRES_PORT } else { "5432" }
$env:PGUSER = "imax_owner"
$env:PGPASSWORD = $config.POSTGRES_PASSWORD
$env:PGCLIENTENCODING = "UTF8"

# Carpeta bin de PostgreSQL: la del psql del PATH o la de la instalación
$psql = (Get-Command psql -ErrorAction SilentlyContinue).Source
if (-not $psql) {
    # Se prefieren las herramientas de PostgreSQL 16, la versión del servidor del proyecto
    $psql = Get-ChildItem "C:\Program Files\PostgreSQL\*\bin\psql.exe" -ErrorAction SilentlyContinue |
        Sort-Object { $_.FullName -notlike "*\16\bin\*" }, FullName |
        Select-Object -First 1 -ExpandProperty FullName
}
if (-not $psql) { throw "No se encontró psql. ¿Está instalado PostgreSQL 16?" }
$bin = Split-Path $psql
function Consulta($base, $sql) { & "$bin\psql.exe" -d $base -v ON_ERROR_STOP=1 -Atc $sql }

$tablas = "cine.funcion", "cine.ocupacion_asiento", "cine.orden", "cine.orden_detalle", "cine.pago",
    "cine.boleto", "cine.checkin", "cine.reembolso", "bitacora.transaccion_log",
    "bitacora.asiento_auditoria_log", "bitacora.acceso_puerta_log", "bitacora.admin_operacion_audit"
$archivo = Join-Path $env:TEMP "imax.dump"

Write-Host "1. Respaldo completo en formato comprimido (pg_dump -Fc)"
$reloj = [Diagnostics.Stopwatch]::StartNew()
& "$bin\pg_dump.exe" -d imax -Fc -f $archivo
if ($LASTEXITCODE -ne 0) { throw "Falló pg_dump" }
Write-Host ("   Duración: {0:N0} s" -f $reloj.Elapsed.TotalSeconds)
Write-Host "   Tamaño de la base: $(Consulta imax "select pg_size_pretty(pg_database_size('imax'))")"
Write-Host ("   Tamaño del respaldo: {0:N0} MB" -f ((Get-Item $archivo).Length / 1MB))

Write-Host "2. Restauración en una base nueva (pg_restore)"
Consulta postgres "drop database if exists imax_restaurada" | Out-Null
Consulta postgres "create database imax_restaurada" | Out-Null
$reloj.Restart()
& "$bin\pg_restore.exe" -d imax_restaurada $archivo
if ($LASTEXITCODE -ne 0) {
    # Por ejemplo, un pg_restore más nuevo que el servidor emite parámetros que este no conoce.
    # El resultado se decide igual con la comparación de filas.
    Write-Host "   Aviso: pg_restore informó errores (ver arriba); se verifica con la comparación de filas"
}
Write-Host ("   Duración: {0:N0} s" -f $reloj.Elapsed.TotalSeconds)

Write-Host "3. Comparación de filas (original y restaurada)"
$diferencias = 0
foreach ($tabla in $tablas) {
    $original = Consulta imax "select count(*) from $tabla"
    $restaurada = Consulta imax_restaurada "select count(*) from $tabla"
    $estado = if ($original -eq $restaurada) { "OK" } else { $diferencias++; "DIFERENTE" }
    Write-Host ("   {0,-32} {1,10} {2,10}  {3}" -f $tabla, $original, $restaurada, $estado)
}

Write-Host "4. Limpieza"
Consulta postgres "drop database imax_restaurada" | Out-Null
Remove-Item $archivo
Write-Host "   Base restaurada y archivo de respaldo eliminados"

if ($diferencias -eq 0) {
    Write-Host "RESULTADO: la restauración tiene las mismas filas que la base original"
} else {
    Write-Host "RESULTADO: $diferencias tablas con diferencias"
    exit 1
}
