---
name: spring-gen
description: |
  Kotlin Spring Boot CRUD 계층 스캐폴딩 — 도메인명으로 Entity·Repository·Service·Controller·DTO·Test 를 프로젝트의 빌드 파일과 기존 코드 컨벤션을 먼저 감지해 그에 맞춰 생성한다(/spring-gen 으로 직접 호출).
  Scaffolds Kotlin Spring Boot CRUD layers for a domain after detecting the project's build file and existing conventions. Use when: the user runs /spring-gen to create a new domain's entity, repository, service, controller, DTO and tests.
disable-model-invocation: true
---

# /spring-gen - Kotlin Spring Boot CRUD 코드 생성

## Usage
```
/spring-gen [도메인명] [options]

Options:
  --fields       필드 정의 (e.g., "name:String, price:BigDecimal, status:OrderStatus")
  --layers       생성할 계층 선택 (e.g., "entity,repo,service,controller")
  --no-test      테스트 코드 생성 생략
  --reactive     WebFlux + R2DBC 리액티브 스택으로 생성
  --soft-delete  soft delete 패턴 적용 (deletedAt 필드 + 조회 필터 — Hibernate 6.3+ 는 @SQLRestriction, 미만은 @Where)
  --audit        Auditing 필드 자동 포함 (createdAt, updatedAt, createdBy)
```

## Behavioral Flow

### Phase 1: Discovery — 스택 감지 (생성 전 필수, 단정 금지)
아래를 **읽어서 확정**한다. 감지 결과가 옵션·이 문서의 예시와 다르면 감지 결과가 이긴다.
확정할 수 없는 항목은 사용자에게 한 번에 묻고, 답이 없으면 가정을 리포트에 명시한다.

1. **프로젝트 규칙**: 프로젝트 `CLAUDE.md`, `.claude/rules/` — 패키지·네이밍·테스트 규칙이 있으면 최우선.
2. **빌드 파일**: `build.gradle.kts` / `build.gradle` / `pom.xml`, `gradle/libs.versions.toml`
   - Spring Boot 메이저(3.x/4.x), Kotlin 버전, JDK toolchain
   - Kotlin 컴파일러 플러그인: `plugin.spring`, `plugin.jpa`, `allOpen { … Entity }` — 없으면 프록시·lazy 로딩이 깨진다(kotlin-spring-guide SPR-TX-01). 추가는 사용자 확인 후.
   - 데이터 접근: `spring-boot-starter-data-jpa` / `jooq` / `spring-boot-starter-jdbc` / `data-r2dbc` / `exposed`
   - 웹: `starter-web`(MVC) vs `starter-webflux`; 테스트: kotest / junit-jupiter, mockk / springmockk / mockito
   - 마이그레이션 도구: flyway / liquibase / 기타 — 의존성·`db/migration` 등 디렉터리로 판단. 스키마 파일 생성 여부는 사용자 확인.
3. **설정**: `application.yml`/`.properties` — `spring.jpa.*`(open-in-view, batch 설정), 데이터소스 종류(DB 벤더 → ID 전략: 시퀀스 지원 여부)
4. **기존 코드 샘플**: 가장 최근 도메인 하나를 골라 Entity·Repository·Service·Controller·DTO·Test 를 읽는다
   - 패키지 구조(계층형 `controller/` vs 도메인형 `order/`, 헥사고날 `adapter/port`)
   - Service 인터페이스+Impl 분리 여부, DTO 위치·팩토리 방식(companion `from` vs 매퍼)
   - 에러 처리(ErrorCode/BusinessException, ProblemDetail), Audit(BaseEntity, `@CreatedDate`), ID 타입·전략
5. **분류 확정**: MVC/WebFlux × JPA/jOOQ/JDBC/R2DBC × 계층형/헥사고날. 지원하지 않는 조합(예: Exposed)이면 생성 범위를 줄이고 이유를 보고한다.
6. 기존 컨벤션이 없는 신규 프로젝트에서만 `kotlin-spring-guide` 의 `references/team-conventions.md` 기본값을 쓴다.

### Phase 2: Generation
도메인 모델 정의를 기반으로 전체 계층 코드를 생성한다.

**Steps:**
1. **Entity**: 감지된 데이터 접근 기술에 맞춘 모델(JPA Entity / jOOQ·JDBC 레코드 / R2DBC 엔티티), audit·관계는 기존 패턴대로
2. **Repository**: Phase 1 에서 감지한 데이터 접근 방식대로(Spring Data interface / jOOQ DSL / JdbcClient·JdbcTemplate / R2DBC)
3. **Service**: 프로젝트 방식(인터페이스+Impl 또는 단일 클래스), 비즈니스 로직은 TODO(human)
4. **DTO**: Request/Response classes with Bean Validation
5. **Controller**: REST endpoints with proper HTTP status codes
6. **Test**: Unit(감지된 목 라이브러리) + 감지된 기술에 맞는 슬라이스 테스트(@WebMvcTest/@WebFluxTest, @DataJpaTest/@JooqTest/@JdbcTest/@DataR2dbcTest)

