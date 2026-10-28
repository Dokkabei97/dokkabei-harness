> **English** · [한국어](README_KO.md)

# python-fastapi

> A Python + FastAPI bundle built around a **specialist layer**: pitfalls that even strong senior generalists miss (event-loop blocking, the 40-token thread pool, psycopg pool and PgBouncer prepared statements, Pydantic/response serialization cost, GIL/free-threading, memory and GC, uvicorn deployment, PostGIS indexing), plus generators that detect the project's actual stack before writing code.

## Overview

The entry skill `python-fastapi-guide` is a symptom → item triage index. Each item in its `references/` has an ID (`FA-*`, `PY-*`), applicability conditions, signals, mechanism, prescription, counter-cases, a verification method, and sources, so project-specific rules (`CLAUDE.md` / `.claude/rules/`) can pick only the items that apply. It is guidance, not enforcement.

Nothing about the stack is assumed. Before generating or advising, the tools detect the query layer (SQLAlchemy ORM vs raw SQL with psycopg 3 / asyncpg), the migration tool (Alembic, dbmate, or none), sync vs async, versions (FastAPI 0.130 serialization boundary, Python 3.14.5 GC boundary), and how the app is launched. Language-neutral backend patterns live in `backend-shared`.

## Components

### Commands (user-invoked only — `disable-model-invocation: true`)

- `/fastapi-gen` — Detects the query layer and migration tool, then generates (Migration) → (ORM Model) → Schema → Repository → Service → Router → Test following existing conventions. Includes raw-SQL (psycopg 3) repository and dbmate migration examples alongside the SQLAlchemy ones.
- `/fastapi-api-design` — Maps requirements to REST resources and generates Router + Schema + error handling, after checking existing API conventions and the query layer.

### Agents

- `fastapi-developer` — Code-generation agent; preloads `python-fastapi-guide`, detects the stack first, and applies the specialist checks while generating.
- `fastapi-guide` — Read-centric diagnostics agent (model: sonnet); preloads `python-fastapi-guide` and traces latency, pool, memory, serialization, deployment, and PostGIS problems to root cause with verification commands. Instructed not to edit files (its Bash access is for read-only diagnostics; it proposes changes as diffs).

### Skills

- `python-fastapi-guide` — Specialist triage entry skill (activates on `**/*.py`, `**/pyproject.toml` via `paths`). References:
  - `async-concurrency.md` (FA-ASYNC, FA-THREAD, FA-BG), `psycopg-postgres.md` (PY-PG, PY-MIG), `pydantic-serialization.md` (FA-PYD, FA-RESP), `runtime-memory-gc.md` (PY-GIL, PY-MEM, PY-GC), `deployment-uvicorn.md` (FA-SRV), `postgis.md` (PY-GIS)
  - General references: `fastapi-idioms.md` (the former `fastapi-patterns` skill, merged 2026-10), `layer-patterns.md`, `sqlalchemy-patterns.md` (ORM projects only), `testing-patterns.md`

## Usage

- `/fastapi-gen Order`, `/fastapi-gen Product --fields "name:str, price:Decimal" --audit`, `/fastapi-api-design Order API --pagination cursor`.
- Diagnostics: "this endpoint stalls under load", "PoolTimeout after scaling out", "radius search returns everything" → `fastapi-guide` or the skill's triage table.
- To persist applicable items as project rules, record the item ID + condition + project fact in `.claude/rules/` (use `workflow:project-rules` if installed).

## Dependencies

- **requires: `backend-shared`**. Version-sensitive APIs can be looked up via Context7 following `backend-shared:context7-docs-guide` (skipped if not installed).

## Notes

- Generators do not modify existing files without authorization and do not add dependencies on their own.
- The `fastapi-patterns` skill was archived to `archive/components/python-fastapi/skills/fastapi-patterns/` (content merged into `references/fastapi-idioms.md`).
