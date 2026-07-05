---
name: spring-boot-patterns
description: |
  Spring Boot (Kotlin) 프레임워크 관용 패턴 레퍼런스 — 트랜잭션, JPA, 에러 처리, 유효성 검사, 설정, GraphQL
  Idiomatic Spring Boot (Kotlin) framework pattern reference covering transactions, JPA, error handling, validation, configuration, and GraphQL. Use when: implementing @Transactional or JPA mappings, designing exception handling and validation, configuring Spring Boot properties, or writing Spring for GraphQL code in Kotlin.
---

# Spring Boot (Kotlin) 관용 패턴 레퍼런스

## 1. @Transactional 시맨틱

### Propagation 종류

| Propagation | 동작 | 사용 시기 |
|---|---|---|
| `REQUIRED` (기본값) | 기존 트랜잭션 있으면 참여, 없으면 새로 생성 | 대부분의 서비스 메서드 |
| `REQUIRES_NEW` | 항상 새 트랜잭션 생성, 기존 트랜잭션 일시 중단 | 감사 로그, 알림 등 독립 작업 |
| `NESTED` | 기존 트랜잭션 내 세이브포인트 생성 | 부분 롤백이 필요한 배치 처리 |

```kotlin
@Service
class OrderService(
    private val orderRepository: OrderRepository,
    private val auditService: AuditService,
) {
    // REQUIRED: 기본값 — 주문 생성은 기존 트랜잭션에 참여
    @Transactional
    fun createOrder(request: CreateOrderRequest): Order {
        val order = orderRepository.save(Order.from(request))
        auditService.logCreation(order) // REQUIRES_NEW로 독립 실행
        return order
    }
}

@Service
class AuditService(private val auditRepository: AuditRepository) {
    // REQUIRES_NEW: 주문 생성이 실패해도 감사 로그는 유지
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    fun logCreation(order: Order) {
        auditRepository.save(AuditLog.of(order, AuditAction.CREATED))
    }
}
```

### Isolation Level 가이드

| Level | Dirty Read | Non-Repeatable Read | Phantom Read | 성능 |
|---|---|---|---|---|
| `READ_UNCOMMITTED` | O | O | O | 최고 |
| `READ_COMMITTED` (PostgreSQL 기본) | X | O | O | 좋음 |
| `REPEATABLE_READ` (MySQL InnoDB 기본) | X | X | O | 보통 |
| `SERIALIZABLE` | X | X | X | 낮음 |

```kotlin
// 재고 차감처럼 정합성이 중요한 경우
@Transactional(isolation = Isolation.REPEATABLE_READ)
fun deductStock(productId: Long, quantity: Int) {
    val product = productRepository.findByIdForUpdate(productId)
        ?: throw ProductNotFoundException(productId)
    product.deductStock(quantity)
}
```

### readOnly = true 사용 시기

```kotlin
// Good: 조회 전용 트랜잭션 — 플러시 스킵, Replica DB 라우팅 가능
@Transactional(readOnly = true)
fun getOrderDetail(orderId: Long): OrderDetailResponse {
    val order = orderRepository.findByIdWithItems(orderId)
        ?: throw OrderNotFoundException(orderId)
    return OrderDetailResponse.from(order)
}
```

### 주의사항

```kotlin
// Bad: private 메서드에 @Transactional — AOP 프록시가 적용되지 않음
@Service
class PaymentService {
    @Transactional
    private fun processInternal() { /* 트랜잭션 미적용! */ }
}

// Bad: self-invocation — 같은 클래스 내 호출은 프록시를 거치지 않음
@Service
class UserService(private val userRepository: UserRepository) {
    fun register(request: RegisterRequest) {
        saveUser(request) // @Transactional 무효!
    }

    @Transactional
    fun saveUser(request: RegisterRequest) {
        userRepository.save(User.from(request))
    }
}

// Good: 별도 서비스로 분리하여 프록시 경유
@Service
class UserFacade(private val userService: UserService) {
    fun register(request: RegisterRequest) {
        userService.saveUser(request) // 프록시 경유 — 트랜잭션 적용
    }
}

// Bad: checked exception은 기본적으로 롤백되지 않음
@Transactional
fun transfer(from: Long, to: Long, amount: BigDecimal) {
    // IOException 발생 시 롤백되지 않음!
}

// Good: rollbackFor 명시
@Transactional(rollbackFor = [Exception::class])
fun transfer(from: Long, to: Long, amount: BigDecimal) {
    // 모든 예외에서 롤백
}
```

