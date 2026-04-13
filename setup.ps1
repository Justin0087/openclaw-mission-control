<#
.SYNOPSIS
    OpenClaw Mission Control - 一键环境安装脚本 (Windows)
.DESCRIPTION
    安装 Docker Desktop，生成 .env 配置文件，准备好一切运行前置条件。
    运行后需要重启电脑（Docker Desktop 首次安装要求），然后执行 start.ps1 启动服务。
#>

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
$EnvFile = Join-Path $RepoRoot ".env"
$EnvExample = Join-Path $RepoRoot ".env.example"
$IssuesLog = Join-Path $RepoRoot "docs\deployment-issues.md"

# --- 颜色输出辅助 ---
function Write-Step  { param([string]$msg) Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-Ok    { param([string]$msg) Write-Host "  [OK] $msg" -ForegroundColor Green }
function Write-Warn  { param([string]$msg) Write-Host "  [WARN] $msg" -ForegroundColor Yellow }
function Write-Err   { param([string]$msg) Write-Host "  [ERR] $msg" -ForegroundColor Red }

# --- 问题记录 ---
$issues = [System.Collections.ArrayList]::new()
function Log-Issue {
    param([string]$title, [string]$detail, [string]$resolution)
    [void]$issues.Add(@{ title = $title; detail = $detail; resolution = $resolution })
}

# ============================================================
# 1. 检查管理员权限
# ============================================================
Write-Step "检查运行权限"
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Warn "当前非管理员权限运行。如果 Docker Desktop 需要安装，可能需要管理员权限。"
    Log-Issue "非管理员运行" "脚本以普通用户运行" "如果安装 Docker 失败，请右键 PowerShell → 以管理员身份运行，重新执行"
} else {
    Write-Ok "管理员权限"
}

# ============================================================
# 2. 检查并安装 Docker Desktop
# ============================================================
Write-Step "检查 Docker Desktop"

$dockerInPath = Get-Command docker -ErrorAction SilentlyContinue
$dockerExe = "$env:ProgramFiles\Docker\Docker\resources\bin\docker.exe"
$dockerDesktopExe = "$env:ProgramFiles\Docker\Docker\Docker Desktop.exe"

if ($dockerInPath -or (Test-Path $dockerExe)) {
    Write-Ok "Docker 已安装"
    $docker = if ($dockerInPath) { $dockerInPath.Source } else { $dockerExe }

    # 检查 Docker 是否正在运行
    try {
        & $docker info 2>&1 | Out-Null
        Write-Ok "Docker daemon 正在运行"
    } catch {
        Write-Warn "Docker 已安装但 daemon 未运行"
        if (Test-Path $dockerDesktopExe) {
            Write-Host "  正在启动 Docker Desktop..." -ForegroundColor Yellow
            Start-Process $dockerDesktopExe
            Write-Host "  等待 Docker Desktop 启动 (最多 120 秒)..." -ForegroundColor Yellow
            $waited = 0
            while ($waited -lt 120) {
                Start-Sleep -Seconds 5
                $waited += 5
                try {
                    & $docker info 2>&1 | Out-Null
                    Write-Ok "Docker Desktop 已启动"
                    break
                } catch { }
            }
            if ($waited -ge 120) {
                Write-Err "Docker Desktop 启动超时"
                Log-Issue "Docker 启动超时" "等待 120 秒后 Docker daemon 仍未就绪" "手动打开 Docker Desktop，等待托盘图标显示 running，然后重新执行脚本"
            }
        }
    }
} else {
    Write-Warn "Docker Desktop 未安装，正在通过 winget 安装..."
    Log-Issue "Docker 未安装" "系统中未检测到 Docker Desktop" "通过 winget 自动安装"

    try {
        winget install -e --id Docker.DockerDesktop --accept-package-agreements --accept-source-agreements
        Write-Ok "Docker Desktop 安装完成"
        Write-Warn "!!! Docker Desktop 首次安装需要重启电脑 !!!"
        Write-Warn "请重启后手动打开 Docker Desktop，等待其完成初始化，然后运行 start.ps1"
        Log-Issue "需要重启" "Docker Desktop 首次安装后需要重启 Windows" "重启电脑 → 打开 Docker Desktop → 等待就绪 → 运行 start.ps1"
    } catch {
        Write-Err "Docker Desktop 安装失败: $_"
        Log-Issue "Docker 安装失败" "$_" "手动下载安装: https://www.docker.com/products/docker-desktop"
    }
}

