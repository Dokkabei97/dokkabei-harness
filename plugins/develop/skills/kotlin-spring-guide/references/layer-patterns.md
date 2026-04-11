# Layer Patterns — Controller / Service / Repository

Kotlin + Spring Boot에서 각 계층의 책임과 구현 패턴.

---

## Controller Layer

### 책임
- HTTP 요청/응답 변환 (직렬화/역직렬화)
- 입력값 검증 위임 (Bean Validation)
- 적절한 HTTP 상태 코드 반환
- Service 호출 위임

### 올바른 패턴

```kotlin
@RestController
@RequestMapping("/api/v1/orders")
class OrderController(
    private val orderService: OrderService,
) {
    // 단건 조회 — 200 OK
    @GetMapping("/{id}")
    fun findById(@PathVariable id: Long): ResponseEntity<OrderResponse> =
        ResponseEntity.ok(orderService.findById(id))

    // 목록 조회 — 페이지네이션 + 정렬
    @GetMapping
    fun findAll(
        @PageableDefault(size = 20, sort = ["createdAt"], direction = Sort.Direction.DESC)
        pageable: Pageable,
    ): ResponseEntity<Page<OrderResponse>> =
        ResponseEntity.ok(orderService.findAll(pageable))

    // 생성 — 201 Created + Location
    @PostMapping
    fun create(@Valid @RequestBody request: CreateOrderRequest): ResponseEntity<OrderResponse> {
        val created = orderService.create(request)
        return ResponseEntity
            .created(URI.create("/api/v1/orders/${created.id}"))
            .body(created)
    }

    // 수정 — 200 OK
    @PutMapping("/{id}")
    fun update(
        @PathVariable id: Long,
        @Valid @RequestBody request: UpdateOrderRequest,
    ): ResponseEntity<OrderResponse> =
        ResponseEntity.ok(orderService.update(id, request))

    // 삭제 — 204 No Content
    @DeleteMapping("/{id}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    fun delete(@PathVariable id: Long) {
        orderService.delete(id)
    }
}
```

### 안티패턴

```kotlin
// BAD: Controller에서 비즈니스 로직 수행
@PostMapping
fun create(@RequestBody request: CreateOrderRequest): ResponseEntity<OrderEntity> {
    // ❌ Controller에서 직접 비즈니스 검증
    if (request.amount > BigDecimal(1000000)) {
        throw IllegalArgumentException("한도 초과")
    }
    // ❌ Repository 직접 호출
    val entity = OrderEntity(name = request.name, amount = request.amount)
    val saved = orderRepository.save(entity)
    // ❌ Entity 직접 반환 (API 계약과 도메인 결합)
    return ResponseEntity.ok(saved)
}
```

---

## Service Layer

### 책임
- 비즈니스 로직 구현
- 트랜잭션 경계 관리
- 도메인 검증
- Repository 조합 및 도메인 이벤트 발행

### 올바른 패턴

```kotlin
// Interface 분리 — 테스트 용이, 구현 교체 가능
interface OrderService {
    fun findById(id: Long): OrderResponse
    fun findAll(pageable: Pageable): Page<OrderResponse>
    fun create(request: CreateOrderRequest): OrderResponse
    fun update(id: Long, request: UpdateOrderRequest): OrderResponse
    fun delete(id: Long)
}

@Service
@Transactional(readOnly = true)  // 클래스 레벨: 읽기 전용 기본
class OrderServiceImpl(
    private val orderRepository: OrderRepository,
    private val eventPublisher: ApplicationEventPublisher,
) : OrderService {

    override fun findById(id: Long): OrderResponse {
        val entity = orderRepository.findByIdOrNull(id)
            ?: throw OrderNotFoundException(id)
        return OrderResponse.from(entity)
    }

    override fun findAll(pageable: Pageable): Page<OrderResponse> =
        orderRepository.findAll(pageable).map(OrderResponse::from)

    @Transactional  // 쓰기 메서드만 @Transactional 오버라이드
    override fun create(request: CreateOrderRequest): OrderResponse {
        // 도메인 검증
        require(request.amount > BigDecimal.ZERO) { "주문 금액은 0보다 커야 합니다" }

        val entity = OrderEntity(
            name = request.name,
            amount = request.amount,
            status = OrderStatus.CREATED,
        )
        val saved = orderRepository.save(entity)

        // 도메인 이벤트 발행
        eventPublisher.publishEvent(OrderCreatedEvent(saved.id))

        return OrderResponse.from(saved)
    }

    @Transactional
    override fun update(id: Long, request: UpdateOrderRequest): OrderResponse {
        val entity = orderRepository.findByIdOrNull(id)
            ?: throw OrderNotFoundException(id)

        // 부분 업데이트 — null이 아닌 필드만 적용
        request.name?.let { entity.name = it }
        request.amount?.let {
            require(it > BigDecimal.ZERO) { "주문 금액은 0보다 커야 합니다" }
            entity.amount = it
        }
        request.status?.let {
            // 상태 전이 검증
            entity.validateStatusTransition(it)
            entity.status = it
        }

        return OrderResponse.from(orderRepository.save(entity))
    }

    @Transactional
    override fun delete(id: Long) {
        val entity = orderRepository.findByIdOrNull(id)
            ?: throw OrderNotFoundException(id)
        check(entity.status == OrderStatus.CREATED) {
            "생성 상태의 주문만 삭제할 수 있습니다"
        }
        orderRepository.delete(entity)
    }
}
```