**Generation Rules:**
- Bottom-up 순서: Entity → Repository → Service → Controller
- 각 계층은 아래 계층만 의존 (Controller → Service → Repository)
- DTO는 Entity와 분리 (API 계약과 도메인 모델 독립)
- 테스트는 각 계층별로 적합한 수준으로 생성
- 비즈니스 로직이 필요한 부분은 TODO(human) 마커 사용

### Phase 3: Verification
생성된 코드가 컴파일되고 테스트가 통과하는지 검증한다.

**Steps:**
1. **Compile**: `./gradlew compileKotlin` 실행
2. **Test**: 생성된 테스트 실행 `./gradlew test --tests "*DomainName*"`
3. **Report**: 생성 결과 요약 + Phase 1 감지 결과(스택·가정) 출력

Maven 프로젝트면 `./mvnw compile` / `./mvnw test -Dtest='*DomainName*'` 로 대체한다.

## Tool Coordination
- **Glob**: 프로젝트 구조 파악, 기존 파일 탐색
- **Read**: 기존 코드 패턴 분석, build.gradle.kts 의존성 확인
- **Grep**: 기존 컨벤션 추출 (어노테이션, import, package 패턴)
- **Write**: 새 파일 생성
- **Edit**: 기존 파일 수정 (필요시)
- **Bash**: 빌드, 테스트 실행, 린트 검사
- **Context7 MCP** (선택): 버전 민감 API는 `backend-shared:context7-docs-guide` 규약에 따라 Context7 조회 후 생성 (미설치 시 생략)

## Examples

### Basic Usage
```
/spring-gen Order
# Order 도메인의 전체 CRUD 계층 생성
# → OrderEntity, OrderRepository, OrderService, OrderController, OrderDto, Tests
```

### With Fields
```
/spring-gen Product --fields "name:String, price:BigDecimal, category:Category, stock:Int"
# 필드가 정의된 Product 도메인 전체 계층 생성
```

### Specific Layers Only
```
/spring-gen Payment --layers "entity,repo,service"
# Controller 없이 Entity, Repository, Service만 생성
```

### Reactive Stack
```
/spring-gen Notification --reactive
# WebFlux + R2DBC 기반 리액티브 코드 생성
# → coroutine suspend 함수, Flow 반환 타입
```

### Soft Delete + Audit
```
/spring-gen Member --soft-delete --audit
# soft delete (deletedAt) + audit (createdAt, updatedAt, createdBy) 패턴 적용
```

## Generated Code Patterns (예시 — JPA + MVC + Kotest 조합일 때. 감지된 컨벤션이 우선)

### Entity
```kotlin
@Entity
@Table(name = "orders")
class OrderEntity(
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    val id: Long = 0L,

    @Column(nullable = false, length = 100)
    var name: String,

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 20)
    var status: OrderStatus = OrderStatus.CREATED,

    @Column(nullable = false, updatable = false)
    val createdAt: LocalDateTime = LocalDateTime.now(),

    @Column(nullable = false)
    var updatedAt: LocalDateTime = LocalDateTime.now(),
)

enum class OrderStatus {
    CREATED, CONFIRMED, SHIPPED, DELIVERED, CANCELLED
}
```

### Repository
```kotlin
interface OrderRepository : JpaRepository<OrderEntity, Long> {
    fun findByStatus(status: OrderStatus): List<OrderEntity>
    fun findByCreatedAtBetween(start: LocalDateTime, end: LocalDateTime): List<OrderEntity>
}
```

### Service
```kotlin
interface OrderService {
    fun findById(id: Long): OrderResponse
    fun findAll(pageable: Pageable): Page<OrderResponse>
    fun create(request: CreateOrderRequest): OrderResponse
    fun update(id: Long, request: UpdateOrderRequest): OrderResponse
    fun delete(id: Long)
}

@Service
@Transactional(readOnly = true)
class OrderServiceImpl(
    private val orderRepository: OrderRepository,
) : OrderService {

    override fun findById(id: Long): OrderResponse {
        val entity = orderRepository.findByIdOrNull(id)
            ?: throw OrderNotFoundException(id)
        return OrderResponse.from(entity)
    }

    override fun findAll(pageable: Pageable): Page<OrderResponse> =
        orderRepository.findAll(pageable).map(OrderResponse::from)

    @Transactional
    override fun create(request: CreateOrderRequest): OrderResponse {
        val entity = OrderEntity(
            name = request.name,
            status = request.status,
        )
        return OrderResponse.from(orderRepository.save(entity))
    }

    @Transactional
    override fun update(id: Long, request: UpdateOrderRequest): OrderResponse {
        val entity = orderRepository.findByIdOrNull(id)
            ?: throw OrderNotFoundException(id)
        request.name?.let { entity.name = it }
        request.status?.let { entity.status = it }
        entity.updatedAt = LocalDateTime.now()
        return OrderResponse.from(orderRepository.save(entity))
    }

    @Transactional
    override fun delete(id: Long) {
        if (!orderRepository.existsById(id)) {
            throw OrderNotFoundException(id)
        }
        orderRepository.deleteById(id)
    }
}
```

