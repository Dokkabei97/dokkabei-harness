# Rust Cargo Workspace -- Inverted Index Guide

Rust projects using Cargo workspaces with multiple crates.
Trait -> Implementation mapping across crates is the killer feature because
Rust's orphan rule forces implementations to live in specific crates.

## Workspace Crate Structure

```
project-root/
  Cargo.toml                    # Workspace definition
  Cargo.lock                    # Lockfile
  crates/
    api/                        # HTTP server (Axum/Actix)
      Cargo.toml
      src/
        lib.rs                  # Crate root
        main.rs                 # Binary entry point
        routes/                 # Route handlers
        extractors/             # Custom Axum extractors
        middleware/              # Tower middleware
        error.rs                # Error types + IntoResponse
    domain/                     # Pure domain logic (no framework deps)
      Cargo.toml
      src/
        lib.rs
        models/                 # Domain entities, value objects
        services/               # Domain services
        ports.rs                # Trait definitions (ports)
        errors.rs               # Domain errors
    infra/                      # Infrastructure implementations
      Cargo.toml
      src/
        lib.rs
        db/                     # SQLx/SeaORM implementations
        cache/                  # Redis implementations
        queue/                  # Message queue implementations
        client/                 # External HTTP clients
    shared/                     # Cross-cutting utilities
      Cargo.toml
      src/
        lib.rs
        config.rs               # Configuration structs
        telemetry.rs            # Tracing/metrics setup
        auth.rs                 # Auth token validation
    migration/                  # Database migrations
      Cargo.toml
      src/
        lib.rs
        m20240101_000001_create_users.rs
    macros/                     # Procedural macros (must be separate crate)
      Cargo.toml
      src/
        lib.rs
```

## Technology -> Location Mapping

```markdown
## Tech -> Location Map

### Axum / HTTP
- routes: crates/api/src/routes/
- extractors: crates/api/src/extractors/
- middleware: crates/api/src/middleware/
- error handling: crates/api/src/error.rs
- app state: crates/api/src/state.rs

### SQLx / Database
- repository impl: crates/infra/src/db/
- queries: crates/infra/src/db/queries/ (or .sql files)
- migrations: crates/migration/src/
- sqlx prepared: .sqlx/ (offline query data, DO NOT MODIFY manually)

### Redis
- impl: crates/infra/src/cache/
- config: crates/shared/src/config.rs (RedisConfig struct)

### Message Queue (Kafka/NATS)
- producer/consumer: crates/infra/src/queue/
- message types: crates/domain/src/models/events.rs

### Configuration
- structs: crates/shared/src/config.rs
- loading: crates/shared/src/config.rs (from env/files)
- .env: .env, .env.example

### Observability
- tracing setup: crates/shared/src/telemetry.rs
- metrics: crates/shared/src/metrics.rs
```

## Trait -> Implementation Mapping

This is THE essential section for Rust. Traits defined in `domain` are implemented
in `infra` or other crates. Agents cannot find this through simple text search because
`impl TraitName for StructName` may be in a completely different crate.

```markdown
## Trait -> Implementation Mapping

| Trait (crates/domain/src/ports.rs)  | Impl Crate | Impl File                       |
|-------------------------------------|------------|---------------------------------|
| OrderRepository                     | infra      | infra/src/db/order_repo.rs      |
| CacheStore                          | infra      | infra/src/cache/redis_store.rs  |
| EventPublisher                      | infra      | infra/src/queue/kafka_pub.rs    |
| PaymentGateway                      | infra      | infra/src/client/stripe.rs      |
| OrderRepository (mock)              | domain     | domain/src/ports.rs (#[cfg(test)])|

To find all implementations of a trait:
  grep -rn "impl.*TraitName" crates/
```

## mod.rs / lib.rs Module Chain

Rust's module system requires explicit declarations. Document the chain:

```markdown
## Module Declaration Chain

crates/infra/src/lib.rs
  pub mod db;           -> crates/infra/src/db/mod.rs
  pub mod cache;        -> crates/infra/src/cache/mod.rs
  pub mod queue;        -> crates/infra/src/queue/mod.rs

crates/infra/src/db/mod.rs
  mod order_repo;       -> crates/infra/src/db/order_repo.rs
  mod user_repo;        -> crates/infra/src/db/user_repo.rs
  pub use order_repo::OrderRepoImpl;
  pub use user_repo::UserRepoImpl;
```

## Feature Flags (cfg) Mapping

Cargo features enable/disable code paths. Document what each feature activates:

```markdown
## Feature Flag Mapping

| Crate  | Feature       | Enables                              | Files Affected                |
|--------|---------------|--------------------------------------|-------------------------------|
| infra  | postgres      | PostgreSQL repository implementations| infra/src/db/postgres/        |
| infra  | sqlite        | SQLite repository implementations    | infra/src/db/sqlite/          |
| infra  | redis-cache   | Redis cache adapter                  | infra/src/cache/redis.rs      |
| infra  | mock-repos    | In-memory mock implementations       | infra/src/db/mock/            |
| api    | swagger       | OpenAPI docs endpoint                | api/src/routes/swagger.rs     |
| shared | test-utils    | Test helper utilities                | shared/src/test_utils.rs      |
```

## Procedural Macro Crates

Rust requires proc macros to live in a separate crate. Always call this out:

