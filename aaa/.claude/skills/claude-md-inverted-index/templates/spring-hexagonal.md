---
name: spring-hexagonal
target-stack: Kotlin/Java Spring Boot Hexagonal Architecture
placeholders: ["{base_package}"]
---

# Spring Hexagonal -- Inverted Index Template

## Part 1: PROJECT_ROOT/CLAUDE.md

Copy this section to your project root's `CLAUDE.md` (not `~/.claude/CLAUDE.md`).
Replace `{base_package}` with your actual package path (e.g., `com.acme.orders`).

```markdown
## Architecture: Hexagonal (Ports & Adapters)

### Module Structure
- **domain** -- Ports, domain services, domain events. No framework dependencies.
- **inbound-api** -- REST controllers, DTOs, security filters.
- **inbound-consumer** -- Kafka consumers, message listeners.
- **outbound-persistence** -- JPA entities, repositories, DB migrations.
- **outbound-event** -- Kafka producers, event publishing.
- **outbound-cache** -- Redis adapters, cache config.
- **outbound-search** -- Elasticsearch documents, search adapters.
- **outbound-client** -- gRPC/HTTP external clients, proto files.

### Name Disambiguation
| Name            | Module               | Meaning                        |
|-----------------|----------------------|--------------------------------|
| Order           | domain               | Domain aggregate root          |
| OrderEntity     | outbound-persistence | JPA entity (DB representation) |
| OrderDocument   | outbound-search      | Elasticsearch document         |
| OrderEvent      | domain/event         | Domain event payload           |
| OrderDto        | inbound-api/dto      | API request/response DTO       |

### Generated Files (DO NOT MODIFY)
- **/build/generated/ -- Proto stubs, QueryDSL Q-classes, MapStruct impls
- **/build/ -- All build output

### Detailed Conventions
See `.claude/rules/` for per-technology location maps and conventions.
```

---

## Part 2: PROJECT_ROOT/.claude/rules/ Files

Create each file below in your project's `.claude/rules/` directory (not `~/.claude/rules/`).
Replace `{base_package}` with your actual package path.

---

### File: hexagonal-ports.md

```yaml
---
description: "Hexagonal architecture port/adapter mapping and dependency rules"
paths: ["**/domain/**", "**/port/**", "**/service/**"]
---
```

```markdown
## Hexagonal Ports & Adapters

### Port Locations (domain module)
- inbound (use-case): domain/src/main/kotlin/{base_package}/port/inbound/
- outbound (SPI): domain/src/main/kotlin/{base_package}/port/outbound/
- domain-service: domain/src/main/kotlin/{base_package}/service/

### Port/Adapter Mapping
| Port (domain)         | Adapter (outbound-*)        | Module               |
|-----------------------|-----------------------------|----------------------|
| PersistencePort       | JpaPersistenceAdapter       | outbound-persistence |
| CachePort             | RedisCacheAdapter           | outbound-cache       |
| SearchPort            | ElasticSearchAdapter        | outbound-search      |
| EventPublishPort      | KafkaEventAdapter           | outbound-event       |
| ExternalServicePort   | GrpcClientAdapter           | outbound-client      |

### Dependency Rules
- Ports are interfaces defined in the domain module.
- Outbound ports are implemented by adapters in outbound-* modules.
- Inbound ports (use-cases) are implemented by domain services.
- Domain module MUST NOT import from any adapter module.
- All outbound port implementations should be annotated @Adapter (or @Component).
- Config classes must be in the config/ package of their respective module.
```

---

### File: kafka.md

```yaml
---
description: "Kafka consumer/producer conventions and locations"
paths: ["**/inbound-consumer/**", "**/outbound-event/**", "**/event/**"]
---
```