---

## 2. Spring Data JPA 쿼리 패턴

### 메서드 이름 쿼리

```kotlin
interface ProductRepository : JpaRepository<Product, Long> {
    fun findByNameContainingAndPriceGreaterThan(name: String, price: BigDecimal): List<Product>
    fun findTop10ByStatusOrderByCreatedAtDesc(status: ProductStatus): List<Product>
    fun existsBySkuCode(skuCode: String): Boolean
    fun countByCategory(category: Category): Long
}
```

### @Query JPQL

```kotlin
interface OrderRepository : JpaRepository<Order, Long> {
    @Query("""
        SELECT o FROM Order o
        JOIN FETCH o.items i
        JOIN FETCH i.product
        WHERE o.userId = :userId
        AND o.status IN :statuses
        ORDER BY o.createdAt DESC
    """)
    fun findOrdersWithItems(
        @Param("userId") userId: Long,
        @Param("statuses") statuses: List<OrderStatus>,
    ): List<Order>
}
```

### QueryDSL

```kotlin
class ProductRepositoryCustomImpl(
    private val queryFactory: JPAQueryFactory,
) : ProductRepositoryCustom {

    override fun search(condition: ProductSearchCondition, pageable: Pageable): Page<Product> {
        val query = queryFactory
            .selectFrom(product)
            .where(
                nameContains(condition.name),
                categoryEq(condition.category),
                priceBetween(condition.minPrice, condition.maxPrice),
            )

        val content = query
            .offset(pageable.offset)
            .limit(pageable.pageSize.toLong())
            .orderBy(product.createdAt.desc())
            .fetch()

        val total = query.fetchCount()
        return PageImpl(content, pageable, total)
    }

    private fun nameContains(name: String?) =
        name?.let { product.name.contains(it) }

    private fun categoryEq(category: Category?) =
        category?.let { product.category.eq(it) }

    private fun priceBetween(min: BigDecimal?, max: BigDecimal?) =
        min?.let { product.price.goe(it) }?.and(max?.let { product.price.loe(it) })
}
```

### @EntityGraph로 N+1 방지

```kotlin
interface OrderRepository : JpaRepository<Order, Long> {
    // Bad: N+1 발생 — 주문마다 items를 추가 쿼리
    fun findByUserId(userId: Long): List<Order>

    // Good: EntityGraph로 한 번에 로딩
    @EntityGraph(attributePaths = ["items", "items.product"])
    fun findWithItemsByUserId(userId: Long): List<Order>
}
```

### Pageable / Slice / Page 차이

| 타입 | COUNT 쿼리 | 전체 페이지 수 | 사용 시기 |
|---|---|---|---|
| `Page<T>` | 실행 | 제공 | 관리자 페이지, 총 개수 필요 |
| `Slice<T>` | 미실행 (limit+1) | 미제공 | 무한 스크롤, "더 보기" |
| `List<T>` | 미실행 | 미제공 | 단순 목록 |

```kotlin
// Slice: 다음 페이지 존재 여부만 확인 (성능 우수)
fun findByStatus(status: OrderStatus, pageable: Pageable): Slice<Order>
```

---

## 3. @ControllerAdvice 에러 처리

### 글로벌 예외 핸들러 (RFC 7807 ProblemDetail)