```markdown
## Procedural Macro Crate
- Location: crates/macros/
- Provides: #[derive(DomainEvent)], #[api_handler]
- Must be separate crate (Rust compiler requirement)
- Changes here trigger recompilation of ALL dependent crates
```

## Re-export Chains (pub use)

Rust crates re-export items to create a clean public API. Document the chain:

```markdown
## Re-export Chain (trace pub use to source)

| Public API                    | Re-exported In           | Defined In                      |
|-------------------------------|--------------------------|---------------------------------|
| domain::Order                 | domain/src/lib.rs        | domain/src/models/order.rs      |
| domain::OrderRepository       | domain/src/lib.rs        | domain/src/ports.rs             |
| infra::db::OrderRepoImpl     | infra/src/db/mod.rs      | infra/src/db/order_repo.rs      |
| shared::Config                | shared/src/lib.rs        | shared/src/config.rs            |
```

## Orphan Rule Implications

The orphan rule determines WHERE trait implementations can be placed:

```markdown
## Orphan Rule Constraints
- You can only impl a trait if you own the trait OR the type (or both)
- External trait on external type: use a newtype wrapper
- This is why infra/ implements domain/ traits: infra owns the struct, domain owns the trait
- If you need a third-party trait on a domain type, impl it in the domain crate
```

## Build Scripts (build.rs)

```markdown
## Build Scripts
| Crate     | build.rs Purpose               | Generates                    |
|-----------|-------------------------------|------------------------------|
| api       | protobuf compilation          | src/proto_gen/ (DO NOT MODIFY)|
| macros    | (none typically)              |                              |
| migration | (none typically)              |                              |

Build script outputs go to: target/debug/build/{crate}-{hash}/out/
```

## Auto-Extracting Crate List from Cargo.toml

```bash
# List workspace members
grep -A 50 '\[workspace\]' Cargo.toml | grep '"' | tr -d ' ",'

# Or parse members array
cargo metadata --no-deps --format-version 1 | jq -r '.packages[].name'

# Find all trait definitions
grep -rn "pub trait" crates/domain/src/

# Find all trait implementations
grep -rn "impl .* for " crates/infra/src/
```

## Complete 3-Tier Example

### Part 1: Root CLAUDE.md

```markdown
## Crate Overview
| Crate     | Role                  | Key Deps              |
|-----------|-----------------------|-----------------------|
| api       | HTTP server (Axum)    | axum, tower, domain   |
| domain    | Pure business logic   | (no framework deps)   |
| infra     | DB/cache/queue impls  | sqlx, redis, kafka    |
| shared    | Cross-cutting utils   | config, tracing       |
| migration | DB schema migrations  | sea-orm-migration     |
| macros    | Procedural macros     | syn, quote            |
| worker    | Background jobs       | tokio, domain, infra  |

## Trait -> Implementation
| Trait (domain/src/ports.rs) | Impl File                       |
|-----------------------------|---------------------------------|
| OrderRepository             | infra/src/db/order_repo.rs      |
| CacheStore                  | infra/src/cache/redis_store.rs  |
| EventPublisher              | infra/src/queue/kafka_pub.rs    |
| PaymentGateway              | infra/src/client/stripe.rs      |

## Feature Flags
| Crate | Feature    | Enables                    |
|-------|------------|----------------------------|
| infra | postgres   | PG repository impls        |
| infra | redis      | Redis cache adapter        |
| api   | swagger    | /docs OpenAPI endpoint     |

## Proc Macros (separate crate — compiler requirement)
- crates/macros/ -> #[derive(DomainEvent)], #[api_handler]
- Changes trigger recompilation of ALL dependent crates

## Entry Points
- API server: crates/api/src/main.rs
- Worker:     crates/worker/src/main.rs

## Generated Files (DO NOT MODIFY)
- .sqlx/                     (sqlx offline query data)
- crates/api/src/proto_gen/  (protobuf codegen)
- target/                    (build artifacts)

## Rules
- Domain rules & orphan rule constraints: @.claude/rules/domain.md
```

### Part 2: .claude/rules/domain.md

```markdown
---
paths:
  - crates/domain/**
  - crates/infra/src/db/**
  - crates/infra/src/cache/**
  - crates/infra/src/queue/**
  - crates/infra/src/client/**
---

## Module Re-export Chain

crates/domain/src/lib.rs
  pub mod models;         -> models/mod.rs
  pub mod services;       -> services/mod.rs
  pub mod ports;          -> ports.rs
  pub use models::Order;
  pub use ports::OrderRepository;

crates/infra/src/lib.rs
  pub mod db;             -> db/mod.rs
  pub mod cache;          -> cache/mod.rs
  pub mod queue;          -> queue/mod.rs

crates/infra/src/db/mod.rs
  mod order_repo;         -> db/order_repo.rs
  pub use order_repo::OrderRepoImpl;

## Orphan Rule Constraints
- impl a trait only if you own the trait OR the type
- External trait on external type → newtype wrapper
- infra/ implements domain/ traits: infra owns the struct, domain owns the trait
- Third-party trait on a domain type → impl in domain crate

## Domain Editing Rules
- Trait signatures in ports.rs are the contract — changing them requires updating ALL impls in infra/
- Keep domain/ free of framework dependencies (no axum, sqlx, redis)
- #[cfg(test)] mock impls live in domain/src/ports.rs, not in infra/
```
