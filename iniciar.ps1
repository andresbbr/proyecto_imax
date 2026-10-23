# Arranca el proyecto completo en Windows con un solo comando, sobre el PostgreSQL 16 y el
# Python ya instalados en el equipo:
#   powershell -ExecutionPolicy Bypass -File iniciar.ps1
#
# 1. Crea .env a partir de .env.example si no existe.
# 2. La primera vez crea el usuario imax_owner y la base imax (pide la contraseña del
#    superusuario postgres de la instalación), crea el esquema y carga los datos de prueba
#    (unos 2 minutos). Con -Reiniciar vuelve a crear el esquema y los datos desde cero.
# 3. Instala las dependencias de Python y abre la aplicación en http://127.0.0.1:8000

param([switch]$Reiniciar)

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

function Paso($texto) { Write-Host "`n== $texto" -ForegroundColor Cyan }

if (-not (Test-Path .env)) {
    Copy-Item .env.example .env
    Write-Host "Se creó .env a partir de .env.example (contraseñas de prueba)."
}

# Variables del .env: conexión, contraseñas y clave de la sesión
$config = @{}
foreach ($linea in Get-Content .env -Encoding UTF8) {
    if ($linea -match '^\s*([A-Z_]+)\s*=\s*(.*)$') { $config[$Matches[1]] = $Matches[2].Trim() }
}
$servidor = if ($config.POSTGRES_HOST) { $config.POSTGRES_HOST } else { "localhost" }
$puerto = if ($config.POSTGRES_PORT) { $config.POSTGRES_PORT } else { "5432" }
$superusuario = if ($config.POSTGRES_SUPERUSER) { $config.POSTGRES_SUPERUSER } else { "postgres" }
$env:POSTGRES_PASSWORD = $config.POSTGRES_PASSWORD
$env:APP_DB_PASSWORD = $config.APP_DB_PASSWORD
$env:PGCLIENTENCODING = "UTF8"   # los scripts SQL están en UTF-8

# psql: el del PATH o el de la instalación de PostgreSQL
$psql = (Get-Command psql -ErrorAction SilentlyContinue).Source
if (-not $psql) {
    $psql = Get-ChildItem "C:\Program Files\PostgreSQL\*\bin\psql.exe" -ErrorAction SilentlyContinue |
        Sort-Object FullName | Select-Object -First 1 -ExpandProperty FullName
}
if (-not $psql) { throw "No se encontró psql. ¿Está instalado PostgreSQL 16?" }
Write-Host "psql: $psql"

function Sql([string]$usuario, [string]$base, [string[]]$argumentos, [string]$clave) {
    if ($clave) { $env:PGPASSWORD = $clave } else { Remove-Item Env:PGPASSWORD -ErrorAction SilentlyContinue }
    & $psql -h $servidor -p $puerto -U $usuario -d $base -v ON_ERROR_STOP=1 @argumentos
    $codigo = $LASTEXITCODE
    Remove-Item Env:PGPASSWORD -ErrorAction SilentlyContinue
    if ($codigo -ne 0) { throw "Falló psql $($argumentos -join ' ')" }
}

Paso "Conectando con PostgreSQL en ${servidor}:$puerto"
$env:PGPASSWORD = $config.POSTGRES_PASSWORD
$existe = & $psql -h $servidor -p $puerto -U imax_owner -d imax -Atc "select to_regclass('cine.funcion') is not null" 2>$null
Remove-Item Env:PGPASSWORD -ErrorAction SilentlyContinue

if ($LASTEXITCODE -ne 0) {
    Paso "Creando el usuario imax_owner y la base imax (contraseña del superusuario $superusuario)"
    Sql $superusuario "postgres" @("-f", "db/crear_base.sql") $config.POSTGRES_SUPERUSER_PASSWORD
}
if ($Reiniciar -or $existe -ne "t") {
    Paso "Creando el esquema, las funciones y los roles"
    Sql "imax_owner" "imax" @("-q", "-f", "db/init.sql") $config.POSTGRES_PASSWORD
    Paso "Cargando los datos de prueba (tarda unos 2 minutos)"
    Sql "imax_owner" "imax" @("-q", "-f", "db/seed/cargar.sql") $config.POSTGRES_PASSWORD
} else {
    Write-Host "La base ya existe; se usan sus datos. Para empezar de cero: iniciar.ps1 -Reiniciar"
}

Paso "Instalando las dependencias de Python"
$python = if (Get-Command py -ErrorAction SilentlyContinue) { "py" } else { "python" }
& $python -m pip install -q -r requirements.txt
if ($LASTEXITCODE -ne 0) { throw "No se pudieron instalar las dependencias de Python" }

Paso "Aplicación en http://127.0.0.1:8000 (Ctrl+C para detenerla)"
Write-Host "Usuarios de prueba: cliente@imax.demo, taquilla@imax.demo, puerta@imax.demo, contador@imax.demo, admin@imax.demo (contraseña imax2026)"
Start-Process powershell -WindowStyle Hidden -ArgumentList "-Command", "Start-Sleep 4; Start-Process http://127.0.0.1:8000"
& $python -m uvicorn app.main:app --port 8000
