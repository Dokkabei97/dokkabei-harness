# Multi-Language Monorepo -- Inverted Index Guide

Polyglot monorepos with multiple services in different languages sharing contracts and infrastructure.
Cross-service domain mapping is the killer feature: agents must know which domain concept
lives in which service and in which language.

## Typical Polyglot Monorepo Structure

```
project-root/
  proto/                        # Shared Protobuf/OpenAPI contracts
    order/v1/order.proto
    user/v1/user.proto
    common/v1/types.proto
  services/
    order-api/                  # Kotlin Spring Boot
    user-api/                   # Go Gin/Chi
    notification/               # TypeScript NestJS
    analytics/                  # Python FastAPI
    payment/                    # Rust Axum
    gateway/                    # TypeScript Next.js (BFF)
  packages/                     # Shared TypeScript packages
    ts-proto-gen/               # Generated TS types from proto
    shared-types/               # Cross-frontend shared types
  libs/                         # Shared Go/Kotlin libraries
    go-common/                  # Shared Go utilities
    kt-common/                  # Shared Kotlin utilities
  infra/
    terraform/                  # IaC (Terraform/Pulumi)
    k8s/                        # Kubernetes manifests
    docker/                     # Dockerfiles per service
    helm/                       # Helm charts
  .github/workflows/            # CI/CD pipelines
  docker-compose.yml            # Local development
```

## Cross-Service Domain Mapping Table

This is the most important section. Shows which domain concept lives where.

```markdown
## Domain x Service Matrix

| Domain    | API Service          | Event Consumer       | Data Store         | Search         |
|-----------|----------------------|----------------------|--------------------|----------------|
| Order     | order-api (Kotlin)   | order-api (Kafka)    | PostgreSQL         | Elasticsearch  |
| User      | user-api (Go)        | user-api (NATS)      | PostgreSQL         | --             |
| Payment   | payment (Rust)       | payment (Kafka)      | PostgreSQL         | --             |
| Notify    | notification (TS)    | notification (SQS)   | DynamoDB           | --             |
| Analytics | analytics (Python)   | analytics (Kafka)    | ClickHouse         | --             |
| Auth      | user-api (Go)        | --                   | Redis + PostgreSQL | --             |
```

## Shared Contract Locations

```markdown
## Shared Contracts

### Protobuf
- definitions: proto/{domain}/v{n}/{domain}.proto
- common types: proto/common/v1/types.proto
- generated (Kotlin): services/order-api/build/generated/source/proto/ (DO NOT MODIFY)
- generated (Go): services/user-api/internal/gen/proto/ (DO NOT MODIFY)
- generated (TypeScript): packages/ts-proto-gen/src/ (DO NOT MODIFY)
- generated (Rust): services/payment/src/proto_gen/ (DO NOT MODIFY)
- generated (Python): services/analytics/src/generated/ (DO NOT MODIFY)

### OpenAPI
- specs: proto/openapi/{service}.yaml
- generated clients: packages/ts-proto-gen/src/openapi/ (DO NOT MODIFY)

### Shared Events (Async)
- event schemas: proto/events/{domain}_events.proto
- Avro schemas (if used): proto/avro/{domain}.avsc
```

## Per-Service Technology Stack Table

```markdown
## Service Tech Stack

| Service       | Language   | Framework       | DB          | Queue   | Cache  | Port  |
|---------------|------------|-----------------|-------------|---------|--------|-------|
| order-api     | Kotlin     | Spring Boot     | PostgreSQL  | Kafka   | Redis  | 8080  |
| user-api      | Go         | Chi             | PostgreSQL  | NATS    | Redis  | 8081  |
| notification  | TypeScript | NestJS          | DynamoDB    | SQS     | --     | 8082  |
| analytics     | Python     | FastAPI         | ClickHouse  | Kafka   | --     | 8083  |
| payment       | Rust       | Axum            | PostgreSQL  | Kafka   | --     | 8084  |
| gateway       | TypeScript | Next.js         | --          | --      | Redis  | 3000  |
```

## Generated Code Mapping (Proto -> Language)

```markdown
## Proto Generation Pipeline

proto/order/v1/order.proto generates:
  -> services/order-api/build/generated/.../OrderProto.kt     (protoc-gen-grpc-kotlin)
  -> services/user-api/internal/gen/proto/order/v1/order.pb.go (protoc-gen-go)
  -> packages/ts-proto-gen/src/order/v1/order.ts              (ts-proto)
  -> services/payment/src/proto_gen/order.rs                  (prost)
  -> services/analytics/src/generated/order_pb2.py            (grpcio-tools)

Regenerate all: make proto-gen (or buf generate)
Regenerate single: buf generate --path proto/order/
```