# ============================================================
# 3. 检查端口占用
# ============================================================
Write-Step "检查端口占用"
$requiredPorts = @(
    @{ Port = 3000; Name = "Frontend" },
    @{ Port = 5432; Name = "PostgreSQL" },
    @{ Port = 6379; Name = "Redis" },
    @{ Port = 8000; Name = "Backend" }
)

foreach ($p in $requiredPorts) {
    $conn = Get-NetTCPConnection -LocalPort $p.Port -ErrorAction SilentlyContinue
    if ($conn) {
        $pid = $conn[0].OwningProcess
        $proc = Get-Process -Id $pid -ErrorAction SilentlyContinue
        $procName = if ($proc) { $proc.ProcessName } else { "unknown" }
        Write-Warn "端口 $($p.Port) ($($p.Name)) 被占用 by $procName (PID: $pid)"
        Log-Issue "端口 $($p.Port) 被占用" "$($p.Name) 端口被 $procName (PID $pid) 占用" "停止占用进程或在 .env 中修改 $($p.Name) 端口"
    } else {
        Write-Ok "端口 $($p.Port) ($($p.Name)) 可用"
    }
}

# ============================================================
# 4. 生成 .env 配置文件
# ============================================================
Write-Step "生成 .env 配置文件"

if (Test-Path $EnvFile) {
    Write-Warn ".env 文件已存在，检查 LOCAL_AUTH_TOKEN..."
    $envContent = Get-Content $EnvFile -Raw
    if ($envContent -match 'LOCAL_AUTH_TOKEN=\s*$' -or $envContent -match 'LOCAL_AUTH_TOKEN=\s*#') {
        Write-Warn "LOCAL_AUTH_TOKEN 为空，将自动生成"
        $needsToken = $true
    } else {
        Write-Ok ".env 文件已存在且 TOKEN 已设置"
        $needsToken = $false
    }
} else {
    Write-Host "  从 .env.example 复制..." -ForegroundColor Gray
    Copy-Item $EnvExample $EnvFile
    $needsToken = $true
    Write-Ok ".env 文件已创建"
}

if ($needsToken) {
    # 生成 64 字符的安全随机 token
    $bytes = New-Object byte[] 48
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    $token = [Convert]::ToBase64String($bytes)

    $envContent = Get-Content $EnvFile -Raw
    $envContent = $envContent -replace 'LOCAL_AUTH_TOKEN=.*', "LOCAL_AUTH_TOKEN=$token"
    Set-Content $EnvFile -Value $envContent -NoNewline
    Write-Ok "LOCAL_AUTH_TOKEN 已自动生成 ($($token.Length) 字符)"
    Write-Host "  Token: $token" -ForegroundColor DarkGray
    Write-Host "  (登录时需要输入此 token)" -ForegroundColor Yellow
}

# ============================================================
# 5. 验证 .env 关键配置
# ============================================================
Write-Step "验证 .env 配置"

$envLines = Get-Content $EnvFile | Where-Object { $_ -match '=' -and $_ -notmatch '^\s*#' }
$envDict = @{}
foreach ($line in $envLines) {
    $parts = $line -split '=', 2
    if ($parts.Count -eq 2) { $envDict[$parts[0].Trim()] = $parts[1].Trim() }
}

# 检查 BASE_URL
if ($envDict["BASE_URL"] -and $envDict["BASE_URL"] -match '^https?://') {
    Write-Ok "BASE_URL = $($envDict['BASE_URL'])"
} else {
    Write-Warn "BASE_URL 未设置或格式不正确"
    Log-Issue "BASE_URL 配置" "BASE_URL 必须以 http:// 或 https:// 开头" "确保 .env 中 BASE_URL=http://localhost:8000"
}