```kotlin
@RestControllerAdvice
class GlobalExceptionHandler {

    @ExceptionHandler(BusinessException::class)
    fun handleBusiness(ex: BusinessException): ProblemDetail {
        val problem = ProblemDetail.forStatusAndDetail(
            ex.errorCode.status,
            ex.message ?: ex.errorCode.message,
        )
        problem.title = ex.errorCode.name
        problem.setProperty("code", ex.errorCode.code)
        problem.setProperty("timestamp", Instant.now())
        return problem
    }

    @ExceptionHandler(MethodArgumentNotValidException::class)
    fun handleValidation(ex: MethodArgumentNotValidException): ProblemDetail {
        val problem = ProblemDetail.forStatus(HttpStatus.BAD_REQUEST)
        problem.title = "VALIDATION_ERROR"
        problem.setProperty("errors", ex.bindingResult.fieldErrors.map {
            mapOf("field" to it.field, "message" to it.defaultMessage)
        })
        return problem
    }

    @ExceptionHandler(Exception::class)
    fun handleUnexpected(ex: Exception): ProblemDetail {
        log.error(ex) { "Unexpected error" }
        return ProblemDetail.forStatusAndDetail(
            HttpStatus.INTERNAL_SERVER_ERROR,
            "서버 내부 오류가 발생했습니다.",
        )
    }
}
```

### 커스텀 에러 코드 체계

```kotlin
enum class ErrorCode(
    val status: HttpStatus,
    val code: String,
    val message: String,
) {
    // 주문 도메인: ORD-xxx
    ORDER_NOT_FOUND(HttpStatus.NOT_FOUND, "ORD-001", "주문을 찾을 수 없습니다"),
    ORDER_ALREADY_CANCELLED(HttpStatus.CONFLICT, "ORD-002", "이미 취소된 주문입니다"),

    // 상품 도메인: PRD-xxx
    PRODUCT_OUT_OF_STOCK(HttpStatus.CONFLICT, "PRD-001", "재고가 부족합니다"),
    PRODUCT_NOT_FOUND(HttpStatus.NOT_FOUND, "PRD-002", "상품을 찾을 수 없습니다"),
}

open class BusinessException(
    val errorCode: ErrorCode,
    override val message: String = errorCode.message,
) : RuntimeException(message)

class OrderNotFoundException(orderId: Long) :
    BusinessException(ErrorCode.ORDER_NOT_FOUND, "주문(ID=$orderId)을 찾을 수 없습니다")
```

---

## 4. Bean Validation

### @Valid vs @Validated 차이

| 어노테이션 | 그룹 검증 | 메서드 레벨 | 제공자 |
|---|---|---|---|
| `@Valid` | 불가 | 불가 | Jakarta EE |
| `@Validated` | 가능 | 가능 | Spring |

### 커스텀 Validator

```kotlin
@Target(AnnotationTarget.FIELD)
@Retention(AnnotationRetention.RUNTIME)
@Constraint(validatedBy = [PhoneNumberValidator::class])
annotation class PhoneNumber(
    val message: String = "올바른 전화번호 형식이 아닙니다",
    val groups: Array<KClass<*>> = [],
    val payload: Array<KClass<out Payload>> = [],
)

class PhoneNumberValidator : ConstraintValidator<PhoneNumber, String> {
    private val pattern = Regex("^01[016789]-?\\d{3,4}-?\\d{4}$")
    override fun isValid(value: String?, context: ConstraintValidatorContext) =
        value == null || pattern.matches(value)
}
```

### 그룹 유효성 검사 & DTO 계층별 검증

```kotlin
interface OnCreate
interface OnUpdate

data class ProductRequest(
    @field:Null(groups = [OnCreate::class])
    @field:NotNull(groups = [OnUpdate::class])
    val id: Long?,

    @field:NotBlank(groups = [OnCreate::class, OnUpdate::class])
    @field:Size(max = 100)
    val name: String,

    @field:NotNull(groups = [OnCreate::class])
    @field:Positive
    val price: BigDecimal?,
)

@RestController
class ProductController(private val productService: ProductService) {
    @PostMapping("/products")
    fun create(@RequestBody @Validated(OnCreate::class) request: ProductRequest) =
        productService.create(request)

    @PutMapping("/products/{id}")
    fun update(@RequestBody @Validated(OnUpdate::class) request: ProductRequest) =
        productService.update(request)
}
```