## CI/CD Pipeline Mapping

```markdown
## CI Workflow -> Service Mapping

| Workflow File                      | Triggers On                          | Deploys            |
|------------------------------------|--------------------------------------|--------------------|
| .github/workflows/order-api.yml   | services/order-api/**, proto/order/**| order-api          |
| .github/workflows/user-api.yml    | services/user-api/**, proto/user/**  | user-api           |
| .github/workflows/notification.yml| services/notification/**             | notification       |
| .github/workflows/analytics.yml   | services/analytics/**                | analytics          |
| .github/workflows/payment.yml     | services/payment/**                  | payment            |
| .github/workflows/gateway.yml     | services/gateway/**, packages/**     | gateway            |
| .github/workflows/proto.yml       | proto/**                             | regenerates all    |
| .github/workflows/infra.yml       | infra/**                             | Terraform apply    |

## Change Impact
- proto/ changes trigger ALL service rebuilds
- packages/ changes trigger gateway + notification (TypeScript services)
- libs/go-common/ changes trigger user-api
- libs/kt-common/ changes trigger order-api
```

## Docker / K8s Manifest Locations

```markdown
## Infrastructure Files

### Docker
- per-service: infra/docker/{service}/Dockerfile
- compose (local): docker-compose.yml
- compose (test): docker-compose.test.yml
- base images: infra/docker/base/

### Kubernetes
- namespaces: infra/k8s/base/namespace.yaml
- per-service: infra/k8s/services/{service}/
  - deployment.yaml
  - service.yaml
  - configmap.yaml
  - hpa.yaml
- shared: infra/k8s/shared/
  - ingress.yaml
  - network-policy.yaml
  - secrets (sealed): infra/k8s/sealed-secrets/

### Helm (if used instead of raw K8s)
- charts: infra/helm/charts/{service}/
- values: infra/helm/values/{environment}/{service}.yaml

### Terraform / IaC
- modules: infra/terraform/modules/
- environments: infra/terraform/environments/{env}/
- state config: infra/terraform/backend.tf
```

## Cross-Service Communication Map

```markdown
## Service Communication

| From           | To             | Method     | Contract                       |
|----------------|----------------|------------|--------------------------------|
| gateway        | order-api      | REST/gRPC  | proto/order/v1/order.proto     |
| gateway        | user-api       | REST/gRPC  | proto/user/v1/user.proto       |
| order-api      | payment        | gRPC       | proto/payment/v1/payment.proto |
| order-api      | notification   | Kafka      | proto/events/order_events.proto|
| payment        | notification   | Kafka      | proto/events/payment_events.proto|
| analytics      | (all)          | Kafka      | consumes all domain events     |
```

## Auto-Extraction for Polyglot Repos

```bash
#!/bin/bash
echo "## Per-Service Structure"

for svc_dir in services/*/; do
  svc=$(basename "$svc_dir")
  echo ""
  echo "### $svc"

  # Detect language
  if [ -f "$svc_dir/build.gradle.kts" ] || [ -f "$svc_dir/pom.xml" ]; then
    echo "Language: Kotlin/Java"
  elif [ -f "$svc_dir/go.mod" ]; then
    echo "Language: Go"
  elif [ -f "$svc_dir/package.json" ]; then
    echo "Language: TypeScript"
  elif [ -f "$svc_dir/pyproject.toml" ] || [ -f "$svc_dir/setup.py" ]; then
    echo "Language: Python"
  elif [ -f "$svc_dir/Cargo.toml" ]; then
    echo "Language: Rust"
  fi

  # Show top-level structure
  ls -1 "$svc_dir/src/" 2>/dev/null | head -10 | sed 's/^/  /'
done
```

## Complete 3-Tier Example

### Part 1: Root CLAUDE.md

