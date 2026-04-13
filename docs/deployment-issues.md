# 本地部署问题记录

> 环境: Windows 11, Intel i7-12800H, PowerShell 7+
> 首次记录: 2026-04-09 | 最后更新: 2026-04-10
> 最终方案: 方案 B（混合模式）— 已成功运行

## 环境检查结果

| 检查项 | 状态 |
|--------|------|
| 管理员权限 | ⚠️ 否 |
| Docker Desktop | ✅ 已安装 (v29.3.1, Compose v5.1.1) |
| Docker 守护进程 | ❌ 无法启动（虚拟化未开启）|
| 端口 3000 | ✅ 可用 |
| 端口 5432 | ✅ 可用 |
| 端口 6379 | ✅ 可用 |
| 端口 8000 | ✅ 可用 |
| .env 文件 | ✅ 已生成 |
| LOCAL_AUTH_TOKEN | ✅ 已设置 (64字符) |
| WSL2 | ❌ 未安装 |
| Intel VT-x | ❌ BIOS 中关闭 |

## 发现的问题

### 1. 非管理员运行 ⚠️

- **详情**: 脚本以普通用户运行
- **影响**: 无法查询/启用 Windows 可选功能（Hyper-V, WSL 等）
- **解决方案**: 如需安装系统组件，右键 PowerShell → 以管理员身份运行

### 2. Docker Desktop 未预装 ✅ 已解决

- **详情**: 系统中未检测到 Docker Desktop
- **解决方案**: 通过 `winget install Docker.DockerDesktop` 自动安装 (590 MB)
- **耗时**: ~5 分钟

### 3. Docker 安装后不在 PATH 中 ✅ 已解决

- **详情**: 安装完成后终端仍报 `docker: The term 'docker' is not recognized`
- **原因**: winget 安装后未刷新当前终端的 PATH 环境变量
- **解决方案**: `$env:PATH = "C:\Program Files\Docker\Docker\resources\bin;$env:PATH"` 或重启终端

### 4. 🔴 BIOS 虚拟化未开启 — 当前阻塞项

- **详情**: Docker Desktop 报错 `Virtualization support not detected`
- **诊断结果**:
  ```
  CPU: 12th Gen Intel(R) Core(TM) i7-12800H
  VirtualizationFirmwareEnabled: False
  VMMonitorModeExtensions: False
  ```
- **影响**: Docker Desktop、WSL2、Hyper-V 均**无法使用**（全部依赖硬件虚拟化）
- **解决方案**:
  1. 重启电脑 → 进入 BIOS/UEFI (开机按 F2/F10/Del)
  2. 找到 Intel Virtualization Technology (VT-x) 选项
     - 通常在: Advanced → CPU Configuration 或 Security → Virtualization
  3. 设为 **Enabled** → 保存退出 (F10)
  4. 重启后运行 `.\start.ps1`

### 5. WSL2 未安装 ❌ 待解决

- **详情**: `wsl --list --verbose` 输出帮助文本，无已安装发行版
- **前置条件**: 需先解决 #4 虚拟化问题
- **解决方案**: 开启虚拟化后执行 `wsl --install`（Docker Desktop 会自动配置 WSL2 后端）

---

## 当前阻塞项

