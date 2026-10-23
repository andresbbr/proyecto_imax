# Arranca el proyecto completo en Windows con un solo comando:
#   powershell -ExecutionPolicy Bypass -File iniciar.ps1
#
# 1. Crea .env a partir de .env.example si no existe.
# 2. Levanta PostgreSQL en Docker y espera a que esté listo.
# 3. La primera vez crea la base y carga los datos de prueba (unos 2 minutos).
#    Con -Reiniciar vuelve a crear todo desde cero.
# 4. Instala las dependencias de Python y abre la aplicación en http://127.0.0.1:8000
#
# Requisitos: Docker Desktop abierto y Python 3.14 (comando py o python).

param([switch]$Reiniciar)

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

function Paso($texto) { Write-Host "`n== $texto" -ForegroundColor Cyan }

function Sql($argumentos) {
    # Usa el usuario y la base definidos en .env (variables del contenedor)
    docker exec imax_db sh -c "psql -U `"`$POSTGRES_USER`" -d `"`$POSTGRES_DB`" -v ON_ERROR_STOP=1 $argumentos"
    if ($LASTEXITCODE -ne 0) { throw "Falló: psql $argumentos" }
}

if (-not (Test-Path .env)) {
    Copy-Item .env.example .env
    Write-Host "Se creó .env a partir de .env.example (contraseñas de prueba)."
}

Paso "Levantando PostgreSQL en Docker"
docker compose up -d
if ($LASTEXITCODE -ne 0) { throw "No se pudo iniciar Docker. ¿Está abierto Docker Desktop?" }
for ($i = 0; $i -lt 60; $i++) {
    if ((docker inspect -f "{{.State.Health.Status}}" imax_db) -eq "healthy") { break }
    Start-Sleep -Seconds 2
}

$existe = docker exec imax_db sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Atc "select to_regclass(''cine.funcion'') is not null"'
if ($Reiniciar -or $existe -ne "t") {
    Paso "Creando la base de datos (esquema, funciones, roles)"
    Sql "-q -f /db/init.sql"
    Paso "Cargando los datos de prueba (tarda unos 2 minutos)"
    Sql "-q -f /db/seed/cargar.sql"
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
