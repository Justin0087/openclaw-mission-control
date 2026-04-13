<#
.SYNOPSIS
    OpenClaw Mission Control - 一键启动脚本 (Windows Docker 全栈)
.DESCRIPTION
    启动完整的 Docker Compose 服务栈 (db, redis, backend, frontend, webhook-worker)。
    自动检查 Docker 运行状态、.env 配置，启动服务并等待健康检查通过。
.PARAMETER Down
    停止所有服务 (保留数据)
.PARAMETER Restart
    重启所有服务
.PARAMETER Logs
    跟踪查看所有服务日志
.PARAMETER Status
    查看服务状态
.EXAMPLE
    .\start.ps1           # 启动
    .\start.ps1 -Down     # 停止
    .\start.ps1 -Restart  # 重启
    .\start.ps1 -Logs     # 查看日志
    .\start.ps1 -Status   # 查看状态
#>

param(
    [switch]$Down,
    [switch]$Restart,
    [switch]$Logs,
    [switch]$Status
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
Set-Location $RepoRoot

$ComposeCmd = "docker compose -f compose.yml --env-file .env"

# --- 颜色输出 ---
function Write-Step  { param([string]$msg) Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-Ok    { param([string]$msg) Write-Host "  [OK] $msg" -ForegroundColor Green }
function Write-Warn  { param([string]$msg) Write-Host "  [WARN] $msg" -ForegroundColor Yellow }
function Write-Err   { param([string]$msg) Write-Host "  [ERR] $msg" -ForegroundColor Red }

# ============================================================
# 前置检查
# ============================================================
function Test-Prerequisites {
    Write-Step "前置检查"

    # Docker
    $dockerOk = $false
    try {
        docker info 2>&1 | Out-Null
        Write-Ok "Docker daemon 运行中"
        $dockerOk = $true
    } catch {
        Write-Err "Docker 未运行。请先启动 Docker Desktop。"
        $dde = "$env:ProgramFiles\Docker\Docker\Docker Desktop.exe"
        if (Test-Path $dde) {
            Write-Host "  尝试自动启动 Docker Desktop..." -ForegroundColor Yellow
            Start-Process $dde
            Write-Host "  等待 Docker 就绪 (最多 90 秒)..." -ForegroundColor Yellow
            for ($i = 0; $i -lt 18; $i++) {
                Start-Sleep -Seconds 5
                try {
                    docker info 2>&1 | Out-Null
                    Write-Ok "Docker Desktop 已就绪"
                    $dockerOk = $true
                    break
                } catch { }
            }
        }
        if (-not $dockerOk) {
            Write-Err "Docker 无法启动。请手动打开 Docker Desktop 后重试。"
            exit 1
        }
    }

    # docker compose
    try {
        $ver = docker compose version 2>&1
        Write-Ok "Docker Compose: $ver"
    } catch {
        Write-Err "docker compose 不可用"
        exit 1
    }

    # .env
    if (-not (Test-Path ".env")) {
        Write-Err ".env 文件不存在。请先运行 .\setup.ps1"
        exit 1
    }
    Write-Ok ".env 文件存在"

    # 检查 LOCAL_AUTH_TOKEN
    $token = (Select-String -Path ".env" -Pattern "^LOCAL_AUTH_TOKEN=(.+)" | ForEach-Object { $_.Matches[0].Groups[1].Value })
    if (-not $token -or $token.Length -lt 50) {
        Write-Err "LOCAL_AUTH_TOKEN 未设置或太短。请运行 .\setup.ps1 生成"
        exit 1
    }
    Write-Ok "LOCAL_AUTH_TOKEN 已配置 ($($token.Length) 字符)"

    return $token
}

# ============================================================
# 停止服务
# ============================================================
if ($Down) {
    Write-Step "停止所有服务"
    Invoke-Expression "$ComposeCmd down"
    Write-Ok "所有服务已停止 (数据保留在 Docker volume 中)"
    Write-Host "  如需删除数据: docker compose -f compose.yml --env-file .env down -v" -ForegroundColor DarkGray
    exit 0
}

# ============================================================
# 查看日志
# ============================================================
if ($Logs) {
    Write-Step "跟踪服务日志 (Ctrl+C 退出)"
    Invoke-Expression "$ComposeCmd logs -f --tail 100"
    exit 0
}

# ============================================================
# 查看状态
# ============================================================
if ($Status) {
    Write-Step "服务状态"
    Invoke-Expression "$ComposeCmd ps"
    exit 0
}

# ============================================================
# 重启
# ============================================================
if ($Restart) {
    Write-Step "重启所有服务"
    Invoke-Expression "$ComposeCmd down"
    # fall through to startup
}

# ============================================================
# 启动流程
# ============================================================
$token = Test-Prerequisites

Write-Step "构建并启动服务"
Write-Host "  首次构建可能需要数分钟，请耐心等待..." -ForegroundColor Yellow
Invoke-Expression "$ComposeCmd up -d --build"

Write-Step "等待服务就绪"

# 等待 backend 健康检查
$maxWait = 120
$waited = 0
$backendReady = $false
Write-Host "  等待 Backend 就绪 (最多 ${maxWait} 秒)..." -ForegroundColor Gray

while ($waited -lt $maxWait) {
    Start-Sleep -Seconds 3
    $waited += 3
    try {
        $resp = Invoke-WebRequest -Uri "http://localhost:8000/healthz" -UseBasicParsing -TimeoutSec 3 -ErrorAction Stop
        if ($resp.StatusCode -eq 200) {
            $backendReady = $true
            break
        }
    } catch { }
    Write-Host "." -NoNewline -ForegroundColor DarkGray
}
Write-Host ""

if ($backendReady) {
    Write-Ok "Backend 就绪 (${waited}s)"
} else {
    Write-Warn "Backend 在 ${maxWait}s 内未就绪，可能仍在启动中"
    Write-Host "  查看日志: .\start.ps1 -Logs" -ForegroundColor Yellow
}

# 等待 frontend
$waited = 0
$frontendReady = $false
Write-Host "  等待 Frontend 就绪 (最多 60 秒)..." -ForegroundColor Gray

while ($waited -lt 60) {
    Start-Sleep -Seconds 3
    $waited += 3
    try {
        $resp = Invoke-WebRequest -Uri "http://localhost:3000" -UseBasicParsing -TimeoutSec 3 -ErrorAction Stop
        if ($resp.StatusCode -eq 200) {
            $frontendReady = $true
            break
        }
    } catch { }
    Write-Host "." -NoNewline -ForegroundColor DarkGray
}
Write-Host ""

if ($frontendReady) {
    Write-Ok "Frontend 就绪 (${waited}s)"
} else {
    Write-Warn "Frontend 在 60s 内未响应"
}

# 展示服务状态
Write-Step "服务状态"
Invoke-Expression "$ComposeCmd ps"

# ============================================================
# 完成
# ============================================================
Write-Host "`n" -NoNewline
Write-Host "========================================" -ForegroundColor Green
Write-Host "  Mission Control 已启动!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "  前端:       http://localhost:3000" -ForegroundColor White
Write-Host "  后端健康:   http://localhost:8000/healthz" -ForegroundColor White
Write-Host "  API 文档:   http://localhost:8000/docs" -ForegroundColor White
Write-Host ""
Write-Host "  登录方式:   AUTH_MODE=local" -ForegroundColor White
Write-Host "  登录 Token: " -NoNewline -ForegroundColor White
Write-Host "$token" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  常用命令:" -ForegroundColor Cyan
Write-Host "    .\start.ps1 -Status   # 查看服务状态" -ForegroundColor Gray
Write-Host "    .\start.ps1 -Logs     # 查看服务日志" -ForegroundColor Gray
Write-Host "    .\start.ps1 -Down     # 停止服务" -ForegroundColor Gray
Write-Host "    .\start.ps1 -Restart  # 重启服务" -ForegroundColor Gray
Write-Host ""