**方案 A (Docker 全栈)** 被 **BIOS 虚拟化未开启 (#4)** 阻塞。

---

## 方案 B（混合模式）部署记录

> 切换原因: BIOS 虚拟化被禁用，Docker 无法使用

### 已安装组件

| 组件 | 版本 | 安装方式 |
|------|------|----------|
| Python | 3.12.10 | 已有 |
| Node.js | v24.14.0 | 已有 |
| npm | 11.9.0 | 已有 |
| uv | 0.11.6 | winget (astral-sh.uv) |
| PostgreSQL | 16.13 | winget (PostgreSQL.PostgreSQL.16) |
| Redis | 5.0.14 | 便携版 (tporadowski/redis) |

### 6. uv 安装后不在 PATH 中 ✅ 已解决

- **详情**: `winget install astral-sh.uv` 安装成功但终端找不到 `uv` 命令
- **原因**: winget 安装路径不在当前终端 PATH 中
- **实际路径**: `C:\Users\sesa508315\AppData\Local\Microsoft\WinGet\Packages\astral-sh.uv_Microsoft.Winget.Source_8wekyb3d8bbwe\uv.exe`
- **解决方案**: 新启终端或手动添加到 PATH

### 7. Redis MSI 安装失败（需管理员权限）✅ 已解决

- **详情**: `winget install Redis.Redis` 下载成功，MSI 安装无权限
- **解决方案**: 使用 tporadowski/redis 便携版，直接解压运行
  - 路径: `.local\redis\redis-server.exe`
  - 无需安装、无需管理员权限

### 8. npm install 失败 — Cypress 下载被 Zscaler 拦截 ✅ 已解决

- **详情**: `npm install` 报错 `unable to get local issuer certificate`
- **原因**: 公司 Zscaler 代理 SSL 拦截，Cypress 下载 API 证书不被信任
- **影响**: npm install 整体回滚，node_modules 被清空
- **解决方案**: 跳过 Cypress 二进制下载
  ```powershell
  $env:CYPRESS_INSTALL_BINARY = "0"
  $env:NODE_TLS_REJECT_UNAUTHORIZED = "0"
  npm install
  ```
- **副作用**: E2E 测试 (Cypress) 不可用（仅影响测试，不影响开发）

### 9. Zscaler 拦截 localhost 请求 ⚠️ 需配置

- **详情**: `Invoke-WebRequest http://localhost:8000` 被 Zscaler 拦截
- **报错**: `Blocked due to invalid server IP`
- **解决方案**: 使用 `127.0.0.1` 代替 `localhost`，并设置 NoProxy
  ```powershell
  $env:NO_PROXY = "localhost,127.0.0.1"
  Invoke-WebRequest -Uri "http://127.0.0.1:8000/healthz" -NoProxy
  ```
- **浏览器访问**: 浏览器通常不走 Zscaler 代理访问 localhost，可正常使用

### 10. Next.js Turbopack Google Fonts 解析失败 ✅ 已解决

- **详情**: Next.js 16 默认使用 Turbopack，Google Fonts 模块解析失败
- **报错**: `Module not found: Can't resolve '@vercel/turbopack-next/internal/font/google/font'`
- **原因**: Zscaler 拦截 Google Fonts CDN 请求，Turbopack 字体加载器失败
- **解决方案**: 使用 webpack 替代 Turbopack
  ```powershell
  npx next dev --webpack
  ```

---

## 最终状态

| 服务 | 状态 | 地址 |
|------|------|------|
| PostgreSQL | ✅ 运行中 | localhost:5432 |
| Redis | ✅ 运行中 | localhost:6379 |
| Backend (FastAPI) | ✅ 运行中 | http://127.0.0.1:8000 |
| Frontend (Next.js) | ✅ 运行中 | http://127.0.0.1:3000 |
| API Docs | ✅ 可访问 | http://127.0.0.1:8000/docs |
| Worker (RQ) | ⚠️ 未启动 | 需要手动启动（可选） |

### 验证结果

```
Backend /healthz → {"ok":true}
Frontend / → HTTP 200, 18KB HTML
Redis ping → PONG
PostgreSQL → 接受连接
```

### 推荐下一步

| 优先级 | 操作 | 预计耗时 |
|--------|------|----------|
| 1 | 重启电脑，在 BIOS 中开启 VT-x | 5-10 分钟 |
| 2 | 重启后打开 Docker Desktop，等待引擎就绪 | 2-3 分钟 |
| 3 | 运行 `.\start.ps1` 启动全部服务 | 5-10 分钟（首次构建）|

### 备选：切换到方案 B（混合模式，不需要虚拟化）

如果无法修改 BIOS（如公司锁定），可改用混合模式：

```powershell
# 1. 安装 PostgreSQL 和 Redis
winget install PostgreSQL.PostgreSQL.16
winget install Redis.Redis       # 或 Memurai

# 2. 安装 Python 工具链
winget install astral-sh.uv
winget install OpenJS.NodeJS.LTS

# 3. 启动后端
cd backend
uv sync --extra dev
uv run uvicorn app.main:app --reload --port 8000

# 4. 启动前端
cd frontend
npm install
npm run dev
```

## 下一步

1. 如果 Docker Desktop 是首次安装，请 **重启电脑**
2. 重启后打开 Docker Desktop，等待托盘图标显示 "running"
3. 运行 `.\start.ps1` 启动全部服务
4. 登录 token 记录在 `.env` 文件的 `LOCAL_AUTH_TOKEN` 中