---

## 5. 설정 바인딩

### @ConfigurationProperties + @ConstructorBinding

```kotlin
@ConfigurationProperties(prefix = "app.payment")
data class PaymentProperties(
    val apiKey: String,
    val secretKey: String,
    val timeout: Duration = Duration.ofSeconds(5),
    val retry: RetryProperties = RetryProperties(),
) {
    data class RetryProperties(
        val maxAttempts: Int = 3,
        val backoff: Duration = Duration.ofMillis(500),
    )
}

// application.yml
// app:
//   payment:
//     api-key: ${PAYMENT_API_KEY}
//     secret-key: ${PAYMENT_SECRET_KEY}
//     timeout: 10s
//     retry:
//       max-attempts: 5
//       backoff: 1s
```

### 프로파일별 설정 관리

```
src/main/resources/
├── application.yml            # 공통 설정
├── application-local.yml      # 로컬 개발 (H2, debug 로깅)
├── application-dev.yml        # 개발 서버
├── application-staging.yml    # 스테이징
└── application-prod.yml       # 프로덕션
```

### 환경변수 바인딩 패턴

```yaml
# application.yml — 환경변수 우선, 기본값 제공
spring:
  datasource:
    url: ${DB_URL:jdbc:postgresql://localhost:5432/mydb}
    username: ${DB_USERNAME:local}
    password: ${DB_PASSWORD:local}
```

---

## 6. Spring for GraphQL

### 기본 매핑 어노테이션

```kotlin
@Controller
class ProductController(private val productService: ProductService) {

    // Query.products 필드 매핑
    @QueryMapping
    fun products(
        @Argument category: String?,
        @Argument first: Int,
        @Argument after: String?,
    ): ProductConnection {
        return productService.findProducts(category, first, after)
    }

    // Mutation.createProduct 필드 매핑
    @MutationMapping
    fun createProduct(@Argument input: CreateProductInput): Product {
        return productService.create(input)
    }

    // Product.reviews 필드 매핑 (개별 resolve)
    @SchemaMapping(typeName = "Product", field = "reviews")
    fun reviews(product: Product): List<Review> {
        return reviewService.findByProductId(product.id)
    }
}
```

### @BatchMapping으로 N+1 방지

```kotlin
@Controller
class ProductController(
    private val reviewService: ReviewService,
    private val categoryService: CategoryService,
) {
    // N+1 방지: Product 목록의 reviews를 한 번에 조회
    @BatchMapping(typeName = "Product", field = "reviews")
    fun reviews(products: List<Product>): Map<Product, List<Review>> {
        val productIds = products.map { it.id }
        val reviewMap = reviewService.findByProductIds(productIds)
            .groupBy { it.productId }
        return products.associateWith { product ->
            reviewMap[product.id] ?: emptyList()
        }
    }

    // BatchMapping: 단일 값 매핑
    @BatchMapping(typeName = "Product", field = "category")
    fun categories(products: List<Product>): Map<Product, Category> {
        val categoryIds = products.map { it.categoryId }.distinct()
        val categoryMap = categoryService.findByIds(categoryIds)
            .associateBy { it.id }
        return products.associateWith { categoryMap[it.categoryId]!! }
    }
}
```

### DataLoader 등록 및 사용

```kotlin
@Configuration
class DataLoaderConfig {

    @Bean
    fun batchLoaderRegistry(
        reviewService: ReviewService,
    ): BatchLoaderRegistry {
        return DefaultBatchLoaderRegistry().apply {
            forTypePair(Long::class.java, List::class.java)
                .registerMappedBatchLoader { productIds, _ ->
                    Mono.fromCallable {
                        reviewService.findByProductIds(productIds.toList())
                            .groupBy { it.productId }
                    }
                }
        }
    }
}
```

