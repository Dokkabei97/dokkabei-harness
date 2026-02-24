---
name: python-uv-monorepo
target-stack: Python uv Workspace (FastAPI, Celery, SQLAlchemy)
placeholders: ["{project_name}", "{pkg_api}", "{pkg_worker}", "{pkg_domain}", "{pkg_infra}", "{pkg_shared}"]
---

# Python uv Monorepo -- Inverted Index Template

## Part 1: PROJECT_ROOT/CLAUDE.md

Copy this section into your project root's `CLAUDE.md` (not `~/.claude/CLAUDE.md`). Details live in `.claude/rules/`.

```markdown
## Package Overview

| Package      | Path                    | Purpose                        |
|--------------|-------------------------|--------------------------------|
| {pkg_api}    | packages/{pkg_api}/     | FastAPI HTTP service           |
| {pkg_worker} | packages/{pkg_worker}/  | Celery async task workers      |
| {pkg_domain} | packages/{pkg_domain}/  | Domain models & business logic |
| {pkg_infra}  | packages/{pkg_infra}/   | DB, cache, external adapters   |
| {pkg_shared} | packages/{pkg_shared}/  | Cross-cutting utilities        |

## Name Disambiguation

| Name    | Package      | File / Path     | Meaning                        |
|---------|--------------|-----------------|--------------------------------|
| models  | {pkg_domain} | models/         | Domain dataclasses / entities  |
| models  | {pkg_infra}  | models/         | SQLAlchemy ORM models          |
| schemas | {pkg_api}    | schemas/        | Pydantic request/response DTOs |
| config  | {pkg_shared} | config.py       | Global Settings (BaseSettings) |
| config  | {pkg_worker} | celeryconfig.py | Celery-specific configuration  |

## Entry Points

| Command               | Target                                   |
|-----------------------|------------------------------------------|
| `uv run uvicorn ...`  | packages/{pkg_api}/src/{pkg_api}/app.py  |
| `uv run celery ...`   | packages/{pkg_worker}/src/{pkg_worker}/celery_app.py |

## Test Hierarchy

conftest.py fixture chain (broadest → narrowest):
- tests/conftest.py — workspace-wide (DB engine, test client)
- packages/{pkg_api}/tests/conftest.py — API (async client, auth mocks)
- packages/{pkg_worker}/tests/conftest.py — Celery (celery_app, eager mode)
- packages/{pkg_infra}/tests/conftest.py — DB (session, factories)

Run all: `uv run pytest` | One package: `uv run pytest packages/{pkg_api}`

## Generated Files (DO NOT MODIFY)

- packages/{pkg_infra}/alembic/versions/
- **/__pycache__/
- **/*.egg-info/

## Rules

- {pkg_domain} MUST NOT import from {pkg_infra} or {pkg_api}
- All async endpoints must use dependency injection via deps.py
- Alembic migrations must be reviewed before merge
- See `.claude/rules/` for technology-specific conventions
```

## Part 2: PROJECT_ROOT/.claude/rules/ Files

Create each file below in your project's `.claude/rules/` directory (not `~/.claude/rules/`).

### File: fastapi.md

```markdown
---
description: "FastAPI routes, schemas, dependencies, and middleware"
paths: ["**/routers/**", "**/schemas/**", "**/middleware/**", "**/deps.py"]
---

## FastAPI

### Location Index
- app-factory: packages/{pkg_api}/src/{pkg_api}/app.py
- routers: packages/{pkg_api}/src/{pkg_api}/routers/
- dependencies: packages/{pkg_api}/src/{pkg_api}/deps.py
- middleware: packages/{pkg_api}/src/{pkg_api}/middleware/
- exception-handlers: packages/{pkg_api}/src/{pkg_api}/exceptions.py
- schemas: packages/{pkg_api}/src/{pkg_api}/schemas/

### Pydantic Settings
- config: packages/{pkg_shared}/src/{pkg_shared}/config.py
- per-package overrides: packages/{pkg_api}/src/{pkg_api}/settings.py
- .env files at workspace root. Never commit .env; use .env.example.

### __init__.py Re-export Chains
FastAPI sub-packages use `__init__.py` to re-export public symbols:
| Public import                              | Actual definition                              |
|--------------------------------------------|------------------------------------------------|
| {pkg_api}.routers                          | {pkg_api}/routers/__init__.py (collects all)   |
| {pkg_api}.schemas.{resource}               | {pkg_api}/schemas/{resource}.py                |
| {pkg_api}.deps.get_db / get_current_user   | {pkg_api}/deps.py                              |

### Test Fixtures (API)
- packages/{pkg_api}/tests/conftest.py: async test client, auth header factory, mock dependencies
- Override real deps with `app.dependency_overrides[dep] = mock_dep` in fixtures
```

