---
name: arch-review-guide
description: Use this skill when reviewing or working on project architecture. Provides quick reference for architecture violation detection, dependency direction rules, and structural health assessment across Kotlin, Python, and TypeScript/JavaScript.
---

# Architecture Review Quick Reference

This skill provides a condensed checklist for identifying architecture violations during code review or development.

## When to Activate

- Reviewing code that changes project structure or adds new modules
- Working with dependency injection, layer boundaries, or module dependencies
- Creating new packages, directories, or modules
- Refactoring architecture (extracting services, separating layers)
- Reviewing import statements for dependency direction compliance
- Evaluating DTO/Entity separation or data flow patterns
- Assessing microservice communication patterns

## Core Principles

### 1. Dependencies Flow Inward
Outer layers depend on inner layers, never the reverse. Domain/core has zero outward dependencies.

```
[Controller/API] --> [Service/UseCase] --> [Domain/Entity] --> [nothing]
     ^                     ^                    ^
     |                     |                    |
[Infrastructure]    [Infrastructure]      [NEVER depends on outer]
```

### 2. Detect, Don't Prescribe
Report the detected architecture style. Don't force hexagonal on a simple CRUD app. Match analysis to project maturity.

### 3. Context Matters
Read surrounding code before flagging. A pattern that looks bad in isolation may be an intentional trade-off.

## 6-Step Analysis Workflow

| Step | Name | What to Check |
|------|------|--------------|
| 1 | Macro Structure Discovery | Build configs, module composition, project type |
| 2 | Dependency Direction Tracking | Import analysis, layer violation detection |
| 3 | Package Structure & Naming | Naming conventions, package-by-layer vs feature |
| 4 | Data Modeling Strategy | DTO/Entity separation, CQRS patterns |
| 5 | MSA / Distributed System | Message brokers, service discovery, resilience |
| 6 | Developer Intent & Health | Git history, test coverage, exception handling |

## Quick Reference by Violation Type

### Critical Violations
| ID | Violation | Fix | Detection |
|----|-----------|-----|-----------|
| V-C1 | Domain depends on infrastructure | Pure domain model + separate persistence entity | `import javax.persistence` in `domain/**` |
| V-C2 | Circular module dependencies | Shared events/interfaces, event-driven communication | Bidirectional imports between modules |
| V-C3 | UseCase depends on concrete adapter | Depend on port interfaces only | `import adapter.*` in `usecase/**` |

### High Violations
| ID | Violation | Fix | Detection |
|----|-----------|-----|-----------|
| V-H1 | Layer skipping (Controller -> Repository) | Controller -> Service -> Repository | `Repository` in `controller/**` |
| V-H2 | Entity exposed to API | Map to DTO before responding | `ResponseEntity<*Entity>` in controllers |
| V-H3 | Business logic in controller | Move to service layer | `calculate/validate/process` in controllers |
| V-H4 | Hard-coded dependencies (no DI) | Constructor injection | `= new *Repository()` or `= *Service()` |

### Medium Violations
| ID | Violation | Fix | Detection |
|----|-----------|-----|-----------|
| V-M1 | Inconsistent naming convention | Follow language conventions (PEP8, Kotlin style) | `class [a-z]`, `def camelCase` |
| V-M2 | Package structure inconsistency | Choose one: package-by-layer OR package-by-feature | Mixed `controllers/` + `order/` directories |
| V-M3 | God class / God module | Extract responsibilities, apply SRP | Files > 500 lines, > 15 imports |
| V-M4 | Excessive nullable in domain data class (Kotlin) | Encode domain invariants — required = non-null, List/Map/Set = default empty | data class nullable ratio > 70%, `List<*>?`/`Map<*,*>?`/`Set<*>?` in domain |