### GraphQL 에러 핸들링

```kotlin
@Configuration
class GraphQlExceptionConfig {

    @Bean
    fun exceptionResolver(): DataFetcherExceptionResolver {
        return DataFetcherExceptionResolverAdapter.from { ex, env ->
            when (ex) {
                is BusinessException -> GraphqlErrorBuilder.newError(env)
                    .message(ex.message)
                    .errorType(ErrorType.BAD_REQUEST)
                    .extensions(mapOf("code" to ex.errorCode.code))
                    .build()
                is AccessDeniedException -> GraphqlErrorBuilder.newError(env)
                    .message("접근 권한이 없습니다")
                    .errorType(ErrorType.FORBIDDEN)
                    .build()
                else -> null // 기본 핸들러에 위임
            }
        }
    }
}
```

---

## 7. Kotlin Coroutines 통합

### suspend fun 컨트롤러 (Spring WebFlux)

```kotlin
@RestController
@RequestMapping("/api/orders")
class OrderController(private val orderService: OrderService) {

    // suspend fun으로 비동기 처리
    @GetMapping("/{id}")
    suspend fun getOrder(@PathVariable id: Long): OrderResponse {
        return orderService.findById(id)
    }

    // Flow로 스트리밍 응답
    @GetMapping(produces = [MediaType.TEXT_EVENT_STREAM_VALUE])
    fun streamOrders(): Flow<OrderResponse> {
        return orderService.streamRecentOrders()
    }
}
```

### 서비스 레이어에서 Dispatchers.IO 사용

```kotlin
@Service
class OrderService(
    private val orderRepository: OrderRepository,
    private val externalApiClient: ExternalApiClient,
) {
    // Good: blocking JPA 호출을 Dispatchers.IO로 래핑
    suspend fun findById(id: Long): OrderResponse {
        val order = withContext(Dispatchers.IO) {
            orderRepository.findById(id)
                .orElseThrow { OrderNotFoundException(id) }
        }
        return OrderResponse.from(order)
    }

    // Good: 병렬 실행
    suspend fun getOrderWithRecommendations(orderId: Long): OrderDetailResponse {
        return coroutineScope {
            val order = async(Dispatchers.IO) { orderRepository.findById(orderId) }
            val recommendations = async(Dispatchers.IO) { externalApiClient.getRecommendations(orderId) }
            OrderDetailResponse(order.await().orElseThrow(), recommendations.await())
        }
    }
}
```

### structured concurrency

```kotlin
// supervisorScope: 자식 코루틴 실패가 다른 자식에 전파되지 않음
suspend fun processOrderBatch(orders: List<Order>) {
    supervisorScope {
        orders.map { order ->
            async(Dispatchers.IO) {
                try {
                    processOrder(order)
                } catch (e: Exception) {
                    logger.error(e) { "주문 ${order.id} 처리 실패" }
                }
            }
        }.awaitAll()
    }
}

// Bad: GlobalScope 사용 — 구조적 동시성 위반, 누수 위험
GlobalScope.launch { processOrder(order) } // 절대 사용 금지
```

---

## 8. WebClient 패턴

### WebClient 설정 Bean

```kotlin
@Configuration
class WebClientConfig {

    @Bean
    fun paymentWebClient(): WebClient {
        val connectionProvider = ConnectionProvider.builder("payment-pool")
            .maxConnections(50)
            .maxIdleTime(Duration.ofSeconds(20))
            .build()

        val httpClient = HttpClient.create(connectionProvider)
            .responseTimeout(Duration.ofSeconds(10))

        return WebClient.builder()
            .baseUrl("https://api.payment.example.com")
            .clientConnector(ReactorClientHttpConnector(httpClient))
            .defaultHeader(HttpHeaders.CONTENT_TYPE, MediaType.APPLICATION_JSON_VALUE)
            .filter(logRequest())
            .build()
    }

    private fun logRequest(): ExchangeFilterFunction {
        return ExchangeFilterFunction.ofRequestProcessor { request ->
            logger.debug { "[WebClient] ${request.method()} ${request.url()}" }
            Mono.just(request)
        }
    }
}
```

