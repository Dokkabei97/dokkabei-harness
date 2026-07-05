> **English** · [한국어](README_KO.md)

# backend-shared

> A language- and framework-agnostic backend common layer — reused on any stack, from API design to migration, architecture, and operational patterns.

## Overview

`backend-shared` provides a **language-neutral common layer** that applies across any backend stack — Kotlin/Spring, Python/FastAPI, Go/mux, and more. It covers REST/GraphQL API contract design, safe DB migrations, hexagonal architecture, and cross-cutting concerns such as observability, caching, events, resilience, security, DTOs, and testing, organized into three layers: commands (execution), agents (specialized analysis), and skills (reference).

The design intent is "gathering the decision criteria that are duplicated across languages into one place." The idiomatic code and detailed APIs of a specific framework are handled by the language-specific plugins (`kotlin-spring`, `python-fastapi`, `go-mux`), while this plugin is responsible for the principles, checklists, and contract design that don't change even when the stack changes. Use it as the foundational layer you consult first, regardless of language, when opening up a new API, changing a schema with zero downtime, or validating architectural boundaries. On top of this, `context7-docs-guide` provides a common convention for looking up the latest documentation that blocks hallucination of version-sensitive APIs, so that code generation across the 4 stacks references it.

## Components

### Commands

- `/api-design` — Designs REST API endpoints based on requirements and generates the Controller + DTO + error handling code.
- `/api-gen` — Generates API endpoint scaffolding (Controller/Router, Service, DTO/Schema, test stubs) for REST/GraphQL and Kotlin/Python.
- `/api-doc` — Generates API documentation from code (OpenAPI 3.0 spec, GraphQL SDL, request/response examples, springdoc/FastAPI annotations).
- `/api-test` — Auto-generates integration tests for existing API endpoints (@WebMvcTest/TestClient, MockK/pytest-mock, auth·GraphQL scenarios).
- `/api-perf` — Analyzes API performance (N+1 query JPA/SQLAlchemy detection, connection pool configuration, query execution plan hints).
- `/bean-check` — Validates DI configuration (circular dependencies, missing Beans, `@Transactional` misuse, `Depends` chains, GraphQL DataLoader).
- `/graphql-check` — Validates GraphQL schema quality·performance·security (naming, N+1, missing DataLoader, depth limit, introspection, field-level authorization).
- `/event-gen` — Generates event-driven code scaffolding (Kafka Producer/Consumer, Spring ApplicationEvent, AsyncAPI spec).
- `/migrate` — Generates safe DB migrations (Flyway/Alembic, zero-downtime compatibility validation, expand-contract pattern, rollback scripts).
- `/security-check` — Validates authentication/authorization configuration (CORS, CSRF, header security, missing endpoint protection detection — Spring Boot/FastAPI).

### Agents

- `api-designer` — REST/GraphQL API contract design specialist. Responsible for OpenAPI specs, GraphQL SDL, DTO/Input Type design, validation, error response standardization, and versioning.
- `migration-advisor` — DB migration safety specialist. Performs zero-downtime schema changes, expand-contract, rollback strategies, data backfill, and index impact analysis (model: opus).
- `infra-integration-guide` — PG/Valkey/Kafka infrastructure integration specialist. Guides connection management, serialization, error handling, and test patterns.

### Skills (reference)

- `hexagonal-architecture` — Hexagonal architecture guide. Port/adapter structure, package layout, dependency direction, module boundaries.
- `dto-design-patterns` — DTO design patterns. Request/Response/Projection separation, preferring data class over Map, nullable policy, Jackson/Pydantic serialization.
- `graphql-design-guide` — GraphQL schema design·performance·security guide. Naming, pagination, error handling, DataLoader, query complexity, security checklist.
- `async-event-patterns` — Async & event patterns. Kotlin Coroutines, Spring Kafka, FastAPI BackgroundTasks, PG/Valkey/Kafka integration.
- `caching-patterns` — Caching patterns. Spring Cache `@Cacheable`/`@CacheEvict`, Valkey patterns, FastAPI caching, TTL strategy.
- `resilience-patterns` — Resilience patterns. Circuit Breaker(Resilience4j), Retry, Timeout, Bulkhead, WebClient/httpx error handling.
- `observability-patterns` — Observability patterns. OpenTelemetry-based logging/tracing/metrics, OTel Collector, Actuator, Health Check.
- `security-patterns` — Authentication/authorization patterns. Spring Security JWT/OAuth2/RBAC, FastAPI OAuth2/Depends authorization, Three-Tier Boundary, OWASP Top 10 mapping.
- `migration-safety-checklist` — DB migration safety checklist. Zero-downtime change assessment, Expand-Contract, Flyway/Alembic rules, rollback strategy.
- `backend-testing-patterns` — Backend test setup·patterns. Spring Boot slices, MockK, Kotest, FastAPI, pytest, Testcontainers, GraphQL testing.
- `context7-docs-guide` — Context7 latest-documentation lookup common convention. Version-sensitive API assessment criteria, `resolve-library-id` → `query-docs` procedure, graceful degrade when not installed, per-stack application points, lookup cost trade-offs.

## Usage

- **Commands** are invoked directly via slash. Examples: `/api-design order creation endpoint`, `/migrate add status column to orders table`, `/graphql-check`, `/security-check`.
- **Agents** are delegated to·invoked for tasks that need specialized judgment, such as API contract design, migration safety, and infrastructure integration, and return their analysis results. `migration-advisor` handles high-risk schema changes, so it uses the opus model.
- **Skills** are automatically activated to fit the context during related tasks (architecture design, DTO writing, introducing caching/security/observability, etc.), injecting decision criteria and patterns. They are referenced without a separate command.
- Code-generation commands (`/api-gen`, `/api-design`, `/event-gen`, etc.) look up the latest documentation per the `context7-docs-guide` convention when handling version-sensitive APIs, reducing hallucination.

## Dependencies

There are no forced `dependencies` or `requires` in `plugin.json`. This plugin alone can perform language-neutral common tasks. However, to cover the idiomatic code and framework details of a specific stack, using it together with a language-specific plugin is recommended.

- `kotlin-spring` — Kotlin/Spring Boot specialization
- `python-fastapi` — Python/FastAPI specialization
- `go-mux` — Go specialization

## Notes

- The Context7 MCP server that `context7-docs-guide` references is optional. If it is not installed, it gracefully degrades per the convention and proceeds without lookup, so the remaining features work normally even in an uninstalled environment.
- This plugin is a common layer independent of language·framework. Stack-specific detailed implementations·idiomatic code are handled by the corresponding language-specific plugin, so using the two layers together divides responsibilities without duplication.
- The security checks provided by `/security-check`·`security-patterns` are auxiliary tools for configuration validation at the development stage, and do not replace a formal security audit or penetration testing.
