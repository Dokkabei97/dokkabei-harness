# Python uv/pip Monorepo -- Inverted Index Guide

Python monorepos using uv workspaces, FastAPI, Django, Celery, and SQLAlchemy.
Python's naming collisions (models, schemas, config everywhere) make disambiguation critical.

## uv Workspace Structure

```
project-root/
  pyproject.toml              # Root workspace definition
  uv.lock                     # Lockfile
  packages/
    api/                      # FastAPI service
      pyproject.toml
      src/api/
        main.py               # Entry point
        routers/              # Route handlers
        schemas/              # Pydantic request/response models
        dependencies.py       # FastAPI Depends() factories
        middleware/            # CORS, auth, logging middleware
    worker/                   # Celery workers
      pyproject.toml
      src/worker/
        app.py                # Celery app instance
        tasks/                # Task definitions
        schedules.py          # Beat schedule
    shared/                   # Shared domain logic
      pyproject.toml
      src/shared/
        domain/               # Domain models
        services/             # Business logic
        ports/                # Abstract interfaces
    ml/                       # ML pipeline
      pyproject.toml
      src/ml/
        models/               # ML model definitions
        pipelines/            # Training/inference pipelines
        features/             # Feature engineering
    infra/                    # Infrastructure adapters
      pyproject.toml
      src/infra/
        db/                   # SQLAlchemy models and session
        cache/                # Redis adapter
        queue/                # Kafka/SQS adapter
        search/               # Elasticsearch adapter
```

## FastAPI Location Patterns

```markdown
## Tech -> Location Map

### FastAPI
- routers: packages/api/src/api/routers/
- schemas (request/response): packages/api/src/api/schemas/
- dependencies: packages/api/src/api/dependencies.py
- middleware: packages/api/src/api/middleware/
- exception handlers: packages/api/src/api/exceptions.py
- lifespan/startup: packages/api/src/api/main.py

### SQLAlchemy / Database
- ORM models: packages/infra/src/infra/db/models/
- session factory: packages/infra/src/infra/db/session.py
- migrations: packages/infra/src/infra/db/migrations/ (Alembic)
- alembic.ini: packages/infra/alembic.ini
- migration env: packages/infra/src/infra/db/migrations/env.py

### Redis
- adapter: packages/infra/src/infra/cache/
- config: packages/infra/src/infra/cache/config.py

### Celery
- app instance: packages/worker/src/worker/app.py
- tasks: packages/worker/src/worker/tasks/
- schedules: packages/worker/src/worker/schedules.py
- config: packages/worker/src/worker/config.py

### Elasticsearch
- adapter: packages/infra/src/infra/search/
- index definitions: packages/infra/src/infra/search/indices.py
```

## Django App Patterns

For Django projects, the structure differs significantly:

```markdown
## Django Tech -> Location Map

### Django Core
- settings: config/settings/ (base.py, local.py, production.py)
- root urls: config/urls.py
- wsgi/asgi: config/wsgi.py, config/asgi.py

### Per-App Structure (apps/{app_name}/)
- models: apps/{app_name}/models.py (or models/ package)
- views: apps/{app_name}/views.py
- serializers: apps/{app_name}/serializers.py (DRF)
- urls: apps/{app_name}/urls.py
- admin: apps/{app_name}/admin.py
- signals: apps/{app_name}/signals.py
- tasks: apps/{app_name}/tasks.py (Celery)
- managers: apps/{app_name}/managers.py

### Migrations
- per-app: apps/{app_name}/migrations/
```

## Name Disambiguation Table

This is the single most important section for Python projects.
Python reuses generic names across completely different modules.

```markdown
## Name Disambiguation

| Name       | Package   | Path                              | Purpose                    |
|------------|-----------|-----------------------------------|----------------------------|
| models     | infra     | infra/db/models/                  | SQLAlchemy ORM models      |
| models     | shared    | shared/domain/                    | Domain value objects        |
| models     | ml        | ml/models/                        | ML model definitions       |
| schemas    | api       | api/schemas/                      | Pydantic request/response  |
| schemas    | shared    | shared/schemas/                   | Shared validation schemas  |
| config     | api       | api/config.py                     | FastAPI settings           |
| config     | worker    | worker/config.py                  | Celery settings            |
| config     | infra     | infra/db/config.py                | DB connection settings     |
| tasks      | worker    | worker/tasks/                     | Celery task definitions    |
| tasks      | ml        | ml/pipelines/tasks/               | ML pipeline steps          |
| utils      | shared    | shared/utils/                     | Shared utilities           |
| utils      | api       | api/utils/                        | API-specific helpers       |
```

## conftest.py Hierarchy

pytest conftest files form a hierarchy. Document fixture locations:

