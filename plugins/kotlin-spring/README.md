> **English** · [한국어](README_KO.md)

# kotlin-spring

> A backend-specialized plugin that generates idiomatic CRUD-layer code in Kotlin + Spring Boot projects and bundles framework diagnostics, principles, naming, and idiomatic patterns into a single set.

## Overview

`kotlin-spring` is a collection of code generation, diagnostic, and reference tools specialized for the Kotlin + Spring Boot stack. Its core capability is scaffolding the entire Entity → Repository → Service → Controller → DTO → Test layer from a single domain name, aligned with the project's existing conventions (`/spring-gen` + `spring-developer`). Combined with this are a specialist agent that diagnoses framework-level problems (`spring-boot-guide`) and skills that attach development principles, naming, and idiomatic patterns at the moment they are needed.

Code generation follows the discipline of "analyze first, then generate." It scans `build.gradle.kts`, `application.yml`, and existing sources to extract the package structure, DTO patterns, test framework (Kotest/JUnit·MockK), error-handling approach, and Audit patterns, then emits code following those conventions. It enforces a Kotlin First style that excludes Java idioms (`Optional`, getter/setter, `!!`), and it does not arbitrarily implement business logic — leaving it behind as `TODO(human)` markers instead.

Language-neutral backend cross-cutting concerns (REST/GraphQL API contracts, DB migration safety, hexagonal architecture, observability/caching/events/resilience/security) are not handled by this plugin and are delegated to the `backend-shared` plugin. Because it covers only the Kotlin/Spring-specific parts, it presumes the two are installed together and combined.

## Components

### Commands

- `/spring-gen [domain-name]` — Scaffolds the full Kotlin Spring Boot CRUD layer. It proceeds in 3 stages: Discovery (convention analysis) → Generation (per-layer generation) → Verification (compile·test), and the `--fields`, `--layers`, `--no-test`, `--reactive` (WebFlux + R2DBC), `--soft-delete`, and `--audit` options adjust the generation scope and patterns.

### Agents

- `spring-developer` — A code generation specialist agent. As the actual generation engine of `/spring-gen`, it extracts the project's conventions (Decision Matrix) to build an idiomatic Kotlin full CRUD stack. Its tools are Read/Grep/Glob/Bash/Write/Edit, and it references the skill `kotlin-spring-guide`.
- `spring-boot-guide` — A Spring Boot (Kotlin) framework diagnostics expert (read-only: Read/Grep/Glob/Bash). It diagnoses DI/bean conflicts, `@Transactional` propagation·proxy (self-invocation) issues, Spring Security, Data JPA/R2DBC, N+1, test slices, auto-configuration, and Spring for GraphQL problems, and recommends patterns.

### Skills

- `kotlin-spring-guide` — A development-principles·decision-making guide. It provides the Kotlin First, layer discipline (top→bottom dependencies), Fail Fast (triple defense), and Convention over Configuration principles, along with the selection criteria for architecture/stack/test framework. As detailed references it includes `references/layer-patterns.md` (per-layer patterns), `references/jpa-patterns.md` (Entity design·N+1 prevention·associations·persistence context), and `references/testing-patterns.md` (Kotest·MockK·@WebMvcTest·@DataJpaTest).
- `spring-boot-patterns` — An idiomatic-pattern reference centered on actual implementation code examples. It covers `@Transactional` semantics (propagation/isolation/readOnly/rollbackFor·proxy pitfalls), Spring Data JPA queries (method queries·JPQL·QueryDSL·@EntityGraph·Page/Slice), `@ControllerAdvice` (RFC 7807 ProblemDetail)·error-code system, Bean Validation (group validation·custom Validator), configuration binding (@ConfigurationProperties·relaxed binding), Spring for GraphQL (@BatchMapping·DataLoader), Coroutines integration, and WebClient patterns.
- `naming-conventions` — Kotlin naming idioms. It organizes into rules and checklists: purpose-oriented vs implementation-oriented (`isExpired` vs `expiredAt`), Enum name invariance (`POPULARITY` vs `POPULARITY_SCORE`), verb-form conversion functions (`convertTo~` vs `to~`), uppercase `const val`, parameters named from the function's standpoint, domain-term consistency (avoiding `~Info`/`~Data`), avoiding `Map<String, Any>` parameters, and avoiding primitive extension functions.

## Usage

CRUD scaffolding is invoked directly with `/spring-gen`. Append options after the domain name to specify fields·layers·stack.

```
# Generate the full CRUD layer for the Order domain
/spring-gen Order

# Generate the Product layer with fields defined
/spring-gen Product --fields "name:String, price:BigDecimal, stock:Int"

# Only Entity/Repository/Service, without Controller
/spring-gen Payment --layers "entity,repo,service"

# WebFlux + R2DBC reactive stack (suspend/Flow)
/spring-gen Notification --reactive

# Apply soft delete + audit fields
/spring-gen Member --soft-delete --audit
```

Agents and skills operate from context without separate commands. `spring-developer` performs generation when `/spring-gen` runs, and `spring-boot-guide` is used when framework diagnostics for transactions/DI/GraphQL and the like are needed. The skills (`kotlin-spring-guide`·`spring-boot-patterns`·`naming-conventions`) are loaded automatically the moment you write·review·refactor Kotlin + Spring code, reinforcing principles, pattern examples, and naming decision criteria. The roles are split between `kotlin-spring-guide` for principles·decision-making and `spring-boot-patterns` for concrete implementation code examples.

## Dependencies

- **requires / dependencies**: `backend-shared`. Because language-neutral backend common patterns (API contracts, migrations, hexagonal, observability/caching/events/resilience/security, DTO·test patterns) are handled by `backend-shared`, install it together and combine.
- If Python/FastAPI specialization is needed, the `python-fastapi` plugin corresponds to that.

## Notes

- `/spring-gen` does not modify existing files without authorization, and it does not arbitrarily implement business logic — marking it with `TODO(human)` markers instead.
- It does not add `build.gradle.kts` dependencies without user confirmation, and it does not generate code that requires dependencies absent from the project.
- It does not generate Java-style Kotlin (`Optional.get()`, getter/setter, `!!`, Java Stream).
- Compile·test execution (`./gradlew compileKotlin`, `./gradlew test`) is performed in the verification stage, and after confirming that the generated code matches the project conventions, it is compiled into a report.
- Version-sensitive APIs (Spring Boot 3.x configuration, etc.) are reflected after a Context7 lookup per the `backend-shared:context7-docs-guide` convention, and are omitted when it is not installed.
