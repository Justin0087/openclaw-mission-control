---
applyTo: "backend/**"
description: "Use when editing backend Python code: models, routes, schemas, services, tests, or migrations."
---
# Backend Instructions

## Models
- Inherit from `QueryModel` ([app/models/base.py](../../backend/app/models/base.py)) or `TenantScoped` ([app/models/tenancy.py](../../backend/app/models/tenancy.py)) for org-scoped data.
- Use `sa_column=Column(JSON)` for dict fields and `sa_column=Column(Text)` for unbounded strings.
- Register every new model by importing it in [app/models/__init__.py](../../backend/app/models/__init__.py) so Alembic autogenerate discovers it.

## Routes
- Follow [app/api/tags.py](../../backend/app/api/tags.py) for simple CRUD; follow [app/api/boards.py](../../backend/app/api/boards.py) for complex multi-dep routes.
- Use module-level dependency constants from [app/api/deps.py](../../backend/app/api/deps.py) (`SESSION_DEP`, `ORG_MEMBER_DEP`, etc.).
- Return `DefaultLimitOffsetPage[SchemaType]` for list endpoints.
- Use `status.HTTP_404_NOT_FOUND` / `HTTP_409_CONFLICT` with structured `detail` dicts.

## Schemas
- Pydantic V2. Use `field_validator(mode="before")` for input normalization.
- Reuse `NonEmptyStr` from [app/schemas/common.py](../../backend/app/schemas/common.py).

## Services
- Keep business logic in `app/services/`, not in route handlers.
- Raise `HTTPException` with a `detail` dict containing a `message` key and relevant IDs.

## Tests
- conftest.py sets `AUTH_MODE=local`, `LOCAL_AUTH_TOKEN`, and `BASE_URL` **before** any app imports.
- Use `@dataclass`-based fakes (`_FakeSession`, `_FakeExecResult`) to mock DB session; keep fakes minimal.
- Decorate async tests with `@pytest.mark.asyncio`.
- Run with `make backend-test`; scoped coverage gate with `make backend-coverage`.

## Migrations
- One migration per PR. CI rejects multiple heads or multiple new files in `migrations/versions/`.
- Run `make backend-migration-check` to verify migration integrity before pushing.
- `DB_AUTO_MIGRATE=true` runs `alembic upgrade head` on startup; `false` falls back to `create_all()`.
