# Testing Patterns — Kotest, MockK, Spring Boot Test

Kotlin + Spring Boot 프로젝트의 테스트 작성 패턴과 전략.

---

## 테스트 피라미드

```
        ╱ E2E ╲               ~5%  — @SpringBootTest + TestRestTemplate
       ╱ Integration ╲        ~15% — @WebMvcTest, @DataJpaTest
      ╱ Unit Tests    ╲       ~80% — Kotest + MockK
     ────────────────────
```

| 레벨 | 어노테이션 | 용도 | 속도 |
|------|-----------|------|------|
| Unit | 없음 (순수 Kotest + MockK) | Service 비즈니스 로직 | 가장 빠름 |
| Slice | `@WebMvcTest` | Controller HTTP 매핑, 검증 | 빠름 |
| Slice | `@DataJpaTest` | Repository 쿼리, Entity 매핑 | 중간 |
| Full | `@SpringBootTest` | 전체 스택 통합 | 느림 |

---

## Kotest Spec 스타일 선택

### BehaviorSpec — BDD 스타일 (권장)

Given/When/Then 구조로 시나리오 기반 테스트 작성.

```kotlin
class OrderServiceTest : BehaviorSpec({
    val orderRepository = mockk<OrderRepository>()
    val service = OrderServiceImpl(orderRepository)

    afterEach { clearAllMocks() }

    Given("존재하는 주문 ID") {
        val entity = OrderEntity(id = 1L, name = "테스트 주문")
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

### FunSpec — 간결한 스타일

단순한 함수 레벨 테스트에 적합.

```kotlin
class OrderValidatorTest : FunSpec({
    test("유효한 주문은 통과한다") {
        val request = CreateOrderRequest(name = "테스트", amount = BigDecimal(1000))
        // 예외 없이 통과
        request.validate()
    }

    test("빈 이름은 실패한다") {
        shouldThrow<IllegalArgumentException> {
            CreateOrderRequest(name = "", amount = BigDecimal(1000)).validate()
        }
    }
})
```

### 스타일 선택 가이드

| 상황 | Spec 스타일 | 이유 |
|------|------------|------|
| Service 비즈니스 로직 | BehaviorSpec | 시나리오 기반, 상태 전이 표현 |
| 유틸리티/헬퍼 함수 | FunSpec | 간결, 상태 없음 |
| 데이터 기반 테스트 | FunSpec + forAll | property-based testing |
| 상태 머신/워크플로우 | BehaviorSpec | Given 상태 → When 동작 → Then 결과 |

---

## MockK 패턴

### 기본 Mock 사용

```kotlin
val orderRepository = mockk<OrderRepository>()

// 반환값 설정
every { orderRepository.findByIdOrNull(1L) } returns orderEntity
every { orderRepository.save(any()) } returnsArgument 0  // 입력값 그대로 반환
every { orderRepository.findAll(any<Pageable>()) } returns pageOf(orderEntity)

// void 반환 메서드
every { orderRepository.deleteById(any()) } just runs

// 예외 발생
every { orderRepository.findByIdOrNull(999L) } throws EntityNotFoundException("Not found")
```

### 검증 (Verify)

```kotlin
// 호출 확인
verify(exactly = 1) { orderRepository.save(any()) }
verify { orderRepository.deleteById(1L) }

// 호출되지 않음 확인
verify(exactly = 0) { orderRepository.deleteById(any()) }

// 호출 순서 검증
verifyOrder {
    orderRepository.findByIdOrNull(1L)
    orderRepository.save(any())
}
```

### Capture — 인자 캡처

```kotlin
val slot = slot<OrderEntity>()
every { orderRepository.save(capture(slot)) } returnsArgument 0

service.create(CreateOrderRequest(name = "테스트", amount = BigDecimal(1000)))

// 저장된 Entity 검증
slot.captured.name shouldBe "테스트"
slot.captured.amount shouldBe BigDecimal(1000)
slot.captured.status shouldBe OrderStatus.CREATED
```

### relaxed Mock

```kotlin
// 모든 메서드에 기본값 반환 (0, "", false, null, emptyList 등)
val relaxedMock = mockk<OrderRepository>(relaxed = true)