### Low Violations
| ID | Violation | Fix | Detection |
|----|-----------|-----|-----------|
| V-L1 | Missing architecture tests | Add ArchUnit / dependency-cruiser | No `@ArchTest` or `dependency-cruiser` |
| V-L2 | Missing API documentation | Add springdoc / swagger | No `openapi` in build config |
| V-L3 | No error handling strategy | Add global exception handler | No `@ControllerAdvice` / `ExceptionFilter` |

## Top 5 Most Common Architecture Violations

### 1. Domain Depends on Infrastructure (V-C1)
```kotlin
// BAD: domain/model/Order.kt
import javax.persistence.Entity  // Infrastructure leak!

// GOOD: Pure domain model + infrastructure/persistence/OrderEntity.kt
data class Order(val id: OrderId, val customerId: CustomerId, val totalAmount: Money)
```

### 2. Controller Skipping Service Layer (V-H1)
```kotlin
// BAD
@RestController
class OrderController(private val orderRepository: OrderRepository) { ... }

// GOOD
@RestController
class OrderController(private val orderService: OrderService) { ... }
```

### 3. Entity Exposed to API (V-H2)
```python
# BAD
@router.get("/users/{id}")
async def get_user(id: int, db: Session = Depends(get_db)):
    return db.query(UserModel).get(id)  # Leaks all fields

# GOOD
@router.get("/users/{id}", response_model=UserResponse)
async def get_user(id: int, service: UserService = Depends()):
    return service.find_by_id(id)
```

### 4. Hard-coded Dependencies (V-H4)
```typescript
// BAD
export class OrderService {
    private repo = new PostgresOrderRepo() // Tight coupling!
}

// GOOD
@Injectable()
export class OrderService {
    constructor(private readonly repo: OrderRepository) {}
}
```

### 5. Business Logic in Controller (V-H3)
```kotlin
// BAD: Controller calculates, validates, notifies
@PostMapping("/orders")
fun createOrder(@RequestBody req: CreateOrderRequest): ResponseEntity<OrderDto> {
    val total = req.items.sumOf { it.price * it.quantity }
    if (total > 10000) notificationService.notifyAdmin("Large order")
    // ...
}

// GOOD: Delegate to service
@PostMapping("/orders")
fun createOrder(@RequestBody req: CreateOrderRequest): ResponseEntity<OrderDto> {
    return ResponseEntity.status(HttpStatus.CREATED).body(orderService.create(req))
}
```

## Architecture Identification Matrix

| Signal | Architecture Type |
|--------|-------------------|
| `controller/`, `service/`, `repository/` dirs | Layered |
| `@Controller`, `@Service`, `@Repository` | Layered |
| `port/`, `adapter/`, `usecase/` dirs | Hexagonal/Clean |
| `domain/` with no outward imports | Hexagonal/Clean |
| `views.py`, `models.py`, `urls.py` | Django MVT |
| `modules/` with `*.module.ts` | NestJS Modular |

## DTO Separation Maturity

| Level | Description | Quality |
|-------|-------------|---------|
| 0 | Entity used everywhere | Poor |
| 1 | DTO exists but mixed with Entity | Fair |
| 2 | DTO per layer (Request/Response/Domain) | Good |
| 3 | CQRS (Command/Query separation) | Excellent |

## Naming Clarity Checklist (Kotlin)

Architectural health includes **naming alignment with domain intent**. Common reviewable patterns:

