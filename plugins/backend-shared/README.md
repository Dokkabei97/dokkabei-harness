> **English** · [한국어](README_KO.md)

# backend-shared

> Shared backend layer for Kotlin/Go/Python — PostgreSQL, Kafka, Valkey and distributed-call specialist knowledge that even senior engineers miss, plus team-specific rules.

## Overview

`backend-shared` does not restate generic patterns the model already knows ("add an index", "use a cache"). It captures **pitfalls caused by defaults, versions and internals that strong senior generalists miss** as ID'd items (applies-to, signals, mechanism, fix, counter-case, verification, sources), together with team rules (required DTO `channel`, timeout ceilings, cache key conventions).

It never assumes an ORM, migration tool or framework version: every skill starts by checking the project's build files, existing conventions and project CLAUDE.md. Per-project selection of item IDs is generated and audited by `workflow:project-rules` into `.claude/rules`.

## Components

### Skills (3 model-invocable entry points)

- `migration-safety-checklist` — zero-downtime schema changes: tool detection (Flyway, Liquibase, Alembic, dbmate, golang-migrate, goose, Atlas) and per-tool transaction boundaries, PostgreSQL DDL lock items PG-MIG-01..16 (lock_timeout and lock queues, PG11+ fast defaults, CHECK NOT VALID→VALIDATE, INVALID indexes after failed CONCURRENTLY, batched backfill).
- `async-event-patterns` — backend infrastructure specialist hub: symptom→item index plus `references/` items for PostgreSQL (PG-IDX/MVCC/POOL/PLAN/QRY/LOCK), Kafka (KFK-PRD/CON/TOP/EOS), Valkey (VK-KEY/EXP/MEM/CLI/LOCK/STR), distributed calls (DIST-TMO/RTY/IDEM/MSG/CACHE/NET/OBS/OPS) and team rules (team-conventions.md).
- `dto-design-patterns` — team DTO rules (DTO-T-*) plus serialization pitfalls (DTO-S-*: explicit null with Jackson Kotlin, Go nil slices, int64 IDs in JavaScript, Pydantic v2 Optional; Jackson 3 unknown-field default) in `references/serialization.md`.
- `context7-docs-guide` — short Context7 lookup convention for version-sensitive APIs; the stack guide skills (kotlin-spring, go-mux, python-fastapi, nextjs) point to it.

### Commands (user `/` invocation only, `disable-model-invocation`)

- `/api-design` — REST API design and implementation (Kotlin/Spring; Go and FastAPI use `/go-api-design` and `/fastapi-api-design`).
- `/api-doc` — OpenAPI / GraphQL SDL from code.
- `/api-test` — integration tests for existing endpoints.
- `/api-perf` — N+1, pool settings and plan analysis (references PG-POOL/PLAN items).
- `/bean-check` — DI configuration checks (Spring Boot/FastAPI).
- `/event-gen` — Kafka / ApplicationEvent scaffolding (references KFK items).
- `/graphql-check` — GraphQL schema checks.
- `/security-check` — authn/authz configuration checks.

### Agents

- `api-designer` — REST/GraphQL contract design (preloads `dto-design-patterns`, includes the team API intuitiveness checklist).
- `infra-integration-guide` — PG/Kafka/Valkey integration diagnosis and review (preloads `async-event-patterns`, reports by item ID).

## Usage

- Writing or reviewing migrations, or symptoms such as slow queries, pool exhaustion, consumer lag or cache issues, activate the matching skill from context. Entry skills are triage indexes; details live in `references/` and are read per item.
- Delegate a service-wide infrastructure review to the `infra-integration-guide` agent.
- Invoke commands directly, e.g. `/api-design order creation`, `/api-perf`, `/event-gen order completed event`.

## Dependencies

No forced `dependencies`. Use with `kotlin-spring`, `go-mux`, `python-fastapi` for stack idioms and `search` for Elasticsearch.

## Cleanup history (2026-10)

Generic pattern skills (backend-testing-patterns, caching-patterns, graphql-design-guide, hexagonal-architecture, observability-patterns, security-patterns, resilience-patterns), `/api-gen` (duplicated the per-stack `*-gen` commands) and `/migrate` + `migration-advisor` (absorbed into `migration-safety-checklist`) moved to `archive/components/backend-shared/`. Specialist items and team-specific paragraphs were extracted into the hub references. Restore by moving the paths back.

## Notes

- The Context7 MCP server is optional; without it the convention proceeds without lookups.
- `/security-check` is a development-time configuration aid and does not replace a formal security audit.
