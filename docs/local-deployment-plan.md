# 本地部署计划（Windows）

本文档描述如何在 Windows 本机搭建 OpenClaw Mission Control 的完整开发、调试和测试环境。

## 目录

1. [前置条件](#1-前置条件)
2. [方案选择](#2-方案选择)
3. [方案 A：Docker 全栈部署（推荐首次验证）](#3-方案-a-docker-全栈部署)
4. [方案 B：混合开发模式（推荐日常开发）](#4-方案-b-混合开发模式)
5. [验证与测试](#5-验证与测试)
6. [常见问题排查](#6-常见问题排查)
7. [命令速查表](#7-命令速查表)

---

## 1. 前置条件

### 必须安装

| 工具 | 最低版本 | 用途 | 安装方式 |
|------|---------|------|---------|
| Docker Desktop | Compose v2.22+ | 运行数据库/Redis/全栈 | https://www.docker.com/products/docker-desktop |
| Git | 2.x | 版本控制 | https://git-scm.com |

### 日常开发额外需要（方案 B）

| 工具 | 最低版本 | 用途 | 安装方式 |
|------|---------|------|---------|
| Python | 3.12+ | 后端运行时 | https://www.python.org |
| uv | latest | Python 依赖管理（**不要用 pip**） | `pip install uv` 或 `winget install astral-sh.uv` |
| Node.js | 22+ | 前端运行时 | https://nodejs.org |
| npm | 随 Node 附带 | 前端依赖（**不要用 yarn/pnpm**） | 随 Node 安装 |
| Make | GNU Make | 执行统一构建命令 | `winget install GnuWin32.Make` 或用 Git Bash 自带 |

### 注意事项

- 本项目官方支持 Linux/macOS，`install.sh` 不支持 Windows，**不要运行它**。
- Windows 上推荐使用 **Git Bash** 或 **WSL2** 来执行 Make 命令。PowerShell 下部分 Makefile target 可能不兼容。
- 如果端口 5432、6379、8000、3000 被占用，需要先释放或在 `.env` 中修改端口号。

---

## 2. 方案选择

| | 方案 A：Docker 全栈 | 方案 B：混合开发 |
|---|---|---|
| **适合场景** | 首次验证、演示、集成测试 | 日常开发、调试、快速迭代 |
| **启动速度** | 慢（需要构建镜像） | 快（热重载） |
| **调试能力** | 有限（需要进入容器） | 完整（本机进程，断点调试） |
| **依赖安装** | 只需 Docker | 需要 Python + Node 等 |

**建议**：先用方案 A 确认环境可用，再切到方案 B 进行日常开发。

---

## 3. 方案 A：Docker 全栈部署

### 步骤 1：配置环境变量

```bash
cd openclaw-mission-control
cp .env.example .env
```

编辑 `.env`，**必须修改**以下三项：

```dotenv
# 生成一个至少 50 字符的随机 token（不能是 change-me 等占位符）
LOCAL_AUTH_TOKEN=my-secure-local-auth-token-that-is-at-least-fifty-characters-long-1234567890

# 保持默认值即可
BASE_URL=http://localhost:8000
NEXT_PUBLIC_API_URL=auto
```

其余变量保持默认值（`AUTH_MODE=local`、`DB_AUTO_MIGRATE=true` 等）。

### 步骤 2：启动全部服务

```bash
docker compose -f compose.yml --env-file .env up -d --build
```

首次构建需要几分钟。启动后运行 5 个服务：

| 服务 | 端口 | 说明 |
|------|------|------|
| db (Postgres) | 5432 | 数据库 |
| redis | 6379 | 队列和缓存 |
| backend | 8000 | FastAPI 后端 |
| frontend | 3000 | Next.js 前端 |
| webhook-worker | 无 | 异步任务处理 |

### 步骤 3：验证

```bash
# 后端健康检查
curl -f http://localhost:8000/healthz

# 浏览器打开前端
# http://localhost:3000
```

### 步骤 4：停止

```bash
# 停止服务（保留数据）
docker compose -f compose.yml --env-file .env down

# ⚠️ 停止并删除数据（危险操作）
# docker compose -f compose.yml --env-file .env down -v
```

### 可选：Watch 模式（前端热重建）

需要 Docker Compose 2.22.0+：

```bash
docker compose -f compose.yml --env-file .env up --build --watch
```

---

## 4. 方案 B：混合开发模式

Docker 只运行基础设施（Postgres + Redis），后端和前端在宿主机运行，支持热重载和断点调试。

### 步骤 1：启动基础设施

```bash
cp .env.example .env
# 编辑 .env，设置 LOCAL_AUTH_TOKEN（同方案 A）

docker compose -f compose.yml --env-file .env up -d db redis
```

### 步骤 2：配置并启动后端

```bash
cd backend
cp .env.example .env
```

编辑 `backend/.env`：

```dotenv
DATABASE_URL=postgresql+psycopg://postgres:postgres@localhost:5432/mission_control
BASE_URL=http://localhost:8000
AUTH_MODE=local
LOCAL_AUTH_TOKEN=my-secure-local-auth-token-that-is-at-least-fifty-characters-long-1234567890
DB_AUTO_MIGRATE=true
RQ_REDIS_URL=redis://localhost:6379/0
```

安装依赖并启动：

```bash
uv sync --extra dev
uv run uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

验证：`curl -f http://localhost:8000/healthz`

### 步骤 3：启动 Worker（单独终端）

```bash
cd backend
uv run python ../scripts/rq worker
```

> **重要**：不启动 worker 会导致 webhook 和异步任务无法处理，部分功能不完整。

### 步骤 4：配置并启动前端

```bash
cd frontend
cp .env.example .env.local
```

编辑 `frontend/.env.local`：

```dotenv
NEXT_PUBLIC_API_URL=http://localhost:8000
NEXT_PUBLIC_AUTH_MODE=local
```

安装依赖并启动：

```bash
npm install
npm run dev
```

打开 http://localhost:3000。

### 步骤 5（可选）：VS Code 调试配置

后端调试 — 在 `.vscode/launch.json` 中添加：

```json
{
  "name": "Backend (uvicorn)",
  "type": "debugpy",
  "request": "launch",
  "module": "uvicorn",
  "args": ["app.main:app", "--reload", "--port", "8000"],
  "cwd": "${workspaceFolder}/backend",
  "envFile": "${workspaceFolder}/backend/.env",
  "console": "integratedTerminal"
}
```

前端调试 — 使用 VS Code 内置的 JavaScript Debug Terminal 启动 `npm run dev`。

---

## 5. 验证与测试

### 功能验证清单

| 检查项 | 命令 / 操作 | 预期结果 |
|--------|------------|---------|
| 后端健康 | `curl http://localhost:8000/healthz` | `{"status":"ok"}` |
| 后端就绪 | `curl http://localhost:8000/readyz` | 200 OK |
| 前端页面 | 浏览器 http://localhost:3000 | 登录/首页正常显示 |
| 认证流程 | 在前端输入 LOCAL_AUTH_TOKEN 登录 | 登录成功，跳转到 boards 页面 |
| 数据库连接 | 后端启动日志无报错 | 无连接错误 |
| Worker 运行 | Worker 终端显示轮询日志 | 无异常退出 |

### 运行测试

```bash
# 全量 CI 检查（lint + typecheck + 测试 + 构建）
make check

# 仅后端测试
make backend-test

# 后端覆盖率（当前仅覆盖 error_handling 和 mentions 模块）
make backend-coverage

# 仅前端测试
make frontend-test

# 前端 E2E（需要全栈运行中）
cd frontend && npm run e2e
```

### 重新生成前端 API 客户端

当后端 API 有变更时（**后端必须在 127.0.0.1:8000 运行**）：

```bash
make api-gen
```

---

## 6. 常见问题排查

### 后端启动失败

| 错误信息 | 原因 | 解决方案 |
|---------|------|---------|
| `LOCAL_AUTH_TOKEN` 相关报错 | Token 太短或是占位符 | 设为至少 50 字符的非占位值 |
| `BASE_URL` 校验失败 | 不是以 `http://` 或 `https://` 开头的绝对 URL | 设为 `http://localhost:8000` |
| 数据库连接拒绝 | Postgres 未运行或端口不匹配 | 确认 `docker compose up -d db` 已运行 |

### 前端能打开但 API 请求失败

- 检查 `NEXT_PUBLIC_API_URL` 是否是**浏览器**能访问的地址（不能用 Docker 内部地址）
- 检查后端 `CORS_ORIGINS` 是否包含前端地址（默认 `http://localhost:3000`）
- 确认后端进程正在运行

### Make 命令在 PowerShell 下报错

Makefile 使用 Bash 语法。解决方案：
- 使用 Git Bash 执行 `make` 命令
- 或安装 WSL2，在 WSL 终端中运行
- 或直接执行 Makefile 中对应的原始命令（查看 `make help` 输出）

### 端口冲突

编辑 `.env` 修改对应端口：

```dotenv
FRONTEND_PORT=3001
BACKEND_PORT=8001
POSTGRES_PORT=5433
```

---

## 7. 命令速查表

```bash
# === 环境管理 ===
make setup                  # 安装所有依赖
make help                   # 查看所有可用 Make 目标

# === Docker 全栈 ===
docker compose -f compose.yml --env-file .env up -d --build     # 启动
docker compose -f compose.yml --env-file .env down               # 停止
docker compose -f compose.yml --env-file .env logs -f backend    # 查看后端日志

# === 混合模式 ===
docker compose -f compose.yml --env-file .env up -d db redis    # 仅启中间件
cd backend && uv run uvicorn app.main:app --reload --port 8000  # 后端
cd backend && uv run python ../scripts/rq worker                # Worker
cd frontend && npm run dev                                       # 前端

# === 质量检查 ===
make check                  # 完整 CI 检查
make backend-test           # 后端测试
make frontend-test          # 前端测试
make lint                   # 全量 lint
make typecheck              # 全量类型检查

# === API 客户端 ===
make api-gen                # 重新生成（需要后端在 127.0.0.1:8000）
```
