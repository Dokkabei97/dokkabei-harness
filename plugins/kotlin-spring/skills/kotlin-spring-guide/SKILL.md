---
name: kotlin-spring-guide
description: |
  Kotlin + Spring Boot 개발 원칙/의사결정 가이드. Kotlin First 철학, 레이어 규율, Fail Fast, 아키텍처·스택·테스트 프레임워크 선택 기준을 제공한다.
  구체적 구현 코드 예제(@Transactional, JPA, WebClient, Coroutines 관용구)는 spring-boot-patterns를 참조할 것.
  Decision guide for Kotlin + Spring Boot development: Kotlin First philosophy, layer discipline, Fail Fast, and selection criteria for architecture, stack, and test frameworks; concrete code idioms (@Transactional, JPA, WebClient, Coroutines) live in spring-boot-patterns. Use when: making Kotlin/Spring architecture or stack decisions, enforcing layer rules, or choosing test frameworks.
---

# Kotlin + Spring Boot Development Guide

Kotlin + Spring Boot 프로젝트에서 관용적이고 유지보수 가능한 코드를 작성하기 위한 종합 가이드.

## When to Apply

Reference these guidelines when:
- Kotlin + Spring Boot 프로젝트에서 새 코드를 작성할 때
- 기존 Spring Boot 코드를 리뷰하거나 리팩토링할 때
- JPA Entity 설계나 쿼리 최적화가 필요할 때
- 테스트 코드를 작성하거나 테스트 전략을 결정할 때
- 버전 민감 API(Spring Boot 3.x 설정 등)는 `backend-shared:context7-docs-guide` 규약에 따라 Context7 조회 후 생성 (미설치 시 생략)

## Quick Reference

| Priority | Category | Impact | Reference |
|----------|----------|--------|-----------|
| 1 | Layer Patterns | 코드 구조와 의존성 방향 | `references/layer-patterns.md` |
| 2 | JPA Patterns | 데이터 접근 성능과 정합성 | `references/jpa-patterns.md` |
| 3 | Testing Patterns | 테스트 품질과 신뢰성 | `references/testing-patterns.md` |

## Core Principles

### 1. Kotlin First — Java 관용구 제거

| Java Style (Avoid) | Kotlin Style (Use) | Why |
|----|----|----|
| `Optional<T>` | `T?` | Kotlin null safety가 더 안전하고 간결 |
| `obj.getX()` | `obj.x` | property access syntax |
| `static` methods | `companion object` / top-level | Kotlin에 static 없음 |
| `StringBuilder` | `buildString { }` | DSL style, 더 읽기 쉬움 |
| `Stream.map().collect()` | `.map { }` | Kotlin stdlib가 더 간결 |
| `try-catch → return null` | `runCatching { }.getOrNull()` | 함수형 에러 처리 |
| setter chain | `apply { }` block | scope function |
| `new ArrayList()` | `mutableListOf()` | Kotlin collection factories |
| `instanceof` check | `is` + smart cast | 자동 캐스팅 |

### 2. Layer Discipline — 의존 방향은 항상 위→아래

```
Controller (API 계약)
    ↓ DTO
Service (비즈니스 로직)
    ↓ Entity
Repository (데이터 접근)
    ↓
Database
```

**절대 규칙:**
- Controller는 Entity를 직접 반환하지 않는다 (DTO 사용)
- Repository는 Service 없이 Controller에서 직접 호출하지 않는다
- Service는 HttpServletRequest 등 웹 계층 객체에 접근하지 않는다

### 3. Fail Fast — 잘못된 입력은 빨리 거부

```kotlin
// 1st defense: Bean Validation at Controller layer
data class CreateOrderRequest(
    @field:NotBlank val name: String,
    @field:Positive val amount: BigDecimal,
)

// 2nd defense: Domain validation at Service layer
fun create(request: CreateOrderRequest): OrderResponse {
    require(request.amount <= MAX_ORDER_AMOUNT) { "주문 한도 초과" }
    // ...
}

// 3rd defense: DB constraint as last safety net
@Column(nullable = false)
var name: String
```

### 4. Convention over Configuration

Spring Boot의 기본값을 최대한 활용하고, 필요한 경우에만 커스터마이징한다.

```kotlin
// GOOD: Spring Data JPA 기본 메서드 활용
interface OrderRepository : JpaRepository<OrderEntity, Long>

// BAD: 불필요한 커스텀 쿼리
interface OrderRepository : JpaRepository<OrderEntity, Long> {
    @Query("SELECT o FROM OrderEntity o WHERE o.id = :id")
    fun findOrderById(id: Long): OrderEntity?  // findById로 충분
}
```

## How to Use

Read individual reference files for detailed patterns and examples:

```
references/layer-patterns.md    — Controller, Service, Repository 계층별 패턴
references/jpa-patterns.md      — Entity 설계, N+1 방지, 연관 관계, 영속성 컨텍스트
references/testing-patterns.md  — Kotest, MockK, @WebMvcTest, @DataJpaTest
```

Each reference file contains:
- Pattern description and rationale
- Bad/Good code examples with explanations
- Common pitfalls and solutions
- Decision guidance for choosing between approaches

## Decision Quick Reference

### Architecture Style

| 상황 | 권장 | 이유 |
|------|-----|------|
| CRUD 중심 서비스 | Layered Architecture | 단순하고 팀 러닝커브 낮음 |
| 복잡한 도메인 로직 | Hexagonal / Clean | 도메인 보호, 테스트 용이 |
| MSA 이벤트 기반 | CQRS + Event Sourcing | 읽기/쓰기 최적화 분리 |

### Stack Selection

| 상황 | 권장 | 이유 |
|------|-----|------|
| 표준 REST API | Spring MVC + JPA | 생태계, 문서, 팀 경험 |
| 고처리량 비동기 | WebFlux + R2DBC + Coroutine | 비차단 I/O |
| 배치/데이터 처리 | Spring Batch | 트랜잭션, 재시도, 모니터링 |

### Test Framework

| 상황 | 권장 | 이유 |
|------|-----|------|
| BDD 스타일 선호 | Kotest BehaviorSpec | Given/When/Then 가독성 |
| 간결한 단위 테스트 | Kotest FunSpec | 최소 보일러플레이트 |
| 기존 JUnit 프로젝트 | JUnit 5 + AssertJ | 마이그레이션 비용 절감 |
| Mocking | MockK | Kotlin 친화적 (suspend, extension 지원) |