// relaxUnitFun — Unit 반환 메서드만 자동 처리
val mock = mockk<OrderRepository>(relaxUnitFun = true)
```

---

## Controller 테스트 — @WebMvcTest

### 기본 패턴

```kotlin
@WebMvcTest(OrderController::class)
class OrderControllerTest(
    @Autowired val mockMvc: MockMvc,
    @MockkBean val orderService: OrderService,
) : BehaviorSpec({
    val objectMapper = jacksonObjectMapper().apply {
        registerModule(JavaTimeModule())
        disable(SerializationFeature.WRITE_DATES_AS_TIMESTAMPS)
    }

    Given("주문 생성 요청") {
        val request = CreateOrderRequest(name = "새 주문", amount = BigDecimal(5000))
        val response = OrderResponse(
            id = 1L, name = "새 주문", amount = BigDecimal(5000),
            status = OrderStatus.CREATED,
            createdAt = LocalDateTime.now(), updatedAt = LocalDateTime.now(),
        )
        every { orderService.create(any()) } returns response

        When("POST /api/v1/orders") {
            val result = mockMvc.perform(
                post("/api/v1/orders")
                    .contentType(MediaType.APPLICATION_JSON)
                    .content(objectMapper.writeValueAsString(request))
            )

            Then("201 Created를 반환한다") {
                result
                    .andExpect(status().isCreated)
                    .andExpect(header().exists("Location"))
                    .andExpect(jsonPath("$.id").value(1))
                    .andExpect(jsonPath("$.name").value("새 주문"))
                    .andExpect(jsonPath("$.status").value("CREATED"))
            }
        }
    }

    Given("유효하지 않은 요청 바디") {
        When("빈 이름으로 POST 호출") {
            val result = mockMvc.perform(
                post("/api/v1/orders")
                    .contentType(MediaType.APPLICATION_JSON)
                    .content("""{"name":"","amount":5000}""")
            )

            Then("400 Bad Request를 반환한다") {
                result
                    .andExpect(status().isBadRequest)
                    .andExpect(jsonPath("$.title").value("Validation Failed"))
            }
        }
    }

    Given("존재하지 않는 주문 ID") {
        every { orderService.findById(999L) } throws OrderNotFoundException(999L)

        When("GET /api/v1/orders/999") {
            val result = mockMvc.perform(get("/api/v1/orders/999"))

            Then("404 Not Found를 반환한다") {
                result
                    .andExpect(status().isNotFound)
                    .andExpect(jsonPath("$.detail").exists())
            }
        }
    }
})
```

### @MockkBean vs @MockBean

```kotlin
// ✅ MockK 사용 시 — @MockkBean (springmockk 의존성 필요)
@MockkBean val orderService: OrderService

// JUnit Mockito 사용 시 — @MockBean
@MockBean lateinit var orderService: OrderService
```

**의존성:** `com.ninja-squad:springmockk` (springmockk)

---

## Repository 테스트 — @DataJpaTest

### 기본 패턴

```kotlin
@DataJpaTest
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
class OrderRepositoryTest(
    @Autowired val orderRepository: OrderRepository,
    @Autowired val entityManager: EntityManager,
) : BehaviorSpec({

    Given("여러 상태의 주문이 존재할 때") {
        val created = orderRepository.save(
            OrderEntity(name = "주문1", status = OrderStatus.CREATED)
        )
        val confirmed = orderRepository.save(
            OrderEntity(name = "주문2", status = OrderStatus.CONFIRMED)
        )
        entityManager.flush()
        entityManager.clear()  // 영속성 컨텍스트 초기화 → DB에서 조회 확인

        When("CREATED 상태로 필터링") {
            val results = orderRepository.findByStatus(OrderStatus.CREATED)

            Then("해당 상태 주문만 반환한다") {
                results shouldHaveSize 1
                results[0].name shouldBe "주문1"
            }
        }
    }

    Given("주문이 없을 때") {
        When("전체 조회") {
            val results = orderRepository.findAll()

            Then("빈 목록을 반환한다") {
                results.shouldBeEmpty()
            }
        }
    }
})
```

### H2 vs 실제 DB

| 방식 | 장점 | 단점 | 권장 시점 |
|------|------|------|----------|
| H2 (기본) | 빠른 실행, 의존성 없음 | DB 방언 차이 | 단순 CRUD 테스트 |
| Testcontainers | 실제 DB와 동일 | 느림, Docker 필요 | 복잡한 쿼리, DB 기능 테스트 |

```kotlin
// Testcontainers 사용
@DataJpaTest
@Testcontainers
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
class OrderRepositoryTest : BehaviorSpec({
    companion object {
        @Container
        val postgres = PostgreSQLContainer("postgres:16-alpine").apply {
            withDatabaseName("testdb")
        }

        @JvmStatic
        @DynamicPropertySource
        fun properties(registry: DynamicPropertyRegistry) {
            registry.add("spring.datasource.url") { postgres.jdbcUrl }
            registry.add("spring.datasource.username") { postgres.username }
            registry.add("spring.datasource.password") { postgres.password }
        }
    }
})
```

---

## 통합 테스트 — @SpringBootTest

### 전체 스택 테스트

```kotlin
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class OrderIntegrationTest(
    @Autowired val restTemplate: TestRestTemplate,
    @Autowired val orderRepository: OrderRepository,
) : BehaviorSpec({

    afterEach { orderRepository.deleteAll() }

    Given("빈 데이터베이스") {
        When("주문 생성 API 호출") {
            val request = CreateOrderRequest(name = "통합테스트 주문", amount = BigDecimal(10000))
            val response = restTemplate.postForEntity(
                "/api/v1/orders",
                request,
                OrderResponse::class.java,
            )

            Then("201 Created와 주문 정보를 반환한다") {
                response.statusCode shouldBe HttpStatus.CREATED
                response.body!!.name shouldBe "통합테스트 주문"
            }

            Then("DB에 저장되었다") {
                val saved = orderRepository.findAll()
                saved shouldHaveSize 1
                saved[0].name shouldBe "통합테스트 주문"
            }
        }
    }
})
```

---

## 테스트 유틸리티 패턴

### Test Fixture Factory

```kotlin
// src/test/kotlin/com/example/fixture/OrderFixture.kt
object OrderFixture {