### 안티패턴

```kotlin
// BAD: @Transactional 누락 or 잘못된 사용
@Service
class OrderServiceImpl(
    private val orderRepository: OrderRepository,
) : OrderService {

    // ❌ readOnly=true 없이 전체 클래스에 @Transactional
    // → 읽기 쿼리도 쓰기 트랜잭션으로 처리

    // ❌ findByIdOrNull 대신 findById().get()
    override fun findById(id: Long): OrderResponse {
        val entity = orderRepository.findById(id).get() // NoSuchElementException
        return OrderResponse.from(entity)
    }

    // ❌ @Transactional 메서드 안에서 외부 API 호출
    @Transactional
    override fun create(request: CreateOrderRequest): OrderResponse {
        val entity = orderRepository.save(...)
        paymentClient.charge(entity.amount) // 외부 호출 중 트랜잭션 점유
        return OrderResponse.from(entity)
    }
}
```

### @Transactional 전략

| 시나리오 | 권장 | 이유 |
|---------|-----|------|
| Service 클래스 레벨 | `@Transactional(readOnly = true)` | 읽기 최적화 기본값 |
| 쓰기 메서드 | `@Transactional` (readOnly 오버라이드) | 쓰기 트랜잭션 |
| 외부 API 호출 포함 | 트랜잭션 밖에서 호출 후 저장 | 트랜잭션 점유 시간 최소화 |
| 대량 처리 | `@Transactional` + 배치 사이즈 | OOM 방지 |

---

## Repository Layer

### 책임
- 데이터 접근 추상화
- 쿼리 메서드 정의
- 복잡한 쿼리는 JPQL 또는 QueryDSL

### 올바른 패턴

```kotlin
interface OrderRepository : JpaRepository<OrderEntity, Long> {

    // 메서드 이름 기반 쿼리
    fun findByStatus(status: OrderStatus): List<OrderEntity>
    fun findByStatusAndCreatedAtAfter(status: OrderStatus, after: LocalDateTime): List<OrderEntity>
    fun existsByNameAndStatus(name: String, status: OrderStatus): Boolean

    // JPQL — 복잡한 조건
    @Query("""
        SELECT o FROM OrderEntity o
        WHERE o.status = :status
        AND o.amount >= :minAmount
        ORDER BY o.createdAt DESC
    """)
    fun findExpensiveOrders(
        @Param("status") status: OrderStatus,
        @Param("minAmount") minAmount: BigDecimal,
    ): List<OrderEntity>

    // 페이지네이션 쿼리
    fun findByStatus(status: OrderStatus, pageable: Pageable): Page<OrderEntity>

    // Projection — 필요한 필드만 조회
    @Query("SELECT o.id, o.name, o.status FROM OrderEntity o WHERE o.status = :status")
    fun findSummaryByStatus(@Param("status") status: OrderStatus): List<OrderSummary>
}

// Projection interface
interface OrderSummary {
    val id: Long
    val name: String
    val status: OrderStatus
}
```

### 안티패턴

```kotlin
// BAD: 불필요한 커스텀 쿼리
interface OrderRepository : JpaRepository<OrderEntity, Long> {
    // ❌ findById()가 이미 존재
    @Query("SELECT o FROM OrderEntity o WHERE o.id = :id")
    fun findOrderById(@Param("id") id: Long): OrderEntity?

    // ❌ findAll(pageable)이 이미 존재
    @Query("SELECT o FROM OrderEntity o")
    fun findAllOrders(pageable: Pageable): Page<OrderEntity>
}
```