### WebClient 에러 핸들링

```kotlin
@Service
class PaymentService(
    @Qualifier("paymentWebClient") private val webClient: WebClient,
) {
    suspend fun requestPayment(request: PaymentRequest): PaymentResponse {
        return webClient.post()
            .uri("/v1/payments")
            .bodyValue(request)
            .retrieve()
            .onStatus(HttpStatusCode::is4xxClientError) { response ->
                response.bodyToMono<String>().flatMap { body ->
                    Mono.error(PaymentClientException("결제 요청 오류: $body"))
                }
            }
            .onStatus(HttpStatusCode::is5xxServerError) { _ ->
                Mono.error(PaymentServerException("결제 서버 오류"))
            }
            .bodyToMono<PaymentResponse>()
            .retryWhen(Retry.backoff(3, Duration.ofMillis(500))
                .filter { it is PaymentServerException }
                .onRetryExhaustedThrow { _, signal ->
                    PaymentServerException("결제 서버 재시도 초과 (${signal.totalRetries()}회)")
                }
            )
            .awaitSingle()
    }
}
```

---

## 9. @ConfigurationProperties 심화

### 중첩 프로퍼티 + 유효성 검사

```kotlin
@ConfigurationProperties(prefix = "app.external")
@Validated
data class ExternalServiceProperties(
    @field:NotBlank
    val baseUrl: String,

    @field:NotBlank
    val apiKey: String,

    val timeout: TimeoutProperties = TimeoutProperties(),
    val retry: RetryProperties = RetryProperties(),
    val pool: PoolProperties = PoolProperties(),
) {
    data class TimeoutProperties(
        val connect: Duration = Duration.ofSeconds(3),
        val read: Duration = Duration.ofSeconds(10),
        val write: Duration = Duration.ofSeconds(10),
    )

    data class RetryProperties(
        @field:Min(0) @field:Max(10)
        val maxAttempts: Int = 3,
        val backoff: Duration = Duration.ofMillis(500),
    )

    data class PoolProperties(
        @field:Min(1) @field:Max(200)
        val maxConnections: Int = 50,
        val maxIdleTime: Duration = Duration.ofSeconds(30),
    )
}
```

### application.yml 바인딩

```yaml
app:
  external:
    base-url: ${EXTERNAL_API_URL:https://api.example.com}
    api-key: ${EXTERNAL_API_KEY}
    timeout:
      connect: 5s
      read: 30s
    retry:
      max-attempts: 3
      backoff: 1s
    pool:
      max-connections: 100
      max-idle-time: 20s
```

### Relaxed Binding 규칙

| YAML/properties | 환경변수 | 바인딩 대상 |
|---|---|---|
| `app.external.base-url` | `APP_EXTERNAL_BASEURL` | `baseUrl: String` |
| `app.external.timeout.connect` | `APP_EXTERNAL_TIMEOUT_CONNECT` | `timeout.connect: Duration` |
| `app.external.retry.max-attempts` | `APP_EXTERNAL_RETRY_MAXATTEMPTS` | `retry.maxAttempts: Int` |

### @ConfigurationPropertiesScan vs @EnableConfigurationProperties

```kotlin
// 방법 1: 스캔 (권장 — Application 클래스에 선언)
@SpringBootApplication
@ConfigurationPropertiesScan
class Application

// 방법 2: 명시적 등록 (특정 Configuration에서만 필요할 때)
@Configuration
@EnableConfigurationProperties(ExternalServiceProperties::class)
class ExternalServiceConfig
```
