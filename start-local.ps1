<#
.SYNOPSIS
  Plan B local stack helper for Windows.

.DESCRIPTION
  Runs the local Windows development stack without Docker.
  PostgreSQL must be installed and Redis must exist under .local\redis.

.PARAMETER Down
  Stop Redis, backend, and frontend.

.PARAMETER Status
  Print service status.

.EXAMPLE
  .\start-local.ps1
  .\start-local.ps1 -Down
  .\start-local.ps1 -Status
#>
param(
    [switch]$Down,
    [switch]$Status
)

$ErrorActionPreference = "Continue"
$ROOT = $PSScriptRoot
if (-not $ROOT) { $ROOT = (Get-Location).Path }

$UV_DIR = "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\astral-sh.uv_Microsoft.Winget.Source_8wekyb3d8bbwe"
$PG_BIN = "C:\Program Files\PostgreSQL\16\bin"
$REDIS_EXE = "$ROOT\.local\redis\redis-server.exe"
$REDIS_CLI = "$ROOT\.local\redis\redis-cli.exe"
$NEXT_CMD = "$ROOT\frontend\node_modules\.bin\next.cmd"

$env:PATH = "$UV_DIR;$PG_BIN;$env:PATH"
$env:NO_PROXY = "localhost,127.0.0.1"
$env:CYPRESS_INSTALL_BINARY = "0"
$env:NODE_TLS_REJECT_UNAUTHORIZED = "0"

function Write-Step($Message) { Write-Host "`n==> $Message" -ForegroundColor Cyan }
function Write-Ok($Message) { Write-Host "  [OK] $Message" -ForegroundColor Green }
function Write-Warn($Message) { Write-Host "  [WARN] $Message" -ForegroundColor Yellow }
function Write-Err($Message) { Write-Host "  [ERR] $Message" -ForegroundColor Red }

function Test-Url {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url,
        [int]$TimeoutSec = 3
    )

    try {
        $request = [System.Net.WebRequest]::Create($Url)
        $request.Proxy = $null
        $request.Timeout = $TimeoutSec * 1000
        $response = $request.GetResponse()
        $statusCode = [int]([System.Net.HttpWebResponse]$response).StatusCode
        $response.Close()
        return $statusCode -eq 200
    } catch {
        return $false
    }
}

function Get-PortListenerPid {
    param(
        [Parameter(Mandatory = $true)]
        [int]$Port
    )

    return (Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue).OwningProcess |
        Select-Object -First 1
}

function Stop-BackendProcesses {
    $backendProcesses = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Name -eq "python.exe" -and
            $_.CommandLine -and
            $_.CommandLine -match "app\.main:app"
        }

    foreach ($backendProcess in $backendProcesses) {
        Stop-Process -Id $backendProcess.ProcessId -Force -ErrorAction SilentlyContinue
    }

    $backendPid = Get-PortListenerPid -Port 8000
    if ($backendPid) {
        Stop-Process -Id $backendPid -Force -ErrorAction SilentlyContinue
    }
}

function Stop-FrontendProcesses {
    $frontendPid = Get-PortListenerPid -Port 3000
    if ($frontendPid) {
        Stop-Process -Id $frontendPid -Force -ErrorAction SilentlyContinue
    }

    $frontendProcesses = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Name -eq "node.exe" -and
            $_.CommandLine -and
            $_.CommandLine -match "next" -and
            $_.CommandLine -match [regex]::Escape("$ROOT\frontend")
        }

    foreach ($frontendProcess in $frontendProcesses) {
        Stop-Process -Id $frontendProcess.ProcessId -Force -ErrorAction SilentlyContinue
    }
}

if ($Status) {
    Write-Step "Service status"

    $pgService = Get-Service -Name "postgresql*" -ErrorAction SilentlyContinue
    if ($pgService -and $pgService.Status -eq "Running") {
        Write-Ok "PostgreSQL is running on port 5432"
    } else {
        Write-Err "PostgreSQL is not running"
    }

    $redisProcess = Get-Process -Name "redis-server" -ErrorAction SilentlyContinue
    if ($redisProcess) {
        Write-Ok "Redis is running (PID $($redisProcess.Id))"
    } else {
        Write-Err "Redis is not running"
    }

    if (Test-Url -Url "http://127.0.0.1:8000/healthz") {
        Write-Ok "Backend is running on port 8000"
    } else {
        Write-Err "Backend is not reachable"
    }

    if (Test-Url -Url "http://127.0.0.1:3000") {
        Write-Ok "Frontend is running on port 3000"
    } else {
        Write-Err "Frontend is not reachable"
    }

    exit 0
}

if ($Down) {
    Write-Step "Stopping local services"

    $redisProcess = Get-Process -Name "redis-server" -ErrorAction SilentlyContinue
    if ($redisProcess) {
        Stop-Process -Name "redis-server" -Force -ErrorAction SilentlyContinue
        Write-Ok "Redis stopped"
    } else {
        Write-Warn "Redis was not running"
    }

    Stop-BackendProcesses
    Write-Ok "Backend stopped"

    Stop-FrontendProcesses
    Write-Ok "Frontend stopped"

    Write-Host "`nAll local services have been stopped. PostgreSQL remains running as a Windows service." -ForegroundColor Cyan
    exit 0
}

Write-Host @"

