---
description: "Scaffold a full backend CRUD resource: model, schema, route, service, and test file."
agent: "agent"
argument-hint: "Resource name, e.g. Priority"
---
# New CRUD Resource

Create a complete backend CRUD resource named **$ARGUMENTS** following the project patterns.

## Files to create

1. **Model** – `backend/app/models/<name>.py`
   - Inherit from `TenantScoped` (org-scoped) or `QueryModel`.
   - Add `objects: ClassVar[ManagerDescriptor[Self]]` descriptor.
   - Use `Field(default_factory=utcnow)` for timestamps via `from app.core.time import utcnow`.
   - Register the import in [backend/app/models/__init__.py](backend/app/models/__init__.py).

2. **Schema** – `backend/app/schemas/<name>.py`
   - Create/Update schemas with Pydantic V2.
   - Reuse `NonEmptyStr` from [backend/app/schemas/common.py](backend/app/schemas/common.py).
   - Use `field_validator(mode="before")` for input normalization.

3. **Service** (if needed) – `backend/app/services/<name>.py`
   - Keep business logic here, not in route handlers.
   - Raise `HTTPException` with structured `detail` dicts.

4. **Route** – `backend/app/api/<name>.py`
   - Follow the pattern in [backend/app/api/tags.py](backend/app/api/tags.py).
   - Use `Depends()` for auth/session from [backend/app/api/deps.py](backend/app/api/deps.py).
   - Return `DefaultLimitOffsetPage[SchemaType]` for list endpoints.
   - Wire the router in [backend/app/api/__init__.py](backend/app/api/__init__.py) or the main router file.

5. **Test** – `backend/tests/test_<name>_api.py`
   - Use `@dataclass`-based fakes for DB session mocking.
   - Decorate async tests with `@pytest.mark.asyncio`.

## After scaffolding

- Run `make backend-test` to verify.
- Run `make backend-migration-check` if a new table was added.
- Remind me to run `make api-gen` once the backend is running to regenerate the frontend client.
