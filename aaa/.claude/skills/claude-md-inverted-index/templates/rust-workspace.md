---
name: rust-workspace
target-stack: Rust Cargo Workspace (Axum/Actix, SQLx, SeaORM)
placeholders: ["{project}"]
---

# Rust Cargo Workspace -- Inverted Index Template

## Part 1: PROJECT_ROOT/CLAUDE.md

Copy this section to your project root's `CLAUDE.md` (not `~/.claude/CLAUDE.md`).
Replace `{project}` with your project name (e.g., `myapp`).

```markdown
## Crate Dependency Graph

```
{project}-bin  -->  {project}-api  -->  {project}-app  -->  {project}-domain
                    {project}-api  -->  {project}-infra -->  {project}-domain
                                        {project}-infra -->  {project}-app (trait impls)
{project}-macros (proc-macro, used by {project}-domain)
```

### Crate Overview
| Crate              | Path                  | Type       | Purpose                          |
|--------------------|-----------------------|------------|----------------------------------|
| {project}-bin      | crates/bin/           | bin        | Entry point, CLI, server startup |
| {project}-api      | crates/api/           | lib        | HTTP/gRPC handlers, routing      |
| {project}-app      | crates/app/           | lib        | Use cases, application services  |
| {project}-domain   | crates/domain/        | lib        | Entities, value objects, traits  |
| {project}-infra    | crates/infra/         | lib        | DB, cache, external service impls|
| {project}-macros   | crates/macros/        | proc-macro | Derive macros for domain         |

### Trait -> Implementation Map
| Trait (crate::path)                       | Implementation                              |
|-------------------------------------------|---------------------------------------------|
| domain::repository::OrderRepository       | infra/src/postgres/order_repo.rs            |
| domain::repository::UserRepository        | infra/src/postgres/user_repo.rs             |
| domain::service::EventPublisher           | infra/src/kafka/publisher.rs                |
| domain::service::CacheService             | infra/src/redis/cache.rs                    |
| app::port::AuthTokenVerifier              | infra/src/jwt/verifier.rs                   |

### Feature Flags
| Feature          | Crate            | Effect                                    |
|------------------|------------------|-------------------------------------------|
| test-utils       | {project}-domain | Exposes builder/factory helpers for tests  |
| mock-infra       | {project}-infra  | Swaps real adapters for in-memory fakes    |

### Proc Macro Crate
- crate: crates/macros/
- entry: crates/macros/src/lib.rs
- Rules: Cannot export anything except proc macros. Cannot depend on crates that depend on it.

### Entry Points
- server: crates/bin/src/main.rs
- CLI: crates/bin/src/cli.rs (if applicable)

### Generated Files (DO NOT MODIFY)
- target/
- crates/infra/src/postgres/schema.rs (diesel print-schema output, if using diesel)
- **/*.generated.rs

### Detailed Conventions
See `.claude/rules/` for per-technology location maps and conventions.
```

---

## Part 2: PROJECT_ROOT/.claude/rules/ Files

Create each file below in your project's `.claude/rules/` directory (not `~/.claude/rules/`).
Replace `{project}` with your project name.

---

### File: domain.md

```yaml
---
description: "Domain entities, value objects, trait definitions, module re-exports, and orphan rule constraints"
paths: ["**/domain/**"]
---
```

```markdown
## Domain Crate

### Domain Concept -> File Map
| Concept            | Path                                    |
|--------------------|-----------------------------------------|
| Entities           | crates/domain/src/entities/             |
| Value objects      | crates/domain/src/values/               |
| Domain errors      | crates/domain/src/error.rs              |
| Repository traits  | crates/domain/src/repository/           |
| Service traits     | crates/domain/src/service/              |
| Use cases          | crates/app/src/usecases/                |
| Commands/Queries   | crates/app/src/dto/                     |

### Module Re-export Chain
Rust's `pub mod` / `pub use` re-exports create indirection. Check `crates/{crate}/src/lib.rs` for the full re-export tree.

| Public API (what consumers import)        | Actual definition location                  |
|-------------------------------------------|---------------------------------------------|
| {project}_domain::OrderId                 | crates/domain/src/values/order_id.rs        |
| {project}_domain::Order                   | crates/domain/src/entities/order.rs         |
| {project}_api::routes                     | crates/api/src/routes/mod.rs                |

### Orphan Rule Constraints
- Trait impls must live in either the crate that defines the trait or the crate that defines the type.
- Foreign trait on foreign type requires a newtype wrapper.
- When adding a new impl, verify both the trait and type crate origins to avoid orphan rule violations.

### Dependency Rules
- domain crate MUST NOT depend on infra or api crates.
- All trait definitions in domain; all impl blocks in infra.
- Proc-macro crate must remain dependency-minimal.
```

