# Spring Hexagonal Architecture -- Inverted Index Guide

Kotlin/Java multi-module projects using Spring Boot with Hexagonal (Ports & Adapters) architecture.
This is the most structurally complex pattern: the same domain concept touches 5-8 Gradle modules.

## Typical Module Structure

```
project-root/
  settings.gradle.kts          # Module registry (auto-extract from here)
  build.gradle.kts              # Root build, shared plugins
  domain/                       # Pure domain models, NO Spring dependency
  application/                  # Use cases, port interfaces, DTOs
  inbound-api/                  # REST/gRPC controllers (driving adapters)
  inbound-consumer/             # Kafka/SQS consumers (driving adapters)
  outbound-persistence/         # JPA/R2DBC repositories (driven adapters)
  outbound-event/               # Kafka producers, event publishers
  outbound-client/              # External API clients (WebClient, Feign)
  outbound-cache/               # Redis/Caffeine cache adapters
  outbound-search/              # Elasticsearch adapters
  infrastructure/               # Spring config, security, observability
  support/                      # Shared utilities, common exceptions
```

## Technology -> Location Mapping

This is the core inverted index. Group by technology, not by layer.

```markdown
## Tech -> Location Map

### Kafka
- consumer: inbound-consumer/src/main/kotlin/.../listener/
- producer: outbound-event/src/main/kotlin/.../producer/
- config: inbound-consumer/.../config/KafkaConsumerConfig.kt
         outbound-event/.../config/KafkaProducerConfig.kt
- topics: infrastructure/.../config/KafkaTopicConfig.kt
- error handling: inbound-consumer/.../listener/ErrorHandler.kt

### JPA / Database
- entities: outbound-persistence/.../entity/
- repositories: outbound-persistence/.../repository/
- query DSL: outbound-persistence/.../repository/custom/
- migrations: outbound-persistence/src/main/resources/db/migration/
- config: outbound-persistence/.../config/JpaConfig.kt

### Redis
- adapter: outbound-cache/.../adapter/
- config: outbound-cache/.../config/RedisConfig.kt
- serializer: outbound-cache/.../serializer/

### Elasticsearch
- adapter: outbound-search/.../adapter/
- index config: outbound-search/.../config/ElasticsearchConfig.kt
- query builder: outbound-search/.../query/

### gRPC
- proto files: inbound-api/src/main/proto/
- service impl: inbound-api/.../grpc/
- generated: inbound-api/build/generated/source/proto/ (DO NOT MODIFY)

### Security
- filters: infrastructure/.../security/filter/
- config: infrastructure/.../security/SecurityConfig.kt
- jwt: infrastructure/.../security/jwt/
```

## Port/Adapter Location Pattern

The hexagonal pattern splits interfaces (ports) from implementations (adapters).
This mapping is critical because agents constantly cross this boundary.

```markdown
## Port -> Adapter Mapping

| Port (application module)                    | Adapter (outbound-* module)                        |
|----------------------------------------------|----------------------------------------------------|
| application/.../port/out/OrderRepository     | outbound-persistence/.../adapter/OrderJpaAdapter   |
| application/.../port/out/EventPublisher      | outbound-event/.../adapter/KafkaEventAdapter       |
| application/.../port/out/CacheStore          | outbound-cache/.../adapter/RedisCacheAdapter       |
| application/.../port/out/SearchEngine        | outbound-search/.../adapter/ElasticSearchAdapter   |
| application/.../port/out/PaymentClient       | outbound-client/.../adapter/PaymentFeignAdapter    |
| application/.../port/in/CreateOrderUseCase   | inbound-api/.../controller/OrderController         |
```

## Hexagonal-Specific Pain Points

### Same Concept Across 5-8 Modules

An "Order" domain concept may appear in:
1. `domain/` -- Order.kt (aggregate root)
2. `application/` -- CreateOrderUseCase.kt, OrderPort.kt
3. `inbound-api/` -- OrderController.kt, OrderRequest.kt
4. `inbound-consumer/` -- OrderEventListener.kt
5. `outbound-persistence/` -- OrderEntity.kt, OrderJpaAdapter.kt
6. `outbound-event/` -- OrderEventProducer.kt
7. `outbound-cache/` -- OrderCacheAdapter.kt
8. `outbound-search/` -- OrderSearchAdapter.kt