```markdown
## Domain x Service Matrix

| Domain   | API Service         | Event Consumer      | Data Store        | Search        |
|----------|---------------------|---------------------|-------------------|---------------|
| Order    | order-api (Kotlin)  | order-api (Kafka)   | PostgreSQL        | Elasticsearch |
| User     | user-api (Go)       | user-api (NATS)     | PostgreSQL        | --            |
| Payment  | payment (Rust)      | payment (Kafka)     | PostgreSQL        | --            |
| Notify   | notification (TS)   | notification (SQS)  | DynamoDB          | --            |
| Analytics| analytics (Python)  | analytics (Kafka)   | ClickHouse        | --            |
| Auth     | user-api (Go)       | --                  | Redis + PostgreSQL| --            |

## Tech Stack Quick Reference

| Service       | Language   | Framework   | DB         | Queue | Cache | Port |
|---------------|------------|-------------|------------|-------|-------|------|
| order-api     | Kotlin     | Spring Boot | PostgreSQL | Kafka | Redis | 8080 |
| user-api      | Go         | Chi         | PostgreSQL | NATS  | Redis | 8081 |
| notification  | TypeScript | NestJS      | DynamoDB   | SQS   | --    | 8082 |
| analytics     | Python     | FastAPI     | ClickHouse | Kafka | --    | 8083 |
| payment       | Rust       | Axum        | PostgreSQL | Kafka | --    | 8084 |
| gateway       | TypeScript | Next.js     | --         | --    | Redis | 3000 |

## Shared Contracts
- protobuf definitions: proto/{domain}/v{n}/
- event schemas: proto/events/{domain}_events.proto
- generated code: DO NOT MODIFY (see per-service gen/ directories)
- regenerate all: make proto-gen
- regenerate single: buf generate --path proto/{domain}/
- details -> .claude/rules/proto-contracts.md

## CI Pipelines
- proto/** changes -> ALL services rebuild
- services/{svc}/** changes -> only that service
- packages/** changes -> gateway + notification (TypeScript services)
- libs/go-common/** -> user-api, libs/kt-common/** -> order-api
- details -> .github/workflows/

## Entry Points
- order-api: services/order-api/src/main/kotlin/.../Application.kt
- user-api: services/user-api/cmd/server/main.go
- notification: services/notification/src/main.ts
- analytics: services/analytics/src/main.py
- payment: services/payment/src/main.rs
- gateway: services/gateway/src/app/layout.tsx

## Rules
- Proto contracts & generated code -> .claude/rules/proto-contracts.md
- Per-service conventions -> .claude/rules/{service}.md
- Infrastructure & deployment -> .claude/rules/infra.md
```

### Part 2: .claude/rules/proto-contracts.md

```markdown
---
description: Proto contract definitions, code generation pipeline, and generated code policies
globs:
  - "proto/**"
  - "**/gen/**"
  - "**/generated/**"
---

## Proto Generation Pipeline

proto/order/v1/order.proto generates:
  -> services/order-api/build/generated/.../OrderProto.kt     (protoc-gen-grpc-kotlin)
  -> services/user-api/internal/gen/proto/order/v1/order.pb.go (protoc-gen-go)
  -> packages/ts-proto-gen/src/order/v1/order.ts              (ts-proto)
  -> services/payment/src/proto_gen/order.rs                  (prost)
  -> services/analytics/src/generated/order_pb2.py            (grpcio-tools)

Regenerate all: make proto-gen (or buf generate)
Regenerate single: buf generate --path proto/order/

## Generated Code Mapping

| Proto Source                     | Kotlin (order-api)                                  | Go (user-api)                                  | TypeScript                              | Rust (payment)                      | Python (analytics)                     |
|----------------------------------|-----------------------------------------------------|-------------------------------------------------|-----------------------------------------|-------------------------------------|----------------------------------------|
| proto/order/v1/order.proto       | build/generated/.../OrderProto.kt                   | internal/gen/proto/order/v1/order.pb.go         | packages/ts-proto-gen/src/order/v1/     | src/proto_gen/order.rs              | src/generated/order_pb2.py             |
| proto/user/v1/user.proto         | build/generated/.../UserProto.kt                    | internal/gen/proto/user/v1/user.pb.go           | packages/ts-proto-gen/src/user/v1/      | src/proto_gen/user.rs               | src/generated/user_pb2.py              |
| proto/common/v1/types.proto      | build/generated/.../TypesProto.kt                   | internal/gen/proto/common/v1/types.pb.go        | packages/ts-proto-gen/src/common/v1/    | src/proto_gen/types.rs              | src/generated/types_pb2.py             |
| proto/events/{domain}_events.proto| build/generated/.../{Domain}EventsProto.kt          | internal/gen/proto/events/{domain}.pb.go        | packages/ts-proto-gen/src/events/       | src/proto_gen/{domain}_events.rs    | src/generated/{domain}_events_pb2.py   |

## Rules
- NEVER modify files under gen/, generated/, build/generated/ directories
- Always edit the .proto source, then regenerate
- Proto changes trigger ALL service CI pipelines
- Version bumps (v1 -> v2) require updating all service consumers
- Use buf lint before committing proto changes
```
