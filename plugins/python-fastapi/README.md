> **English** · [한국어](README_KO.md)

# python-fastapi

> A code-generation, design, and guidance bundle specialized for Python + FastAPI backend development. From domain definition, it scaffolds the entire CRUD layer and REST API according to project conventions, and provides idiomatic patterns and decision criteria along the way.

## Overview

This plugin is a collection of development tools for the Python + FastAPI stack. It consists of scaffolding that generates the full layer stack SQLAlchemy Model → Pydantic Schema → Repository → Service → Router → Test from a single domain name (`fastapi-gen`), API design focused on REST resource design (`fastapi-api-design`), a code-generation specialist agent (`fastapi-developer`) and a framework diagnostics agent (`fastapi-guide`), plus an idiomatic-pattern reference (`fastapi-patterns`) and a development-principles/decision guide (`python-fastapi-guide`).

The core design principles are **Pythonic First**, **Layer Discipline** (dependency direction always flows downward Router→Service→Repository), **Fail Fast** (triple defense of Pydantic, domain, and DB constraints), and **Convention over Configuration**. Before writing any code, every generation tool first analyzes the existing project structure (sync/async, SQLAlchemy 1.x/2.0, module layout, test style) and follows the conventions exactly. Language-neutral backend common patterns (API contracts, DB migration safety, observability/caching/events/resilience/security) are handled not by this plugin but by the `backend-shared` plugin, and using the two plugins together is assumed.

## Components

### Commands

- `/fastapi-gen` — Given a domain name, it generates the entire CRUD layer of SQLAlchemy Model, Pydantic Schema, Repository, Service, Router, and Test bottom-up according to project conventions. Supports the `--fields`, `--layers`, `--no-test`, `--async`, `--soft-delete`, and `--audit` options.
- `/fastapi-api-design` — It maps requirements to REST resources/actions to design endpoints, request/response schemas, and error codes, and generates Router + Schema + Exception code. Supports the `--version`, `--auth`, `--pagination` (cursor/offset), and `--error-style` (rfc7807/custom) options.

### Agents

- `fastapi-developer` — A specialist agent for Python + FastAPI code generation. After analyzing project conventions, it generates the entire layer idiomatically (type hints, async/await, Pydantic V2, match/case), and after generation verifies with pytest, type checking, and lint. It leverages the `python-fastapi-guide` skill.
- `fastapi-guide` — A FastAPI framework expert agent (model: sonnet). It diagnoses and advises on Depends DI chains, Pydantic v2 validation, async SQLAlchemy session and loading strategies, Alembic, middleware, BackgroundTasks, lifespan, and Strawberry GraphQL integration. A read-centric (Read/Grep/Glob/Bash) agent that treats async correctness as the top priority.

### Skills

- `fastapi-patterns` — An idiomatic FastAPI pattern reference. It organizes Depends DI, Pydantic v2, async SQLAlchemy, Alembic, middleware, Strawberry GraphQL, lifespan, httpx client, and BaseSettings into runnable code snippets.
- `python-fastapi-guide` — A development-principles/decision guide. It provides the Pythonic First, Layer Discipline, and Fail Fast principles and criteria for choosing architecture/stack/test frameworks, and includes three reference documents: `references/layer-patterns.md` (per-layer patterns), `references/sqlalchemy-patterns.md` (model design, N+1 prevention, migrations), and `references/testing-patterns.md` (pytest, Mock, httpx, Factory Boy).

## Usage

- Commands are invoked directly with a slash. Examples: `/fastapi-gen Order`, `/fastapi-gen Product --fields "name:str, price:Decimal" --async --audit`, `/fastapi-api-design Order API --auth jwt --pagination cursor`.
- Agents are auto-delegated or explicitly invoked depending on the nature of the task. When code generation is needed, as in "make Order CRUD," `fastapi-developer` is triggered; for framework issues like "diagnose a Depends cycle problem" or "async session leak," `fastapi-guide` is triggered.
- Skills are auto-referenced in the context of related work. When writing or reviewing FastAPI code, the principles of `python-fastapi-guide` are loaded, and when concrete implementation patterns are needed, `fastapi-patterns` is loaded.
- The common flow of the generation tools is three stages: Discovery (analyze project conventions) → Generation (generate layers) → Verification (pytest/type check/lint), and points that require business-logic implementation are left with a `# TODO(human)` marker.

## Dependencies

- **requires: `backend-shared`** — Language-neutral backend common patterns such as API contracts, migrations, and security are provided by the `backend-shared` plugin, so it must be installed together. Version-sensitive APIs (Pydantic v2, etc.) are generated after querying the latest documentation via Context7 MCP following the `backend-shared:context7-docs-guide` convention (skipped if not installed).

## Notes

- The code-generation tools do not modify existing files without authorization, and do not arbitrarily add dependencies to `pyproject.toml` (separate confirmation required).
- Non-Pythonic patterns (`Optional[]`, `type()` comparison, mutable default, etc.) are not generated, and if the project is an async stack, generation uses `AsyncSession` + `async def`.
- Context7 MCP is optional. If it is not installed, the version-documentation query step is skipped and work proceeds.