# 检查 AUTH_MODE
if ($envDict["AUTH_MODE"] -eq "local") {
    Write-Ok "AUTH_MODE = local"
} else {
    Write-Warn "AUTH_MODE = $($envDict['AUTH_MODE']) (非 local 模式需要额外配置 Clerk)"
}

# 检查 LOCAL_AUTH_TOKEN 长度
$tokenVal = $envDict["LOCAL_AUTH_TOKEN"]
if ($tokenVal -and $tokenVal.Length -ge 50) {
    Write-Ok "LOCAL_AUTH_TOKEN 已设置 ($($tokenVal.Length) 字符)"
} else {
    Write-Err "LOCAL_AUTH_TOKEN 太短 (需要至少 50 字符, 当前 $($tokenVal.Length))"
    Log-Issue "Token 太短" "LOCAL_AUTH_TOKEN 需要至少 50 字符" "运行 setup.ps1 会自动生成"
}

# ============================================================
# 6. 写出问题日志
# ============================================================
Write-Step "生成问题日志"

$issuesMd = @"
# 部署问题记录

> 自动生成于 $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')

## 环境检查结果

| 检查项 | 状态 |
|--------|------|
| 管理员权限 | $(if ($isAdmin) { '✅ 是' } else { '⚠️ 否' }) |
| Docker Desktop | $(if ($dockerInPath -or (Test-Path $dockerExe)) { '✅ 已安装' } else { '❌ 未安装 (已触发安装)' }) |
| 端口 3000 | $(if (Get-NetTCPConnection -LocalPort 3000 -EA SilentlyContinue) { '⚠️ 占用' } else { '✅ 可用' }) |
| 端口 5432 | $(if (Get-NetTCPConnection -LocalPort 5432 -EA SilentlyContinue) { '⚠️ 占用' } else { '✅ 可用' }) |
| 端口 6379 | $(if (Get-NetTCPConnection -LocalPort 6379 -EA SilentlyContinue) { '⚠️ 占用' } else { '✅ 可用' }) |
| 端口 8000 | $(if (Get-NetTCPConnection -LocalPort 8000 -EA SilentlyContinue) { '⚠️ 占用' } else { '✅ 可用' }) |
| .env 文件 | ✅ 已生成 |
| LOCAL_AUTH_TOKEN | $(if ($tokenVal -and $tokenVal.Length -ge 50) { '✅ 已设置' } else { '❌ 不合格' }) |

"@

if ($issues.Count -gt 0) {
    $issuesMd += "## 发现的问题`n`n"
    $i = 1
    foreach ($issue in $issues) {
        $issuesMd += @"
### $i. $($issue.title)

- **详情**: $($issue.detail)
- **解决方案**: $($issue.resolution)

"@
        $i++
    }
} else {
    $issuesMd += "## 未发现问题`n`n所有检查均通过。`n"
}

$issuesMd += @"

## 下一步

1. 如果 Docker Desktop 是首次安装，请 **重启电脑**
2. 重启后打开 Docker Desktop，等待托盘图标显示 "running"
3. 运行 ``.\start.ps1`` 启动全部服务
4. 登录 token 记录在 ``.env`` 文件的 ``LOCAL_AUTH_TOKEN`` 中
"@

Set-Content $IssuesLog -Value $issuesMd -Encoding UTF8
Write-Ok "问题日志已写入: docs\deployment-issues.md"

# ============================================================
# 7. 总结
# ============================================================
Write-Host "`n" -NoNewline
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  环境安装完成" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

if ($issues.Count -gt 0) {
    Write-Host "  发现 $($issues.Count) 个问题 (详见 docs\deployment-issues.md)" -ForegroundColor Yellow
} else {
    Write-Host "  所有检查通过!" -ForegroundColor Green
}

Write-Host ""
Write-Host "  登录 Token (保存好):" -ForegroundColor White
Write-Host "  $tokenVal" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  下一步: .\start.ps1" -ForegroundColor White
Write-Host ""