Index the module-level paths so the agent can narrow quickly.

### Deep Package Paths

Spring Hexagonal projects have verbose paths like:
```
com.company.project.module.adapter.out.persistence.entity.OrderEntity
```

Always show the shortened form in CLAUDE.md:
```
outbound-persistence/.../entity/    (not the full package path)
```

## Config File Locations

```markdown
## Config Files
- application.yml: infrastructure/src/main/resources/
- application-{profile}.yml: infrastructure/src/main/resources/
- logback-spring.xml: infrastructure/src/main/resources/
- Flyway migrations: outbound-persistence/src/main/resources/db/migration/
- Kafka topic definitions: infrastructure/.../config/KafkaTopicConfig.kt
```

## Auto-Extracting Module List from Gradle

Use `settings.gradle.kts` as the source of truth for module names:

```bash
# Extract all module includes from settings.gradle.kts
grep 'include(' settings.gradle.kts | sed 's/include("//;s/")//' | sort
```

Sample `settings.gradle.kts`:
```kotlin
rootProject.name = "order-service"

include("domain")
include("application")
include("inbound-api")
include("inbound-consumer")
include("outbound-persistence")
include("outbound-event")
include("outbound-cache")
include("infrastructure")
include("support")
```

Script to generate the module structure section automatically:

```bash
#!/bin/bash
echo "## Module Structure"
echo '```'
grep 'include(' settings.gradle.kts | while read -r line; do
  module=$(echo "$line" | sed 's/include("//;s/")//')
  echo "  $module/"
  # Show top-level packages
  src="$module/src/main/kotlin"
  if [ -d "$src" ]; then
    find "$src" -maxdepth 5 -type d | tail -n +2 | head -5 | sed 's|^|    |'
  fi
done
echo '```'
```

## .claude/rules/ Breakdown for Spring Hexagonal

Split technology-specific guidance into auto-loaded rule files.
Each file uses `paths:` frontmatter so rules auto-activate only when the agent touches matching files.

**kafka.md**
```markdown
---
paths:
  - "**/inbound-consumer/**"
  - "**/outbound-event/**"
  - "**/KafkaTopicConfig.kt"
---

# Kafka Conventions

## Consumer
- Listener class → inbound-consumer/.../listener/
- One @KafkaListener per topic, method name = handle{EventName}
- Error handling: use DefaultErrorHandler with FixedBackOff, dead-letter to {topic}.DLT
- Deserialization: JsonDeserializer with trusted packages in KafkaConsumerConfig

## Producer
- Producer class → outbound-event/.../producer/
- Always use KafkaTemplate<String, AvroSpecificRecord> (not JSON)
- Topic names: constant in KafkaTopicConfig.kt, never inline strings
- Transactional outbox: if eventual consistency required, write to outbox table first
```

**jpa.md**
```markdown
---
paths:
  - "**/outbound-persistence/**"
  - "**/entity/**"
  - "**/repository/**"
  - "**/db/migration/**"
---

# JPA / Database Conventions

- Entities in outbound-persistence/.../entity/, never expose to domain layer
- Map Entity <-> Domain model in adapter, not in entity itself
- QueryDSL custom repos: outbound-persistence/.../repository/custom/
- Flyway migrations: V{yyyyMMddHHmm}__{description}.sql, never modify existing
```

**redis.md**
```markdown
---
paths:
  - "**/outbound-cache/**"
---

# Redis Conventions

- Adapter in outbound-cache/.../adapter/, implements port from application module
- Key format: {service}:{entity}:{id}, TTL always explicit
- Serializer: outbound-cache/.../serializer/, use Jackson (not JDK serialization)
```

**security.md**
```markdown
---
paths:
  - "**/security/**"
  - "**/filter/**"
---

# Security Conventions

