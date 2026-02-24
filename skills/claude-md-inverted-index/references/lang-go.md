# Go Standard Layout + DDD -- Inverted Index Guide

Go projects using the standard layout (cmd/internal/pkg) with DDD or Clean Architecture.
Go's implicit interfaces make Interface -> Implementation mapping the single most valuable index section.

## Standard Layout Structure

```
project-root/
  go.mod                        # Module definition
  go.sum                        # Dependency checksums
  cmd/
    api-server/main.go          # HTTP server entry point
    worker/main.go              # Background worker entry point
    migrator/main.go            # DB migration runner
  internal/                     # Private application code (import boundary)
    domain/                     # Domain models, value objects
    usecase/                    # Application business logic
    port/                       # Interface definitions (ports)
    adapter/
      http/                     # HTTP handlers (driving adapter)
      grpc/                     # gRPC handlers (driving adapter)
      consumer/                 # Message queue consumers
      repository/               # Database implementations (driven adapter)
      cache/                    # Cache implementations
      client/                   # External API clients
    config/                     # Application configuration
    middleware/                 # HTTP/gRPC middleware
  pkg/                          # Public reusable packages
    logger/
    errors/
    validator/
  api/                          # API definitions
    openapi/                    # OpenAPI specs
    proto/                      # Protobuf definitions
  deployments/                  # Docker, K8s manifests
  scripts/                      # Build and utility scripts
```

## Technology -> Location Mapping

```markdown
## Tech -> Location Map

### HTTP (Chi/Gin/Echo)
- handlers: internal/adapter/http/handler/
- routes: internal/adapter/http/router.go
- middleware: internal/middleware/
- request/response: internal/adapter/http/dto/

### gRPC
- proto files: api/proto/
- service impl: internal/adapter/grpc/
- generated: internal/adapter/grpc/gen/ (DO NOT MODIFY)

### Database (PostgreSQL/MySQL)
- repository impl: internal/adapter/repository/
- queries: internal/adapter/repository/query/
- migrations: internal/adapter/repository/migration/ (or migrations/)
- sqlc generated: internal/adapter/repository/sqlc/ (DO NOT MODIFY)

### Redis
- cache impl: internal/adapter/cache/
- config: internal/config/redis.go

### Kafka / Message Queue
- consumer: internal/adapter/consumer/
- producer: internal/adapter/producer/ (or within usecase)
- config: internal/config/kafka.go

### Configuration
- struct definitions: internal/config/
- env loading: internal/config/config.go
- .env files: .env, .env.example
```

## Interface -> Implementation Mapping

This is THE critical section for Go projects. Go interfaces are implicit (no `implements` keyword),
so agents cannot find implementations through syntax alone.

```markdown
## Interface -> Implementation Mapping

| Interface (internal/port/)         | Implementation                                    |
|------------------------------------|---------------------------------------------------|
| port.OrderRepository               | adapter/repository/order_postgres.go              |
| port.OrderRepository               | adapter/repository/order_mock.go (test)           |
| port.CacheStore                    | adapter/cache/redis_store.go                      |
| port.EventPublisher                | adapter/producer/kafka_publisher.go               |
| port.PaymentGateway                | adapter/client/stripe_client.go                   |
| port.NotificationSender            | adapter/client/sns_sender.go                      |

To find implementations of an interface:
  grep -r "func.*YourInterface" internal/adapter/
```

## Multiple main.go Entry Points

Go projects commonly have multiple binaries. Index all of them:

```markdown
## Entry Points
| Binary       | Path                    | Purpose                   |
|--------------|-------------------------|---------------------------|
| api-server   | cmd/api-server/main.go  | HTTP/gRPC server          |
| worker       | cmd/worker/main.go      | Background job processor  |
| migrator     | cmd/migrator/main.go    | Database migration runner |
| cli          | cmd/cli/main.go         | Admin CLI tool            |
```

## Generated Code Locations

Go projects generate significant amounts of code. All must be marked:

```markdown
## Generated Files (DO NOT MODIFY)
- internal/adapter/grpc/gen/           # protoc-gen-go output
- internal/adapter/repository/sqlc/    # sqlc generated queries
- internal/wire_gen.go                 # Wire DI (google/wire)
- *_ent.go, ent/                       # Ent ORM generated
- *_mock.go                            # mockgen output
- *_easyjson.go                        # easyjson serializers
- docs/swagger/                        # swag generated docs
```

## internal/ Visibility Boundary

This is a Go-specific concept that agents must understand:

```markdown
## Visibility Rules
- internal/ packages can ONLY be imported by code in the parent directory
- internal/adapter/ cannot be imported by external packages
- pkg/ packages CAN be imported by external projects
- Domain models in internal/domain/ are only accessible within this project
```

## Flat Package Philosophy

Go favors flat packages. Multiple files in the same package share a namespace.
Document the convention:

```markdown
## Flat Package Convention (internal/adapter/repository/)
Files in the same package (not subdirectories):
  order_postgres.go      -- OrderRepository implementation
  order_postgres_test.go -- tests for OrderRepository
  user_postgres.go       -- UserRepository implementation
  user_postgres_test.go  -- tests for UserRepository
  common.go              -- shared helpers within package
```

