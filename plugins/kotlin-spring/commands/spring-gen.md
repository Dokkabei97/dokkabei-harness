---
name: spring-gen
description: "Kotlin Spring Boot CRUD 계층 코드 생성. 도메인명을 입력하면 Entity, Repository, Service, Controller, DTO, Test를 프로젝트 컨벤션에 맞춰 자동 생성한다."
category: development
complexity: advanced
mcp-servers: []
personas: []
---

# /spring-gen - Kotlin Spring Boot CRUD 코드 생성

## Triggers
- 새로운 도메인 모델의 CRUD 코드가 필요할 때
- "Order 엔티티 만들어줘", "Product CRUD 생성해줘"
- 기존 프로젝트에 새 도메인 계층을 추가할 때
- Spring Boot 프로젝트에서 표준 계층 구조를 스캐폴딩할 때

## Usage
```
/spring-gen [도메인명] [options]

Options:
  --fields       필드 정의 (e.g., "name:String, price:BigDecimal, status:OrderStatus")
  --layers       생성할 계층 선택 (e.g., "entity,repo,service,controller")
  --no-test      테스트 코드 생성 생략
  --reactive     WebFlux + R2DBC 리액티브 스택으로 생성
  --soft-delete  soft delete 패턴 적용 (deletedAt 필드 + @Where)
  --audit        Auditing 필드 자동 포함 (createdAt, updatedAt, createdBy)
```

## Behavioral Flow

### Phase 1: Discovery
프로젝트 구조와 기존 코드 컨벤션을 분석한다.

**Steps:**
1. **Scan**: `build.gradle.kts`, `application.yml` 스캔하여 의존성과 설정 파악
2. **Analyze**: 기존 Entity, Controller, Service 파일을 읽어 패턴 추출
   - 패키지 구조 (`com.example.app.model` vs `com.example.app.domain.order`)
   - DTO 패턴 (inner class vs separate file, companion factory vs mapper)
   - 테스트 프레임워크 (Kotest vs JUnit, MockK vs Mockito)
   - 에러 핸들링 패턴 (sealed class, GlobalExceptionHandler)
   - Audit 패턴 (BaseEntity, @CreatedDate)
3. **Classify**: 프로젝트 타입 결정
   - Servlet (Spring MVC) vs Reactive (WebFlux)
   - JPA vs R2DBC vs JDBC
   - Layered vs Hexagonal architecture

### Phase 2: Generation
도메인 모델 정의를 기반으로 전체 계층 코드를 생성한다.

**Steps:**
1. **Entity**: JPA Entity with audit fields, validation, relationships
2. **Repository**: Spring Data interface with custom queries
3. **Service**: Interface + Implementation with business logic placeholders
4. **DTO**: Request/Response classes with Bean Validation
5. **Controller**: REST endpoints with proper HTTP status codes
6. **Test**: Unit (MockK) + Integration (@WebMvcTest, @DataJpaTest) tests

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
3. **Report**: 생성 결과 요약 출력

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

## Generated Code Patterns

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
) : BehaviorSpec({
    val objectMapper = jacksonObjectMapper()

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