---

### File: postgresql.md

```yaml
---
description: "SQLx/Diesel queries, repository implementations, migrations"
paths: ["**/postgres/**", "**/db/**", "migrations/**"]
---
```

```markdown
## PostgreSQL (SQLx / Diesel)

### Location Map
- queries: crates/infra/src/postgres/queries/ (.sql files if using sqlx)
- repo-impl: crates/infra/src/postgres/
- migrations: migrations/ (sqlx) or diesel/migrations/ (diesel)
- config: crates/infra/src/config/database.rs

### Conventions
- Repository structs implement traits defined in domain::repository.
- SQLx compile-time checked queries: `sqlx::query_as!` with .sql files in queries/.
- Diesel schema: crates/infra/src/postgres/schema.rs (DO NOT MODIFY -- generated by `diesel print-schema`).
- Regenerate: `cargo sqlx prepare` (sqlx) or `diesel print-schema > schema.rs` (diesel).

### Build Script
- If using sqlx offline mode: `.sqlx/` directory contains query metadata (committed to git).
- If using diesel: `diesel.toml` in workspace root configures schema output path.
```

---

### File: kafka.md

```yaml
---
description: "Kafka producer/consumer (rdkafka)"
paths: ["**/kafka/**", "**/queue/**"]
---
```

```markdown
## Kafka (rdkafka)

### Location Map
- producer: crates/infra/src/kafka/producer.rs
- consumer: crates/infra/src/kafka/consumer.rs
- config: crates/infra/src/config/kafka.rs

### Conventions
- Producer implements domain::service::EventPublisher trait.
- Consumer deserialization should produce domain event types.
- rdkafka is a C-binding (librdkafka); ensure `cmake` and `librdkafka` are available for builds.
```

---

### File: redis.md

```yaml
---
description: "Redis cache adapter"
paths: ["**/redis/**", "**/cache/**"]
---
```

```markdown
## Redis

### Location Map
- adapter: crates/infra/src/redis/
- config: crates/infra/src/config/redis.rs

### Conventions
- Cache adapter implements domain::service::CacheService trait.
- Cache keys should follow: {domain}:{entity}:{id} naming pattern.
- TTL configuration belongs in config, not in adapter logic.
```

---

### File: http.md

```yaml
---
description: "Axum/Actix handlers, routes, extractors, middleware"
paths: ["**/handlers/**", "**/routes/**", "**/extractors/**", "**/middleware/**"]
---
```

```markdown
## HTTP (Axum / Actix-web)

### Location Map
- handlers: crates/api/src/handlers/
- routes: crates/api/src/routes/
- middleware: crates/api/src/middleware/
- extractors: crates/api/src/extractors/

### Conventions
- Handlers receive application services via Axum State or Actix Data extractors.
- Custom extractors implement `FromRequest` / `FromRequestParts`.
- Error responses map domain errors to HTTP status codes in a central error handler.
- Route registration is centralized in crates/api/src/routes/mod.rs.
```

---

### File: build.md

```yaml
---
description: "Build scripts (build.rs), code generation, proc-macro compilation"
paths: ["**/build.rs", "**/macros/**", "**/*.generated.rs"]
---
```

```markdown
## Build Scripts & Code Generation

### build.rs Locations
- workspace root: build.rs (if workspace-level build script exists)
- per-crate: crates/{crate}/build.rs

### Proc Macro Crate
- crate: crates/macros/
- entry: crates/macros/src/lib.rs
- derives: crates/macros/src/derive/
- Rules: Proc-macro crates compile in a separate step. Cannot export anything except proc macros. Cannot depend on crates that depend on it (circular dependency).

### Generated Files (DO NOT MODIFY)
- target/ -- build output
- **/*.generated.rs -- codegen output
- crates/infra/src/postgres/schema.rs -- diesel schema (if applicable)

### Common Build Commands
- `cargo build` -- full workspace build
- `cargo test --features test-utils,mock-infra` -- test with feature flags
- `cargo sqlx prepare` -- regenerate sqlx offline query data
- `cargo clippy --workspace` -- lint entire workspace
```