## Wire / Fx DI Wiring Location

Dependency injection setup is where the whole app is wired together:

```markdown
## DI Wiring
- Wire (google/wire):
  - Provider sets: internal/wire/providers.go
  - Injector: internal/wire/injector.go
  - Generated: internal/wire/wire_gen.go (DO NOT MODIFY)

- Fx (uber-go/fx):
  - Module definitions: internal/module/
  - App construction: cmd/api-server/main.go (fx.New(...))
```

## Auto-Extracting Structure from go.mod

```bash
# Get module name
head -1 go.mod | awk '{print $2}'

# List all packages
go list ./...

# List all entry points
find cmd -name main.go -type f

# Find all interfaces in port/
grep -rn "type.*interface" internal/port/
```

Script to generate interface mapping:

```bash
#!/bin/bash
echo "## Interface -> Implementation Mapping"
echo ""
echo "| Interface | Implementation |"
echo "|-----------|----------------|"

# For each interface in port/
grep -rn "type .* interface" internal/port/ | while IFS=: read -r file line content; do
  iface=$(echo "$content" | sed 's/type //;s/ interface.*//')
  # Find implementations
  grep -rl "func.*$iface" internal/adapter/ 2>/dev/null | while read -r impl; do
    echo "| $iface | ${impl#internal/} |"
  done
done
```

## Complete 3-Tier Example

### Part 1: Root CLAUDE.md

```markdown
# Project: order-platform (Go 1.22 / Chi / Wire / PostgreSQL / Kafka)

## Entry Points
| Binary       | Path                    | Purpose                   |
|--------------|-------------------------|---------------------------|
| api-server   | cmd/api-server/main.go  | HTTP/gRPC server          |
| worker       | cmd/worker/main.go      | Background job processor  |
| migrator     | cmd/migrator/main.go    | Database migration runner |

## Interface -> Implementation
| Interface (internal/port/)  | Implementation                               |
|-----------------------------|----------------------------------------------|
| port.OrderRepository        | adapter/repository/order_postgres.go         |
| port.OrderRepository        | adapter/repository/order_mock.go (test)      |
| port.CacheStore             | adapter/cache/redis_store.go                 |
| port.EventPublisher         | adapter/producer/kafka_publisher.go          |
| port.PaymentGateway         | adapter/client/stripe_client.go              |

## Name Disambiguation
| Short Name  | Canonical Path                          | Note                        |
|-------------|-----------------------------------------|-----------------------------|
| Order       | internal/domain/order.go                | Domain aggregate root       |
| OrderDTO    | internal/adapter/http/dto/order.go      | HTTP request/response       |
| OrderEvent  | internal/adapter/producer/order_event.go| Kafka event schema          |

## DI Wiring
- Wire providers: internal/wire/providers.go
- Injector: internal/wire/injector.go
- Generated: internal/wire/wire_gen.go (DO NOT MODIFY)

## Generated Files (DO NOT MODIFY)
- internal/adapter/grpc/gen/        (protoc-gen-go)
- internal/adapter/repository/sqlc/ (sqlc)
- internal/wire/wire_gen.go         (Wire)
- *_mock.go                         (mockgen)
- docs/swagger/                     (swag)

## Rules
See .claude/rules/ for technology-specific guidelines:
- postgresql.md -- DB schema conventions, migration rules, query patterns
- kafka.md      -- Topic naming, consumer group policies, event schema
- chi.md        -- Router structure, middleware ordering, handler patterns
```

### Part 2: .claude/rules/postgresql.md

```markdown
---
paths:
  - internal/adapter/repository/**
  - migrations/**
  - internal/adapter/repository/sqlc/**
---

## PostgreSQL Conventions

### Tech -> Location
- repository impl: internal/adapter/repository/
- sqlc queries: internal/adapter/repository/query/*.sql
- sqlc generated: internal/adapter/repository/sqlc/ (DO NOT MODIFY)
- migrations: migrations/ (goose format, sequential numbering)

### Schema Rules
- Table names: snake_case, plural (e.g. orders, order_items)
- Primary keys: UUID v7 (`id uuid PRIMARY KEY DEFAULT gen_ulid()`)
- Timestamps: `created_at TIMESTAMPTZ NOT NULL DEFAULT now()`, `updated_at TIMESTAMPTZ`
- Soft delete: `deleted_at TIMESTAMPTZ` with partial index `WHERE deleted_at IS NULL`
- Foreign keys: always indexed, named `fk_{table}_{ref_table}`

### Migration Rules
- One migration per PR; never modify an applied migration
- Always provide both up and down SQL
- Test rollback locally: `make migrate-down && make migrate-up`

### Query Patterns (sqlc)
- Define queries in internal/adapter/repository/query/*.sql
- Run `make sqlc` after editing; never edit sqlc/ output directly
- Use `:one`, `:many`, `:exec` annotations per sqlc convention
- Batch inserts: use `unnest` array parameter pattern

### Testing
- Integration tests use testcontainers-go with PostgreSQL 16
- Test fixtures: internal/adapter/repository/testdata/
- Each test function gets a fresh schema via `t.Cleanup(migrate.Down)`
```