---

## DTO Patterns

### Request/Response 분리

```kotlin
// Create Request — 필수 필드 + 검증
data class CreateOrderRequest(
    @field:NotBlank(message = "이름은 필수입니다")
    @field:Size(max = 100, message = "이름은 100자 이내여야 합니다")
    val name: String,

    @field:NotNull(message = "금액은 필수입니다")
    @field:Positive(message = "금액은 양수여야 합니다")
    val amount: BigDecimal,
)

// Update Request — 모든 필드 nullable (부분 업데이트)
data class UpdateOrderRequest(
    @field:Size(max = 100, message = "이름은 100자 이내여야 합니다")
    val name: String? = null,

    @field:Positive(message = "금액은 양수여야 합니다")
    val amount: BigDecimal? = null,

    val status: OrderStatus? = null,
)

// Response — Entity에서 변환, 도메인 세부사항 숨김
data class OrderResponse(
    val id: Long,
    val name: String,
    val amount: BigDecimal,
    val status: OrderStatus,
    val createdAt: LocalDateTime,
    val updatedAt: LocalDateTime,
) {
    companion object {
        fun from(entity: OrderEntity) = OrderResponse(
            id = entity.id,
            name = entity.name,
            amount = entity.amount,
            status = entity.status,
            createdAt = entity.createdAt,
            updatedAt = entity.updatedAt,
        )
    }
}
```

### Bean Validation 주의점

```kotlin
// ❌ BAD: @NotBlank를 val에 직접 — 동작하지 않음
data class CreateRequest(
    @NotBlank val name: String, // Kotlin에서는 필드에 적용 안 됨
)

// ✅ GOOD: @field: 타겟 지정
data class CreateRequest(
    @field:NotBlank val name: String, // 필드 레벨에 정확히 적용
)
```

---

## Exception Handling

### 커스텀 Exception 계층

```kotlin
// 비즈니스 예외 sealed class
sealed class DomainException(
    message: String,
    val errorCode: String,
) : RuntimeException(message)

class OrderNotFoundException(id: Long) : DomainException(
    message = "주문을 찾을 수 없습니다: $id",
    errorCode = "ORDER_NOT_FOUND",
)

class InvalidOrderStatusException(
    current: OrderStatus,
    target: OrderStatus,
) : DomainException(
    message = "주문 상태를 $current 에서 $target 로 변경할 수 없습니다",
    errorCode = "INVALID_ORDER_STATUS",
)

class DuplicateOrderException(name: String) : DomainException(
    message = "중복된 주문입니다: $name",
    errorCode = "DUPLICATE_ORDER",
)
```

### GlobalExceptionHandler

```kotlin
@RestControllerAdvice
class GlobalExceptionHandler {

    @ExceptionHandler(DomainException::class)
    fun handleDomain(ex: DomainException): ResponseEntity<ProblemDetail> {
        val status = when (ex) {
            is OrderNotFoundException -> HttpStatus.NOT_FOUND
            is InvalidOrderStatusException -> HttpStatus.CONFLICT
            is DuplicateOrderException -> HttpStatus.CONFLICT
        }
        val problem = ProblemDetail.forStatusAndDetail(status, ex.message ?: "")
        problem.title = status.reasonPhrase
        problem.setProperty("errorCode", ex.errorCode)
        return ResponseEntity.status(status).body(problem)
    }

    @ExceptionHandler(MethodArgumentNotValidException::class)
    fun handleValidation(ex: MethodArgumentNotValidException): ResponseEntity<ProblemDetail> {
        val problem = ProblemDetail.forStatusAndDetail(
            HttpStatus.BAD_REQUEST, "입력값 검증에 실패했습니다",
        )
        problem.title = "Validation Failed"
        problem.setProperty("errors", ex.bindingResult.fieldErrors.map {
            mapOf("field" to it.field, "message" to (it.defaultMessage ?: ""))
        })
        return ResponseEntity.badRequest().body(problem)
    }

    @ExceptionHandler(IllegalArgumentException::class)
    fun handleIllegalArgument(ex: IllegalArgumentException): ResponseEntity<ProblemDetail> {
        val problem = ProblemDetail.forStatusAndDetail(
            HttpStatus.BAD_REQUEST, ex.message ?: "잘못된 요청입니다",
        )
        problem.title = "Bad Request"
        return ResponseEntity.badRequest().body(problem)
    }
}
```
