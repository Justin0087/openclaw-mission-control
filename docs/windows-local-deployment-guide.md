# Windows Local Deployment Guide

This guide documents the Windows deployment path that was actually validated for this repository.

Scope:
- Windows 10/11 local development machine
- No Docker dependency
- PostgreSQL + portable Redis on the host
- FastAPI backend + Next.js frontend started by `start-local.ps1`

Use this guide when Docker Desktop, WSL2, or BIOS virtualization is unavailable, or when you want the fastest local development loop.

## 1. What this guide deploys

- PostgreSQL on `localhost:5432`
- Redis on `localhost:6379`
- Backend on `http://127.0.0.1:8000`
- Frontend on `http://127.0.0.1:3000`
- Local auth login via `LOCAL_AUTH_TOKEN`

Important:
- Open the app with `127.0.0.1`, not `localhost`.
- The current verified startup entry point is `start-local.ps1`.
- The worker is not started automatically. If you need async jobs, start it manually.

## 2. Required software

Install the following on the target machine:

```powershell
winget install --id Python.Python.3.12 -e
winget install --id OpenJS.NodeJS.LTS -e
winget install --id astral-sh.uv -e
winget install --id PostgreSQL.PostgreSQL.16 -e
```

Notes:
- PostgreSQL setup usually asks for a password during installation. The examples below use `postgres`; if you choose a different password, update `DATABASE_URL` accordingly.
- `uv` may require opening a fresh terminal after installation.
- Redis is expected as a portable binary under `.local\redis`, because Windows MSI installs often require admin privileges.

## 3. Clone the repository

```powershell
git clone <your-repo-url> openclaw-mission-control
cd openclaw-mission-control
```

## 4. Prepare portable Redis

1. Download a Windows portable Redis build from the `tporadowski/redis` releases page.
2. Extract these files into `.local\redis` under the repository root:
   - `redis-server.exe`
   - `redis-cli.exe`

Expected layout:

```text
openclaw-mission-control
  .local
    redis
      redis-server.exe
      redis-cli.exe
```

## 5. Create the PostgreSQL database

Open PowerShell and run:

```powershell
$env:PGPASSWORD = "postgres"
& "C:\Program Files\PostgreSQL\16\bin\psql.exe" -h localhost -U postgres -c "CREATE DATABASE mission_control;"
```

If the database already exists, PostgreSQL will report it and you can continue.

## 6. Generate a local auth token

Generate a token with at least 50 characters:

```powershell
$bytes = New-Object byte[] 48
[System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
[Convert]::ToBase64String($bytes)
```

Save the output. You will put it into `backend/.env` as `LOCAL_AUTH_TOKEN`.

## 7. Create `backend/.env`

Create `backend/.env` with values like these:

```dotenv
ENVIRONMENT=dev
LOG_LEVEL=INFO
LOG_FORMAT=text
LOG_USE_UTC=false
REQUEST_LOG_SLOW_MS=1000
REQUEST_LOG_INCLUDE_HEALTH=false
DATABASE_URL=postgresql+psycopg://postgres:postgres@localhost:5432/mission_control
CORS_ORIGINS=http://127.0.0.1:3000,http://localhost:3000
BASE_URL=http://127.0.0.1:8000
AUTH_MODE=local
LOCAL_AUTH_TOKEN=replace-with-your-generated-token
DB_AUTO_MIGRATE=true
RQ_REDIS_URL=redis://localhost:6379/0
RQ_QUEUE_NAME=default
RQ_DISPATCH_THROTTLE_SECONDS=15.0
RQ_DISPATCH_MAX_RETRIES=3
```

If your PostgreSQL password is not `postgres`, update `DATABASE_URL`.

## 8. Create `frontend/.env`

Create `frontend/.env` with:

```dotenv
NEXT_PUBLIC_API_URL=auto
NEXT_PUBLIC_AUTH_MODE=local
```

Why `auto`:
- It lets the frontend resolve the backend host from the current browser host.
- If you open the app with `127.0.0.1`, it will talk to `127.0.0.1:8000`.

## 9. Install dependencies

Backend:

```powershell
cd backend
uv sync --extra dev
uv run alembic upgrade head
cd ..
```

Frontend:

```powershell
cd frontend
$env:CYPRESS_INSTALL_BINARY = "0"
$env:NODE_TLS_REJECT_UNAUTHORIZED = "0"
npm install
cd ..
```

The two environment variables above are included because they solved real installs behind corporate TLS interception.

## 10. Start the stack

From the repository root:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\start-local.ps1
```

Expected URLs:

```text
Frontend: http://127.0.0.1:3000
Backend:  http://127.0.0.1:8000
Docs:     http://127.0.0.1:8000/docs
```

Login:
- Open `http://127.0.0.1:3000`
- Paste the exact `LOCAL_AUTH_TOKEN` from `backend/.env`

## 11. Stop or inspect the stack

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\start-local.ps1 -Down
powershell -NoProfile -ExecutionPolicy Bypass -File .\start-local.ps1 -Status
```

If PowerShell 7 is installed, `pwsh` works as well. On the current validated machine, two optional Desktop wrappers were created that call the same commands:
- `Mission-Control-Start.cmd`
- `Mission-Control-Stop.cmd`

## 12. Optional worker

If you need async jobs, open another terminal:

```powershell
cd backend
uv run python ..\scripts\rq worker
```

## 13. Validation checklist

Run these checks after startup:

```powershell
$env:NO_PROXY = "localhost,127.0.0.1"
Invoke-WebRequest -Uri "http://127.0.0.1:8000/healthz" -UseBasicParsing -NoProxy
Invoke-WebRequest -Uri "http://127.0.0.1:3000" -UseBasicParsing -NoProxy
& ".\.local\redis\redis-cli.exe" ping
```

Expected results:
- Backend returns `200` with `{"ok":true}`
- Frontend returns `200`
- Redis returns `PONG`

## 14. Common issues

### Docker does not work on the machine

Use this guide. It does not require Docker, WSL2, or BIOS virtualization.

### `uv` is installed but not found

Open a new terminal. If needed, the script also tries to use the WinGet install path.

### `npm install` fails with certificate errors

Use:

```powershell
$env:CYPRESS_INSTALL_BINARY = "0"
$env:NODE_TLS_REJECT_UNAUTHORIZED = "0"
npm install
```

### The browser cannot validate the token

- Open `http://127.0.0.1:3000`, not `http://localhost:3000`
- Keep `frontend/.env` as `NEXT_PUBLIC_API_URL=auto`
- Keep `backend/.env` with `CORS_ORIGINS=http://127.0.0.1:3000,http://localhost:3000`

### `start-local.ps1` says Redis is missing

Make sure these files exist:

```text
.local\redis\redis-server.exe
.local\redis\redis-cli.exe
```

## 15. Recommended handoff notes for another machine

When handing this repo to another Windows developer, make sure they know:
- This repo is currently verified in Windows hybrid mode, not Docker mode.
- The browser entry point is `http://127.0.0.1:3000`.
- The fastest supported startup path is `start-local.ps1`.
- Redis must exist under `.local\redis` unless they adapt the script.
- If PostgreSQL uses a different password, they must change `backend/.env`.