```markdown
## Test Fixtures (conftest.py)

| Path                                  | Scope   | Key Fixtures                     |
|---------------------------------------|---------|----------------------------------|
| conftest.py (root)                    | session | db_engine, event_loop            |
| packages/api/tests/conftest.py        | module  | test_client, auth_headers        |
| packages/api/tests/routers/conftest.py| func    | sample_order, mock_service       |
| packages/worker/tests/conftest.py     | module  | celery_app, mock_broker          |
| packages/infra/tests/conftest.py      | module  | db_session, redis_client         |
```

## __init__.py Re-export Chains

Python packages often re-export from `__init__.py`. Document the chains
so agents know where the real implementation lives:

```markdown
## Re-export Chains (follow imports to source)

| Import Path                | Re-exported From            | Real Location              |
|----------------------------|-----------------------------|----------------------------|
| shared.domain.Order        | shared/domain/__init__.py   | shared/domain/order.py     |
| infra.db.models.UserModel  | infra/db/models/__init__.py | infra/db/models/user.py    |
| api.schemas.OrderCreate    | api/schemas/__init__.py     | api/schemas/order.py       |
```

## Auto-Extracting Package List from uv

```bash
# List all workspace packages
grep -A1 'members' pyproject.toml | grep '"' | tr -d ' ",'

# Or parse uv workspace
uv workspace list 2>/dev/null || \
  find packages -name pyproject.toml -maxdepth 2 | sort
```

Script to generate the package structure:

```bash
#!/bin/bash
echo "## Package Structure"
for pkg_toml in packages/*/pyproject.toml; do
  pkg_dir=$(dirname "$pkg_toml")
  pkg_name=$(basename "$pkg_dir")
  echo "### $pkg_name"
  src_dir="$pkg_dir/src/$pkg_name"
  if [ -d "$src_dir" ]; then
    find "$src_dir" -type d -maxdepth 2 | sed "s|$pkg_dir/||" | sort
  fi
  echo ""
done
```

## Alembic Migration Pitfall

Alembic migrations and SQLAlchemy models live in different packages.
Always document both:

```markdown
## Database Model <-> Migration Mapping
- Models: packages/infra/src/infra/db/models/
- Migrations: packages/infra/src/infra/db/migrations/versions/
- Alembic env: packages/infra/src/infra/db/migrations/env.py
- To create migration: cd packages/infra && alembic revision --autogenerate -m "description"
```

## Complete 3-Tier Example

### Part 1: Root CLAUDE.md

```markdown
# Python UV Monorepo

5 packages — api, worker, shared, ml, infra

## Package Overview

| Package | Purpose              | Entry Point                      |
|---------|----------------------|----------------------------------|
| api     | FastAPI HTTP service | packages/api/src/api/main.py     |
| worker  | Celery background    | packages/worker/src/worker/app.py|
| shared  | Domain logic         | (library)                        |
| ml      | ML pipelines         | packages/ml/src/ml/pipelines/train.py |
| infra   | DB, cache, queue     | (library)                        |

## Name Disambiguation

| Name     | Package | Path                    | Purpose                   |
|----------|---------|-------------------------|---------------------------|
| models   | infra   | infra/db/models/        | SQLAlchemy ORM models     |
| models   | shared  | shared/domain/          | Domain value objects      |
| models   | ml      | ml/models/              | ML model definitions      |
| schemas  | api     | api/schemas/            | Pydantic request/response |
| schemas  | shared  | shared/schemas/         | Shared validation schemas |
| config   | api     | api/config.py           | FastAPI settings          |
| config   | worker  | worker/config.py        | Celery settings           |
| config   | infra   | infra/db/config.py      | DB connection settings    |

## Entry Points

- API server: packages/api/src/api/main.py
- Celery worker: packages/worker/src/worker/app.py
- ML training: packages/ml/src/ml/pipelines/train.py

## Generated Files (DO NOT MODIFY)

- packages/infra/src/infra/db/migrations/versions/ (Alembic auto-generated)

## Rules

Tech-specific patterns and conventions live in .claude/rules/.
```

### Part 2: `.claude/rules/sqlalchemy.md`

```markdown
---
paths:
  - packages/infra/src/infra/db/**
  - packages/infra/src/infra/db/migrations/**
---

# SQLAlchemy / Database

## Location Map

- ORM models: packages/infra/src/infra/db/models/
- session factory: packages/infra/src/infra/db/session.py
- migrations: packages/infra/src/infra/db/migrations/ (Alembic)
- alembic.ini: packages/infra/alembic.ini
- migration env: packages/infra/src/infra/db/migrations/env.py

## Re-export Chain

| Import Path               | Real Location           |
|---------------------------|-------------------------|
| infra.db.models.UserModel | infra/db/models/user.py |
| infra.db.models.Order     | infra/db/models/order.py|

## Migration Workflow

cd packages/infra && alembic revision --autogenerate -m "description"

## Conventions

- All models inherit from `infra.db.base.Base`
- Use `Mapped[]` type annotations (SQLAlchemy 2.0 style)
- Relationship lazy loading: always specify `lazy=` explicitly
- Table names: snake_case plural (e.g. `user_accounts`)
```