```markdown
## Kafka

### Location Map
- consumer: inbound-consumer/src/main/kotlin/{base_package}/consumer/
- producer: outbound-event/src/main/kotlin/{base_package}/producer/
- consumer config: inbound-consumer/src/main/kotlin/{base_package}/config/KafkaConsumerConfig.kt
- producer config: outbound-event/src/main/kotlin/{base_package}/config/KafkaProducerConfig.kt
- event model: domain/src/main/kotlin/{base_package}/event/

### Conventions
- Event classes live in the domain module (framework-agnostic).
- Consumers deserialize into domain events, then call inbound ports.
- Producers accept domain events from outbound ports, serialize, and publish.
- If using Avro/Protobuf schemas: outbound-event/src/main/avro/
```

---

### File: jpa.md

```yaml
---
description: "JPA entity, repository, and migration locations"
paths: ["**/outbound-persistence/**", "**/entity/**", "**/repository/**", "**/db/migration/**"]
---
```

```markdown
## JPA / Persistence

### Location Map
- entity: outbound-persistence/src/main/kotlin/{base_package}/entity/
- repository: outbound-persistence/src/main/kotlin/{base_package}/repository/
- config: outbound-persistence/src/main/kotlin/{base_package}/config/JpaConfig.kt
- migration: outbound-persistence/src/main/resources/db/migration/

### Conventions
- Flyway migration naming: V{version}__{description}.sql
- Entity classes are suffixed with Entity (e.g., OrderEntity).
- Repositories implement outbound PersistencePort from domain module.
- QueryDSL generated Q-classes: build/generated/ (DO NOT MODIFY)
```

---

### File: redis.md

```yaml
---
description: "Redis cache adapter conventions and locations"
paths: ["**/outbound-cache/**"]
---
```

```markdown
## Redis / Cache

### Location Map
- adapter: outbound-cache/src/main/kotlin/{base_package}/adapter/
- config: outbound-cache/src/main/kotlin/{base_package}/config/RedisConfig.kt
- port: domain/src/main/kotlin/{base_package}/port/outbound/CachePort.kt

### Conventions
- Cache adapter implements CachePort defined in the domain module.
- Cache keys should follow a consistent naming pattern: {domain}:{id}
- TTL configuration belongs in RedisConfig, not in adapter logic.
```

---

### File: elasticsearch.md

```yaml
---
description: "Elasticsearch document, adapter, and config locations"
paths: ["**/outbound-search/**", "**/document/**"]
---
```

```markdown
## Elasticsearch / Search

### Location Map
- adapter: outbound-search/src/main/kotlin/{base_package}/repository/
- document: outbound-search/src/main/kotlin/{base_package}/document/
- config: outbound-search/src/main/kotlin/{base_package}/config/ElasticConfig.kt

### Conventions
- Document classes are suffixed with Document (e.g., OrderDocument).
- Search adapter implements SearchPort from the domain module.
- Index mapping and settings belong in config or resource files.
```

---

### File: grpc.md

```yaml
---
description: "gRPC client, proto, and config locations"
paths: ["**/outbound-client/**", "**/proto/**"]
---
```

```markdown
## gRPC / External Clients

### Location Map
- client: outbound-client/src/main/kotlin/{base_package}/client/
- proto: outbound-client/src/main/proto/
- config: outbound-client/src/main/kotlin/{base_package}/config/GrpcConfig.kt

### Conventions
- Proto-generated stubs land in build/generated/source/proto/ (DO NOT MODIFY).
- Client adapters implement ExternalServicePort from domain module.
- Channel and stub configuration belongs in GrpcConfig.
```

---

### File: security.md

```yaml
---
description: "Security filter, handler, and auth config locations"
paths: ["**/security/**", "**/config/SecurityConfig**"]
---
```

```markdown
## Security

### Location Map
- filter + handler: inbound-api/src/main/kotlin/{base_package}/security/
- config: inbound-api/src/main/kotlin/{base_package}/config/SecurityConfig.kt
- port: domain/src/main/kotlin/{base_package}/port/inbound/AuthPort.kt

### Conventions
- Security filters and handlers live in the inbound-api module.
- Authentication/authorization logic that is domain-specific goes through AuthPort.
- Framework-specific security config (CORS, CSRF, filter chain) stays in SecurityConfig.
```
