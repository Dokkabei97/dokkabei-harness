---
name: go-standard
target-stack: Go Standard Layout + DDD/Clean Architecture
placeholders: ["{module}", "{service}"]
---

# Go Standard Layout -- Inverted Index Template

## Part 1: PROJECT_ROOT/CLAUDE.md

Copy this section to your project root's `CLAUDE.md` (not `~/.claude/CLAUDE.md`).
Replace `{module}` with your Go module path (e.g., `github.com/acme/orders`)
and `{service}` with your service name (e.g., `orders`).

```markdown
## Architecture: Go Standard Layout + DDD/Clean Architecture

### Entry Points
| Binary             | Path                 | Purpose                    |
|--------------------|----------------------|----------------------------|
| {service}-api      | cmd/api/main.go      | HTTP/gRPC server           |
| {service}-worker   | cmd/worker/main.go   | Async job consumer         |
| {service}-migrate  | cmd/migrate/main.go  | Database migration runner  |

### Interface -> Implementation Map
| Interface                   | Defined In                          | Implemented By                     |
|-----------------------------|-------------------------------------|------------------------------------|
| domain/order/Repository     | internal/domain/order/repo.go       | infra/postgres/order_repo.go       |
| domain/order/EventPublisher | internal/domain/order/event.go      | infra/kafka/order_publisher.go     |
| domain/user/Cache           | internal/domain/user/cache.go       | infra/redis/user_cache.go          |
| app/auth/TokenVerifier      | internal/app/auth/port.go           | infra/jwt/verifier.go              |

### Domain Concept -> File Map
| Concept          | Path                                 |
|------------------|--------------------------------------|
| Aggregate roots  | internal/domain/{aggregate}/         |
| Value objects    | internal/domain/{aggregate}/vo/      |
| Domain events    | internal/domain/{aggregate}/event/   |
| Domain services  | internal/domain/{aggregate}/service/ |
| Use cases        | internal/app/{feature}/              |
| DTOs / commands  | internal/app/{feature}/dto/          |

### Name Disambiguation
| Name    | Path                         | Meaning                       |
|---------|------------------------------|-------------------------------|
| Config  | internal/config/             | App configuration structs     |
| Config  | api/proto/                   | Proto service config messages |
| Service | internal/domain/.../service/ | Domain service (pure logic)   |
| Service | internal/transport/grpc/     | gRPC service implementation   |

### Generated Files (DO NOT MODIFY)
- api/proto/gen/ -- protoc / buf output
- internal/app/wire_gen.go -- Wire-generated injector
- mocks/ -- mockgen / mockery output

### DI Wiring
- Wire sets: internal/app/wire.go, internal/infra/wire.go
- Generated injector: internal/app/wire_gen.go (DO NOT MODIFY)

### Detailed Conventions
See `.claude/rules/` for per-technology location maps and conventions.
```

---

## Part 2: PROJECT_ROOT/.claude/rules/ Files

Create each file below in your project's `.claude/rules/` directory (not `~/.claude/rules/`).

---

### File: go-project-structure.md

```yaml
---
description: "Go project layout conventions: internal/ visibility, flat packages, dependency rules"
paths: ["**/internal/**", "**/cmd/**", "**/pkg/**"]
---
```

```markdown
## Go Project Structure Conventions

### internal/ Visibility Boundary
- Code under `internal/` is invisible to external Go modules.
- `internal/domain/` -- pure business logic, no infrastructure imports.
- `internal/app/` -- application/use-case layer, orchestrates domain.
- `internal/infra/` -- infrastructure adapters (DB, cache, messaging).
- `internal/transport/` -- HTTP/gRPC handlers (inbound adapters).
- `internal/config/` -- configuration structs and loaders.

### Flat Package Convention
- Prefer flat packages over deep nesting. One package = one concept.
- Avoid `utils/`, `helpers/`, `common/` packages. Place code where it belongs.
- Package names are short, lowercase, singular nouns (e.g., `order`, `auth`).

### Dependency Rules
- `internal/domain/` MUST NOT import from `internal/infra/` or `internal/transport/`.
- All interfaces defined in `domain/`; implementations in `infra/`.
- `cmd/` packages contain only `main()` and wiring.
- `internal/app/` may import `domain/` but NOT `infra/` or `transport/`.
```

---

### File: postgresql.md

```yaml
---
description: "PostgreSQL repository implementations and migrations"
paths: ["**/repository/**", "**/postgres/**", "**/migration*/**"]
---
```

```markdown
## PostgreSQL

### Location Map
- repository-impl: internal/infra/postgres/
- migrations: migrations/
- config: internal/config/database.go

### Conventions
- Migration tool: golang-migrate or goose.
- Migration files: `{version}_{name}.up.sql` / `.down.sql`
- Repository structs implement domain interfaces (e.g., `domain/order/Repository`).
- Use `sqlx` struct tags or `pgx` for query mapping.
```

---

### File: kafka.md

```yaml
---
description: "Kafka producer/consumer implementations"
paths: ["**/consumer/**", "**/producer/**", "**/kafka/**"]
---
```

```markdown
## Kafka

### Location Map
- producer: internal/infra/kafka/producer.go
- consumer: internal/infra/kafka/consumer.go
- config: internal/config/kafka.go

### Conventions
- Producers implement domain `EventPublisher` interfaces.
- Consumers deserialize messages and delegate to application use-cases.
- Event schemas (Avro/Protobuf) live in `api/proto/` or `api/avro/`.
```

---

### File: redis.md

```yaml
---
description: "Redis cache adapter"
paths: ["**/cache/**", "**/redis/**"]
---
```

```markdown
## Redis

### Location Map
- adapter: internal/infra/redis/
- config: internal/config/redis.go

### Conventions
- Cache adapters implement domain `Cache` interfaces.
- Cache keys follow pattern: `{domain}:{id}` (e.g., `user:123`).
- TTL configuration belongs in config, not in adapter logic.
```

---

### File: grpc.md

```yaml
---
description: "gRPC server and protobuf definitions"
paths: ["**/grpc/**", "**/proto/**"]
---
```

```markdown
## gRPC

### Location Map
- proto definitions: api/proto/
- generated stubs: api/proto/gen/ (DO NOT MODIFY)
- server impl: internal/transport/grpc/
- config: internal/config/grpc.go

### Conventions
- Regenerate stubs: `buf generate`
- Proto-generated code in `api/proto/gen/` must never be hand-edited.
- gRPC service implementations live in `internal/transport/grpc/`.
- Use buf for linting and breaking change detection.
```

---

### File: http.md

```yaml
---
description: "HTTP handlers, routes, and middleware"
paths: ["**/handler/**", "**/http/**", "**/middleware/**"]
---
```

```markdown
## HTTP

### Location Map
- handlers: internal/transport/http/handler/
- routes: internal/transport/http/router.go
- middleware: internal/transport/http/middleware/

### Conventions
- Handlers receive decoded requests, call use-cases, and return responses.
- Middleware handles cross-cutting concerns (auth, logging, CORS, recovery).
- Route registration is centralized in `router.go`.
- Use framework-idiomatic patterns (chi, gin, echo, or net/http).
```