### DTO
```kotlin
data class CreateOrderRequest(
    @field:NotBlank(message = "이름은 필수입니다")
    val name: String,

    @field:NotNull(message = "상태는 필수입니다")
    val status: OrderStatus,
)

data class UpdateOrderRequest(
    val name: String? = null,
    val status: OrderStatus? = null,
)

data class OrderResponse(
    val id: Long,
    val name: String,
    val status: OrderStatus,
    val createdAt: LocalDateTime,
    val updatedAt: LocalDateTime,
) {
    companion object {
        fun from(entity: OrderEntity) = OrderResponse(
            id = entity.id,
            name = entity.name,
            status = entity.status,
            createdAt = entity.createdAt,
            updatedAt = entity.updatedAt,
        )
    }
}
```

### Controller
```kotlin
@RestController
@RequestMapping("/api/v1/orders")
class OrderController(
    private val orderService: OrderService,
) {
    @GetMapping("/{id}")
    fun findById(@PathVariable id: Long): ResponseEntity<OrderResponse> =
        ResponseEntity.ok(orderService.findById(id))

    @GetMapping
    fun findAll(@PageableDefault(size = 20) pageable: Pageable): ResponseEntity<Page<OrderResponse>> =
        ResponseEntity.ok(orderService.findAll(pageable))

    @PostMapping
    fun create(@Valid @RequestBody request: CreateOrderRequest): ResponseEntity<OrderResponse> =
        ResponseEntity.status(HttpStatus.CREATED).body(orderService.create(request))

    @PutMapping("/{id}")
    fun update(
        @PathVariable id: Long,
        @Valid @RequestBody request: UpdateOrderRequest,
    ): ResponseEntity<OrderResponse> =
        ResponseEntity.ok(orderService.update(id, request))

    @DeleteMapping("/{id}")
    fun delete(@PathVariable id: Long): ResponseEntity<Unit> {
        orderService.delete(id)
        return ResponseEntity.noContent().build()
    }
}
```

### Unit Test (Kotest + MockK)
```kotlin
class OrderServiceTest : BehaviorSpec({
    val orderRepository = mockk<OrderRepository>()
    val service = OrderServiceImpl(orderRepository)

    afterEach { clearAllMocks() }

    Given("존재하는 주문 ID") {
        val entity = OrderEntity(id = 1L, name = "테스트 주문", status = OrderStatus.CREATED)
        every { orderRepository.findByIdOrNull(1L) } returns entity

        When("findById 호출") {
            val result = service.findById(1L)

            Then("주문 정보를 반환한다") {
                result.id shouldBe 1L
                result.name shouldBe "테스트 주문"
            }
        }
    }

    Given("존재하지 않는 주문 ID") {
        every { orderRepository.findByIdOrNull(999L) } returns null

        When("findById 호출") {
            Then("OrderNotFoundException이 발생한다") {
                shouldThrow<OrderNotFoundException> {
                    service.findById(999L)
                }
            }
        }
    }
})
```

### Integration Test (@WebMvcTest)
```kotlin
@WebMvcTest(OrderController::class)
class OrderControllerTest(
    @Autowired val mockMvc: MockMvc,
    @MockkBean val orderService: OrderService,
    @Autowired val objectMapper: ObjectMapper, // Boot 구성 매퍼 재사용 (kotlin-spring-guide SPR-JSON-01)
) : BehaviorSpec({

    Given("주문 생성 요청") {
        val request = CreateOrderRequest(name = "새 주문", status = OrderStatus.CREATED)
        val response = OrderResponse(
            id = 1L, name = "새 주문", status = OrderStatus.CREATED,
            createdAt = LocalDateTime.now(), updatedAt = LocalDateTime.now(),
        )
        every { orderService.create(any()) } returns response

        When("POST /api/v1/orders 호출") {
            val result = mockMvc.perform(
                post("/api/v1/orders")
                    .contentType(MediaType.APPLICATION_JSON)
                    .content(objectMapper.writeValueAsString(request))
            )

            Then("201 Created와 주문 정보를 반환한다") {
                result
                    .andExpect(status().isCreated)
                    .andExpect(jsonPath("$.id").value(1))
                    .andExpect(jsonPath("$.name").value("새 주문"))
            }
        }
    }
})
```

## Boundaries

**Will:**
- 프로젝트 기존 컨벤션을 분석하고 정확히 따름
- 전체 CRUD 계층을 일관된 패턴으로 생성
- Bean Validation 어노테이션 포함
- 적절한 테스트 코드 생성 (단위 + 통합)
- Audit 필드 자동 포함 (프로젝트 패턴에 따라)
- 커스텀 Exception 클래스 생성

**Will Not:**
- 기존 파일을 무단 수정
- 비즈니스 로직을 임의로 구현 (TODO(human) 마커 사용)
- 프로젝트에 없는 의존성을 요구하는 코드 생성
- Java 스타일 코드 생성 (Optional.get(), getter/setter 등)
- 불필요한 주석이나 Javadoc 생성
- build.gradle.kts 의존성 추가 (별도 확인 필요)