------------------------------------------------------------
OpenClaw Mission Control - Local Start
Plan B: Windows hybrid mode (no Docker)
------------------------------------------------------------

"@ -ForegroundColor Cyan

Write-Step "Check PostgreSQL"
$pgService = Get-Service -Name "postgresql*" -ErrorAction SilentlyContinue
if ($pgService -and $pgService.Status -eq "Running") {
    Write-Ok "PostgreSQL is running"
} else {
    Write-Err "PostgreSQL is not running. Start the Windows PostgreSQL service first."
    Write-Host "  Suggested command: Start-Service postgresql-x64-16" -ForegroundColor Gray
    exit 1
}

Write-Step "Check Redis"
$redisProcess = Get-Process -Name "redis-server" -ErrorAction SilentlyContinue
if ($redisProcess) {
    Write-Ok "Redis is already running (PID $($redisProcess.Id))"
} else {
    if (-not (Test-Path $REDIS_EXE)) {
        Write-Err "Redis executable not found: $REDIS_EXE"
        exit 1
    }

    Write-Warn "Starting Redis"
    Start-Process -FilePath $REDIS_EXE -ArgumentList "--port 6379" -WindowStyle Hidden
    Start-Sleep -Seconds 1
    $redisProcess = Get-Process -Name "redis-server" -ErrorAction SilentlyContinue
    if ($redisProcess) {
        Write-Ok "Redis started (PID $($redisProcess.Id))"
    } else {
        Write-Err "Redis failed to start"
        exit 1
    }
}

Write-Step "Check configuration"
$backendEnv = "$ROOT\backend\.env"
if (-not (Test-Path $backendEnv)) {
    Write-Err "backend/.env does not exist. Create it before starting the stack."
    exit 1
}

$token = (Get-Content $backendEnv | Select-String "LOCAL_AUTH_TOKEN=(.+)" | ForEach-Object { $_.Matches[0].Groups[1].Value })
if ($token -and $token.Length -ge 50) {
    Write-Ok ".env is ready (token length $($token.Length))"
} else {
    Write-Err "LOCAL_AUTH_TOKEN is missing or shorter than 50 characters"
    exit 1
}

Write-Step "Check backend dependencies"
$venvPath = "$ROOT\backend\.venv"
if (-not (Test-Path $venvPath)) {
    Write-Warn "Installing backend dependencies"
    Push-Location "$ROOT\backend"
    & uv sync --extra dev
    Pop-Location
}
Write-Ok "Backend dependencies are ready"

Write-Step "Start backend"
$backendPid = Get-PortListenerPid -Port 8000
if ($backendPid) {
    Write-Warn "Port 8000 is already in use. Skipping backend start."
} else {
    Start-Process -FilePath "uv" -ArgumentList "run", "uvicorn", "app.main:app", "--reload", "--port", "8000" -WorkingDirectory "$ROOT\backend" -WindowStyle Minimized
    Write-Ok "Backend start requested"
}

Write-Step "Check frontend dependencies"
if (-not (Test-Path "$ROOT\frontend\node_modules\next")) {
    Write-Warn "Installing frontend dependencies"
    Push-Location "$ROOT\frontend"
    npm install
    Pop-Location
}
Write-Ok "Frontend dependencies are ready"

Write-Step "Start frontend"
$frontendPid = Get-PortListenerPid -Port 3000
if ($frontendPid) {
    Write-Warn "Port 3000 is already in use. Skipping frontend start."
} else {
    if (-not (Test-Path $NEXT_CMD)) {
        Write-Err "Frontend launcher not found: $NEXT_CMD"
        exit 1
    }

    Start-Process -FilePath $NEXT_CMD -ArgumentList "dev", "--webpack" -WorkingDirectory "$ROOT\frontend" -WindowStyle Minimized
    Write-Ok "Frontend start requested"
}

Write-Step "Wait for services"
$maxWait = 60
$elapsed = 0
$backendReady = $false
$frontendReady = $false

while ($elapsed -lt $maxWait -and (-not $backendReady -or -not $frontendReady)) {
    Start-Sleep -Seconds 2
    $elapsed += 2

    if (-not $backendReady -and (Test-Url -Url "http://127.0.0.1:8000/healthz" -TimeoutSec 2)) {
        $backendReady = $true
        Write-Ok "Backend ready (${elapsed}s)"
    }

    if (-not $frontendReady -and (Test-Url -Url "http://127.0.0.1:3000" -TimeoutSec 2)) {
        $frontendReady = $true
        Write-Ok "Frontend ready (${elapsed}s)"
    }
}

if (-not $backendReady) { Write-Err "Backend did not become ready within ${maxWait}s" }
if (-not $frontendReady) { Write-Err "Frontend did not become ready within ${maxWait}s" }

Write-Host @"

------------------------------------------------------------
Local stack is ready

Frontend:  http://127.0.0.1:3000
Backend:   http://127.0.0.1:8000
API docs:  http://127.0.0.1:8000/docs

Login mode: Local Auth
Token:      See backend/.env -> LOCAL_AUTH_TOKEN

Use 127.0.0.1 instead of localhost if a proxy intercepts local traffic.

Stop:   .\start-local.ps1 -Down
Status: .\start-local.ps1 -Status
------------------------------------------------------------

"@ -ForegroundColor Green