    fun entity(
        id: Long = 0L,
        name: String = "테스트 주문",
        amount: BigDecimal = BigDecimal(10000),
        status: OrderStatus = OrderStatus.CREATED,
    ) = OrderEntity(
        id = id,
        name = name,
        amount = amount,
        status = status,
    )

    fun createRequest(
        name: String = "테스트 주문",
        amount: BigDecimal = BigDecimal(10000),
    ) = CreateOrderRequest(name = name, amount = amount)

    fun response(
        id: Long = 1L,
        name: String = "테스트 주문",
        amount: BigDecimal = BigDecimal(10000),
        status: OrderStatus = OrderStatus.CREATED,
    ) = OrderResponse(
        id = id, name = name, amount = amount, status = status,
        createdAt = LocalDateTime.now(), updatedAt = LocalDateTime.now(),
    )
}

// 사용
class OrderServiceTest : BehaviorSpec({
    Given("주문이 존재할 때") {
        val entity = OrderFixture.entity(id = 1L)
        every { repository.findByIdOrNull(1L) } returns entity
        // ...
    }
})
```

### Kotest Matchers

```kotlin
// 기본 매처
result shouldBe expected
result shouldNotBe unexpected
result.shouldBeNull()
result.shouldNotBeNull()

// 컬렉션 매처
list shouldHaveSize 3
list.shouldContain(item)
list.shouldBeEmpty()
list shouldContainAll listOf(a, b, c)

// 예외 매처
shouldThrow<OrderNotFoundException> { service.findById(999L) }
    .message shouldContain "999"

// 숫자 매처
score shouldBeGreaterThan 80.0
score shouldBeInRange 0.0..100.0
amount.shouldBePositive()

// 문자열 매처
name shouldStartWith "Order"
name shouldHaveLength 10
name.shouldNotBeBlank()
```

---

## 공통 실수와 해결

### 1. Spring Context 로딩 최소화

```kotlin
// ❌ BAD: 모든 테스트에 @SpringBootTest — 느림
@SpringBootTest
class OrderServiceTest  // Service 단위 테스트에 전체 컨텍스트 불필요

// ✅ GOOD: 순수 단위 테스트 — Spring 없이
class OrderServiceTest : BehaviorSpec({
    val repository = mockk<OrderRepository>()
    val service = OrderServiceImpl(repository)
    // ...
})
```

### 2. 테스트 격리

```kotlin
// ❌ BAD: 테스트 간 상태 공유
class OrderServiceTest : BehaviorSpec({
    val repository = mockk<OrderRepository>()
    val service = OrderServiceImpl(repository)
    // mock이 이전 테스트의 stubbing을 유지

    // ✅ GOOD: 매 테스트 후 mock 초기화
    afterEach { clearAllMocks() }
})
```

### 3. @Transactional in Tests

```kotlin
// @DataJpaTest는 기본적으로 @Transactional
// → 각 테스트 후 자동 롤백 (DB 상태 격리)

// ❌ BAD: @SpringBootTest + @Transactional — 실제 트랜잭션 동작과 다름
@SpringBootTest
@Transactional  // API 호출 시 별도 트랜잭션 문제
class OrderIntegrationTest

// ✅ GOOD: @SpringBootTest에서는 수동 정리
@SpringBootTest
class OrderIntegrationTest {
    @AfterEach fun cleanup() { orderRepository.deleteAll() }
}
```

### 4. 비동기 테스트

```kotlin
// Coroutine 테스트
class OrderServiceTest : BehaviorSpec({
    Given("비동기 주문 처리") {
        When("주문 생성") {
            Then("결과를 반환한다") {
                runBlocking {
                    val result = service.createAsync(request)
                    result.status shouldBe OrderStatus.CREATED
                }
            }
        }
    }
})
```
