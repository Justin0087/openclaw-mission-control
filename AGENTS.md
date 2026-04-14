# Project Guidelines

## Architecture
- The repo is split into a FastAPI backend in [backend](backend), a Next.js frontend in [frontend](frontend), and shared contributor and operations docs in [docs/README.md](docs/README.md).
- Backend routes live in [backend/app/api](backend/app/api), business logic in [backend/app/services](backend/app/services), schemas in [backend/app/schemas](backend/app/schemas), and models in [backend/app/models](backend/app/models).
- Frontend routes live in [frontend/src/app](frontend/src/app), shared UI in [frontend/src/components](frontend/src/components), and utilities in [frontend/src/lib](frontend/src/lib).
- Treat [frontend/src/api/generated](frontend/src/api/generated) as generated code. Regenerate it with `make api-gen`; do not edit it by hand.
- For broader project context, link out instead of duplicating: [README.md](README.md), [docs/development/README.md](docs/development/README.md), [docs/testing/README.md](docs/testing/README.md), and [docs/architecture/README.md](docs/architecture/README.md).

## Build And Test
- Prefer repo-root Make targets over ad hoc commands: `make setup`, `make check`, `make lint`, `make typecheck`, `make test`, and `make build`.
- Backend Python is managed by **uv** (`uv sync --extra dev`, `uv run pytest`). Frontend uses **npm** (`package-lock.json`). Do not mix in pip, yarn, or pnpm.
- Use `docker compose -f compose.yml --env-file .env up -d --build` for the full stack. For the faster local loop, start only Postgres, then run the backend with `uv run uvicorn app.main:app --reload --port 8000` from [backend](backend) and the frontend with `npm run dev` from [frontend](frontend).
- Use targeted validation when possible: `make backend-test`, `make backend-coverage`, `make frontend-test`, and `make backend-migration-check` when touching Alembic revisions.
- Run `make api-gen` after backend API changes once the backend is reachable on `127.0.0.1:8000`.

## Code Style
- Python follows Black, isort, flake8, and strict mypy with a 100-character line limit. Use `snake_case`.
- TypeScript and React follow ESLint and Prettier. Components use `PascalCase`; variables and functions use `camelCase`.
- Prefix intentionally unused destructured TypeScript variables with `_` to satisfy the lint configuration.

## Backend Patterns
- Models inherit from `QueryModel` (or `TenantScoped` for org-scoped data) and expose an `.objects` descriptor for queries (`Model.objects.all()`, `.filter()`, `.by_id()`). See [backend/app/models/base.py](backend/app/models/base.py) and [backend/app/db/query_manager.py](backend/app/db/query_manager.py).
- Routes use FastAPI `Depends()` for auth, session, and resource resolution. Follow the pattern in [backend/app/api/tags.py](backend/app/api/tags.py) for simple CRUD and [backend/app/api/deps.py](backend/app/api/deps.py) for dependency definitions.
- Schemas use Pydantic V2 with `field_validator(mode="before")` for input normalization. Reuse `NonEmptyStr` from [backend/app/schemas/common.py](backend/app/schemas/common.py).
- All timestamps must use `utcnow` from [backend/app/core/time.py](backend/app/core/time.py). Use `from app.core.logging import get_logger` for logging.
- Pagination uses `fastapi-pagination` with `DefaultLimitOffsetPage[ItemType]` response models.

## Conventions
- Add or update tests when behavior changes. Use [docs/testing/README.md](docs/testing/README.md) for command details and coverage expectations.
- Keep migration history clean and follow [docs/policy/one-migration-per-pr.md](docs/policy/one-migration-per-pr.md) when a change requires Alembic revisions. CI enforces exactly one migration per PR and rejects multiple Alembic heads.
- When adding models, ensure they are importable from `app.models` so Alembic autogenerate discovers them (see [backend/migrations/env.py](backend/migrations/env.py)).
- Prefer existing documentation over restating setup, deployment, or policy details. Start with [docs/development/README.md](docs/development/README.md), [docs/reference](docs/reference), [docs/style-guide.md](docs/style-guide.md), and [CONTRIBUTING.md](CONTRIBUTING.md).
- Never commit secrets. Copy local configuration from the existing `.env.example` files and keep real values out of version control.