| Pattern | Bad | Good | Why |
|---|---|---|---|
| Boolean purpose | `expiredAt: Instant?` in response | `isExpired: Boolean` | External API should express purpose, not storage |
| Enum value | `RECENT_SCORE`, `POPULARITY_SCORE` | `RECENT`, `POPULARITY` | Implementation (score/rank) may change — name the property |
| Transformation fn | `fun toLegacySync()` (50-line mapping) | `fun convertToLegacySync()` | `to~` = simple cast, `convertTo~` = real mapping |
| const naming | `const val maxResults = 100` | `const val MAX_RESULTS = 100` | Kotlin convention: UPPER_SNAKE for compile-time constants |
| Parameter semantics | `defaultTime(collectedAt: Instant)` | `defaultTime(defaultInstant: Instant)` | Name by function's internal role, not caller context |
| Generic suffixes | `TokenInfo`, `KeywordData`, `SingleToken` | `TokenGroup`, `Keyword`, `Token` | `~Info/~Data/~Wrapper` add no meaning; "Single" needs a contrast pair |
| Map params | `fun handle(payload: Map<String, Any>)` | `fun handle(payload: AdminPayload)` | Structure known at compile time = data class |
| Primitive extensions | `fun String.toKeyword()` | `Keyword.from(raw)` factory | Primitive extensions lose context |

Flag when a code change introduces any row above. Most are **Low** severity individually but **frequent** — run in aggregate.

## DTO Design Quality Checklist

| Pattern | Flag at | Severity |
|---|---|---|
| `Map<String, Any>` parameter/return in `domain/` or `application/` | always | Medium |
| `Map<String, Any>` in adapter where keys are known at compile time | always | Medium |
| Request DTO: business-required field marked nullable | always | High |
| Response DTO: field nullable when domain is non-null | always | Medium |
| Response DTO: `List<*>?` instead of `List<*> = emptyList()` | always | Medium |
| "Future extensibility" excuse — all fields nullable | when no sealed hierarchy exists | Medium |
| Third-party API response used as `Map`/dynamic type | untrusted boundary | High |
| `ResponseEntity<*Entity>` in controller | always | High (V-H2) |
| Jackson `@JsonProperty` without external contract reason | clutter | Low |
| DTO has more than ~15 properties | often | Medium (split) |

## MSA Maturity Levels

| Level | Description |
|-------|-------------|
| 0 | Monolith - Single deployable unit |
| 1 | Modular Monolith - Logically separated modules |
| 2 | SOA - REST between services, possibly shared DB |
| 3 | MSA - Independent DBs, message brokers, service discovery |
| 4 | Event-Driven - Kafka/RabbitMQ primary, CQRS, Event Sourcing |

## Architecture Health Score

```
Base: 100 points

Deductions:
  Critical violation: -15 each
  High violation:     -8 each
  Medium violation:   -3 each
  Low violation:      -1 each

Bonuses:
  Architecture tests (ArchUnit):  +5
  API documentation:              +3
  Global exception handler:       +2
  Consistent naming:              +3
  DTO separation Level 2+:        +2

Rating:
  90-100: Excellent | 75-89: Good | 60-74: Fair | 40-59: Poor | 0-39: Critical
```

## Severity Guide

| Severity | When to Flag |
|----------|-------------|
| **Critical** | Core architecture principle broken (dependency direction reversed, circular deps) |
| **High** | Layer boundaries crossed, entity leaked to API, business logic misplaced |
| **Medium** | Naming inconsistency, package structure mixing, SRP violation |
| **Low** | Missing best practice (architecture tests, API docs, error handler) |

## Detailed Guide

For detailed analysis methodology, Bad/Good code examples per violation, and detection patterns, refer to the guide below:

- **[Architecture Review Guide](guide/arch-review-guide.md)** - Full methodology including 6-step analysis workflow, Violation Checklist (V-C1~V-L3), and Health Score calculation

This skill (SKILL.md) serves as a quick reference. For in-depth analysis, use the guide's detection patterns and code examples.

## Integration with Other Tools

- Use `/arch-review [target]` command for structured analysis with full report
- Use `/analyze --focus architecture` for broader multi-domain assessment
- The `arch-reviewer` agent contains the complete methodology with all code examples
- Use `/perf-review` for complementary performance-focused analysis
- This skill provides quick reference during regular development

---

**Remember**: Architecture matters most at scale. For small CRUD apps, pragmatism beats purity. Always consider project maturity and team size when evaluating violations. Detect the intended architecture, validate conformance, and provide actionable feedback.