- Config: infrastructure/.../security/SecurityConfig.kt
- JWT processing: infrastructure/.../security/jwt/
- Custom filters: infrastructure/.../security/filter/, register order explicitly
```

**grpc.md**
```markdown
---
paths:
  - "**/proto/**"
  - "**/grpc/**"
---

# gRPC Conventions

- Proto files: inbound-api/src/main/proto/
- Generated code: inbound-api/build/generated/source/proto/ (DO NOT MODIFY)
- Service impl: inbound-api/.../grpc/, extend generated abstract class
```

Each rule file contains adapter-specific conventions, naming patterns,
and common pitfalls that the agent needs only when working in that area.

## Complete 3-Tier Example

### Part 1: Root CLAUDE.md (minimal, ~40 lines)

The root CLAUDE.md contains only structural information and cross-cutting references.
Technology-specific details live in `.claude/rules/` files.

```markdown
# Order Service

Kotlin/Spring Boot hexagonal architecture. 9 Gradle modules.

## Module Structure
- domain/          -- Aggregate roots, value objects (NO Spring dependency)
- application/     -- Use cases, port interfaces, DTOs
- inbound-api/     -- REST/gRPC controllers (driving adapters)
- inbound-consumer/ -- Kafka consumers (driving adapters)
- outbound-persistence/ -- JPA repositories (driven adapters)
- outbound-event/  -- Kafka producers
- outbound-cache/  -- Redis adapters
- outbound-search/ -- Elasticsearch adapters
- infrastructure/  -- Spring config, security, observability
- support/         -- Shared utilities

## Name Disambiguation
- Order (domain/) vs OrderEntity (outbound-persistence/) vs OrderRequest (inbound-api/)
- EventPublisher (application port) vs KafkaEventAdapter (outbound-event impl)

## Port -> Adapter Quick Reference
| Port (application/.../port/) | Adapter Module         |
|-------------------------------|------------------------|
| out/OrderRepository           | outbound-persistence   |
| out/EventPublisher            | outbound-event         |
| out/CacheStore                | outbound-cache         |
| in/CreateOrderUseCase         | inbound-api            |

## Entry Points
- API: inbound-api/.../Application.kt
- Consumer: inbound-consumer/.../Application.kt

## Generated Files (DO NOT MODIFY)
- inbound-api/build/generated/source/proto/
- outbound-persistence/build/generated/querydsl/

## Rules
Technology-specific conventions are in .claude/rules/:
kafka.md, jpa.md, redis.md, security.md, grpc.md
```

### Part 2: .claude/rules/kafka.md (complete example)

This shows a full rules file with `paths:` frontmatter for auto-activation.

```markdown
---
paths:
  - "**/inbound-consumer/**"
  - "**/outbound-event/**"
  - "**/KafkaTopicConfig.kt"
---

# Kafka Conventions

## Tech -> Location
- consumer: inbound-consumer/.../listener/
- producer: outbound-event/.../producer/
- consumer config: inbound-consumer/.../config/KafkaConsumerConfig.kt
- producer config: outbound-event/.../config/KafkaProducerConfig.kt
- topic definitions: infrastructure/.../config/KafkaTopicConfig.kt
- error handling: inbound-consumer/.../listener/ErrorHandler.kt

## Consumer Rules
- One @KafkaListener per topic, method name = handle{EventName}
- Error handling: DefaultErrorHandler with FixedBackOff(interval=1000, maxAttempts=3)
- Dead-letter: publish to {topic}.DLT on exhausted retries
- Deserialization: JsonDeserializer, trusted packages in KafkaConsumerConfig
- Idempotency: check event ID before processing (use Redis or DB unique constraint)

## Producer Rules
- Use KafkaTemplate<String, AvroSpecificRecord> (not JSON in prod)
- Topic names: always reference constants from KafkaTopicConfig.kt, never inline strings
- Key strategy: use aggregate ID as partition key for ordering guarantees
- Transactional outbox: for critical events, write to outbox table first

## Testing
- Integration tests: use @EmbeddedKafka, bootstrap servers from test properties
- Consumer test: publish event -> assert side effect (DB state or mock call)
- Producer test: inject MockProducer or capture via @EmbeddedKafka consumer
```