### File: sqlalchemy.md

```markdown
---
description: "SQLAlchemy models, sessions, Alembic migrations, and repositories"
paths: ["**/models/**", "**/db/**", "**/alembic/**", "**/repositories/**"]
---

## SQLAlchemy

### Location Index
- models: packages/{pkg_infra}/src/{pkg_infra}/models/
- session: packages/{pkg_infra}/src/{pkg_infra}/db/session.py
- base: packages/{pkg_infra}/src/{pkg_infra}/db/base.py
- repositories: packages/{pkg_infra}/src/{pkg_infra}/repositories/

### __init__.py Re-export Chains
| Public import                           | Actual definition                                |
|-----------------------------------------|--------------------------------------------------|
| {pkg_infra}.models                      | {pkg_infra}/models/__init__.py (imports all)     |
| {pkg_infra}.db.session.get_session      | {pkg_infra}/db/session.py                        |
| {pkg_infra}.db.base.Base                | {pkg_infra}/db/base.py (declarative base)        |

All models MUST be imported in models/__init__.py for Alembic autogenerate to detect them.

## Alembic

### Location Index
- config: packages/{pkg_infra}/alembic.ini
- env: packages/{pkg_infra}/alembic/env.py
- migrations: packages/{pkg_infra}/alembic/versions/

### Conventions
- Migration naming: `{revision}_{slug}.py`
- Always review auto-generated migrations before committing
- Run: `uv run alembic -c packages/{pkg_infra}/alembic.ini upgrade head`

### Test Fixtures (DB)
- packages/{pkg_infra}/tests/conftest.py: test DB session, transaction rollback per test, model factories
- conftest.py scope chain: session-scoped engine → function-scoped session with rollback
```

### File: celery.md

```markdown
---
description: "Celery tasks, schedules, and worker configuration"
paths: ["**/tasks/**", "**/worker/**", "**/celery_app.py", "**/celeryconfig.py", "**/schedules.py"]
---

## Celery

### Location Index
- app-instance: packages/{pkg_worker}/src/{pkg_worker}/celery_app.py
- tasks: packages/{pkg_worker}/src/{pkg_worker}/tasks/
- schedules: packages/{pkg_worker}/src/{pkg_worker}/schedules.py
- config: packages/{pkg_worker}/src/{pkg_worker}/celeryconfig.py

### Conventions
- Each task file maps to one domain area (e.g., tasks/billing.py, tasks/notifications.py)
- Task names should use explicit `name=` parameter for stable task routing
- Bind tasks with `@app.task(bind=True)` when retry logic is needed

### __init__.py Re-export Chains
| Public import                              | Actual definition                              |
|--------------------------------------------|------------------------------------------------|
| {pkg_worker}.tasks                         | {pkg_worker}/tasks/__init__.py (autodiscover)  |
| {pkg_worker}.celery_app.app                | {pkg_worker}/celery_app.py                     |

### Test Fixtures (Celery)
- packages/{pkg_worker}/tests/conftest.py: celery_app fixture, `task_always_eager=True` for sync execution
- Mock external dependencies (DB, APIs) at the task boundary
```

### File: redis.md

```markdown
---
description: "Redis cache client, configuration, and cache patterns"
paths: ["**/cache/**"]
---

## Redis

### Location Index
- client: packages/{pkg_infra}/src/{pkg_infra}/cache/redis_client.py
- cache-layer: packages/{pkg_infra}/src/{pkg_infra}/cache/

### Conventions
- If using redis-om, model definitions go in cache/ alongside the client
- Key naming: `{project_name}:{resource}:{id}` prefix pattern
- TTL should be configured via Pydantic Settings, not hardcoded
```
