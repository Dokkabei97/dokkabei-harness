---
name: backend-testing-patterns
description: |
  백엔드 테스트 설정 & 패턴 레퍼런스 — Spring Boot 슬라이스, MockK, Kotest, FastAPI, pytest, Testcontainers, GraphQL 테스트
  Reference for backend test setup and patterns — Spring Boot slice tests, MockK, Kotest, FastAPI, pytest, Testcontainers, and GraphQL testing. Use when: setting up backend tests, choosing slice vs full-context tests, mocking with MockK or pytest-mock, using Testcontainers.
---

# 백엔드 테스트 설정 & 패턴 레퍼런스

## 1. Spring Boot 테스트 슬라이스 의사결정 트리

```
[무엇을 테스트하는가?]
│
├─ Controller (HTTP 요청/응답, 직렬화)
│   └─ @WebMvcTest → MockMvc 사용, Service는 mock
│
├─ Repository (쿼리 정확성, JPA 매핑)
│   └─ @DataJpaTest → H2 또는 Testcontainers, EntityManager
│
├─ 전체 통합 (서비스 흐름, 실제 빈 조합)
│   └─ @SpringBootTest → 전체 컨텍스트, 실 DB 권장
│
├─ GraphQL (스키마 + resolver)
│   └─ @GraphQlTest → GraphQlTester, Service는 mock
│
├─ 서비스 로직 (비즈니스 규칙)
│   └─ 슬라이스 불필요 → 순수 단위 테스트 + MockK
│
└─ 외부 API 연동
    └─ @RestClientTest → MockRestServiceServer 또는 WireMock
```

### @WebMvcTest 예시 (Kotlin + Kotest)

```kotlin
@WebMvcTest(ProductController::class)
class ProductControllerTest(
    @Autowired private val mockMvc: MockMvc,
    @MockkBean private val productService: ProductService,
) : BehaviorSpec({

    Given("상품이 존재할 때") {
        val product = ProductResponse(id = 1, name = "테스트 상품", price = 10000)
        every { productService.getById(1L) } returns product

        When("상품 상세를 조회하면") {
            val result = mockMvc.get("/api/products/1") {
                accept = MediaType.APPLICATION_JSON
            }

            Then("200 OK와 상품 정보를 반환한다") {
                result.andExpect {
                    status { isOk() }
                    jsonPath("$.name") { value("테스트 상품") }
                    jsonPath("$.price") { value(10000) }
                }
            }
        }
    }

    Given("존재하지 않는 상품 ID로 조회할 때") {
        every { productService.getById(999L) } throws ProductNotFoundException(999L)

        When("상품 상세를 조회하면") {
            val result = mockMvc.get("/api/products/999")

            Then("404 Not Found를 반환한다") {
                result.andExpect { status { isNotFound() } }
            }
        }
    }
})
```

### @DataJpaTest 예시

```kotlin
@DataJpaTest
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
@Testcontainers
class ProductRepositoryTest(
    @Autowired private val productRepository: ProductRepository,
    @Autowired private val entityManager: TestEntityManager,
) : FunSpec({

    test("카테고리별 상품 조회") {
        // given
        val electronics = entityManager.persist(Category(name = "전자기기"))
        entityManager.persist(Product(name = "노트북", category = electronics))
        entityManager.persist(Product(name = "키보드", category = electronics))
        entityManager.flush()
        entityManager.clear()

        // when
        val products = productRepository.findByCategory(electronics)

        // then
        products shouldHaveSize 2
        products.map { it.name } shouldContainExactlyInAnyOrder listOf("노트북", "키보드")
    }

    companion object {
        @Container
        @JvmStatic
        val postgres = PostgreSQLContainer("postgres:16-alpine")

        @DynamicPropertySource
        @JvmStatic
        fun properties(registry: DynamicPropertyRegistry) {
            registry.add("spring.datasource.url") { postgres.jdbcUrl }
            registry.add("spring.datasource.username") { postgres.username }
            registry.add("spring.datasource.password") { postgres.password }
        }
    }
})
```

### @SpringBootTest 예시

```kotlin
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class OrderIntegrationTest(
    @Autowired private val restTemplate: TestRestTemplate,
    @Autowired private val orderRepository: OrderRepository,
) : BehaviorSpec({

    Given("인증된 사용자가 상품을 주문할 때") {
        When("주문 생성 API를 호출하면") {
            val request = CreateOrderRequest(productId = 1, quantity = 2)
            val response = restTemplate.postForEntity<OrderResponse>(
                "/api/orders", request
            )

            Then("201 Created와 주문 정보를 반환한다") {
                response.statusCode shouldBe HttpStatus.CREATED
                response.body!!.status shouldBe OrderStatus.CREATED
            }

            Then("DB에 주문이 저장된다") {
                val orders = orderRepository.findAll()
                orders shouldHaveSize 1
            }
        }
    }
})
```

---

## 2. MockK 패턴

### 기본: every / verify

```kotlin
@Test
fun `주문 생성 시 재고를 차감한다`() {
    // given
    val productService = mockk<ProductService>()
    val orderRepository = mockk<OrderRepository>()
    val orderService = OrderService(productService, orderRepository)

    every { productService.deductStock(1L, 2) } just Runs
    every { orderRepository.save(any()) } returns Order(id = 1L, status = OrderStatus.CREATED)

    // when
    orderService.createOrder(CreateOrderRequest(productId = 1L, quantity = 2))

    // then
    verify(exactly = 1) { productService.deductStock(1L, 2) }
    verify { orderRepository.save(match { it.status == OrderStatus.CREATED }) }
}
```

### 코루틴: coEvery / coVerify

```kotlin
@Test
fun `비동기 알림 전송`() = runTest {
    val notificationService = mockk<NotificationService>()
    coEvery { notificationService.sendAsync(any()) } just Runs

    // when
    notificationService.sendAsync(Notification("주문 완료"))

    // then
    coVerify { notificationService.sendAsync(match { it.message == "주문 완료" }) }
}
```

### slot capture

```kotlin
@Test
fun `저장되는 주문 데이터를 검증한다`() {
    val slot = slot<Order>()
    every { orderRepository.save(capture(slot)) } answers { slot.captured }

    orderService.createOrder(request)

    slot.captured.userId shouldBe 42L
    slot.captured.totalAmount shouldBe BigDecimal("20000")
}
```

### relaxed mock & spy

```kotlin
// relaxed: 모든 메서드가 기본값 반환 (설정 없이 사용 가능)
val logger = mockk<AuditLogger>(relaxed = true)

// spy: 실제 객체를 감싸서 특정 메서드만 오버라이드
val realService = ProductService(repository)
val spyService = spyk(realService) {
    every { calculateDiscount(any()) } returns BigDecimal("1000")
}
```

---

## 3. Kotest 스펙 가이드

### BehaviorSpec — Given/When/Then (인수 테스트, 시나리오 중심)

```kotlin
class OrderServiceTest : BehaviorSpec({
    Given("재고가 충분한 상품이 있을 때") {
        When("주문을 생성하면") {
            Then("주문이 성공한다") { /* ... */ }
            Then("재고가 차감된다") { /* ... */ }
        }
        When("재고보다 많은 수량을 주문하면") {
            Then("재고 부족 예외가 발생한다") { /* ... */ }
        }
    }
})
```

### FunSpec — 단순 test 블록 (단위 테스트, 유틸리티)

```kotlin
class PriceCalculatorTest : FunSpec({
    test("할인율 적용 시 최종 가격 계산") {
        val result = PriceCalculator.apply(10000, discountRate = 0.1)
        result shouldBe 9000
    }

    test("할인율이 0이면 원래 가격 반환") {
        val result = PriceCalculator.apply(10000, discountRate = 0.0)
        result shouldBe 10000
    }
})
```

### DescribeSpec — describe/it (RSpec 스타일, 클래스/메서드 단위)

```kotlin
class ProductTest : DescribeSpec({
    describe("Product.deductStock") {
        it("요청 수량만큼 재고를 차감한다") {
            val product = Product(stock = 10)
            product.deductStock(3)
            product.stock shouldBe 7
        }

        it("재고 부족 시 예외를 던진다") {
            val product = Product(stock = 2)
            shouldThrow<InsufficientStockException> {
                product.deductStock(5)
            }
        }
    }
})
```

### 스펙 선택 기준

| 스펙 | 사용 시기 |
|---|---|
| `BehaviorSpec` | 비즈니스 시나리오, 인수 테스트, 복잡한 흐름 |
| `FunSpec` | 단위 테스트, 유틸리티, 간단한 검증 |
| `DescribeSpec` | 클래스/메서드 단위 행동 명세 |

---

## 4. FastAPI 테스트

### TestClient 동기 테스트

```python
from fastapi.testclient import TestClient
from app.main import app

client = TestClient(app)

def test_상품_목록_조회():
    response = client.get("/api/products", params={"category": "electronics"})
    assert response.status_code == 200
    data = response.json()
    assert len(data["items"]) > 0
```

### httpx.AsyncClient 비동기 테스트

```python
import pytest
from httpx import ASGITransport, AsyncClient
from app.main import app

@pytest.mark.anyio
async def test_상품_생성():
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.post(
            "/api/products",
            json={"name": "테스트 상품", "price": 10000},
            headers={"Authorization": "Bearer test-token"},
        )
    assert response.status_code == 201
    assert response.json()["name"] == "테스트 상품"
```

### override_dependency로 DI 교체

```python
from app.dependencies import get_db, get_current_user

# 가짜 DB 세션
async def override_get_db():
    async with test_async_session_maker() as session:
        yield session

# 가짜 인증 사용자
async def override_get_current_user():
    return User(id=1, email="test@example.com", is_admin=False)

app.dependency_overrides[get_db] = override_get_db
app.dependency_overrides[get_current_user] = override_get_current_user
```

### 인증 모킹 패턴

```python
@pytest.fixture
def admin_client():
    """관리자 권한 테스트 클라이언트"""
    async def override_user():
        return User(id=1, email="admin@example.com", is_admin=True)

    app.dependency_overrides[get_current_user] = override_user
    yield TestClient(app)
    app.dependency_overrides.clear()

def test_관리자_전용_API(admin_client):
    response = admin_client.delete("/api/products/1")
    assert response.status_code == 200
```

---

## 5. pytest 픽스처

### conftest.py 구조

```
tests/
├── conftest.py              # 전역 픽스처 (DB 엔진, 세션, 인증)
├── unit/
│   ├── conftest.py          # 단위 테스트 픽스처
│   └── test_price_calculator.py
├── integration/
│   ├── conftest.py          # 통합 테스트 픽스처 (Testcontainers)
│   └── test_order_flow.py
└── e2e/
    └── test_api.py
```

### scope 종류

```python
@pytest.fixture(scope="session")
def db_engine():
    """세션 전체에서 엔진 1개 공유"""
    engine = create_async_engine(TEST_DATABASE_URL)
    yield engine

@pytest.fixture(scope="function")
async def db_session(db_engine):
    """테스트 함수마다 새 세션 + 롤백"""
    async with AsyncSession(db_engine) as session:
        async with session.begin():
            yield session
            await session.rollback()
```

### fixture factory 패턴

```python
@pytest.fixture
def create_user(db_session):
    """사용자 생성 팩토리 — 테스트마다 다른 데이터 생성"""
    created_users = []

    async def _create_user(
        email: str = "test@example.com",
        name: str = "테스트 유저",
        is_admin: bool = False,
    ) -> User:
        user = User(email=email, name=name, is_admin=is_admin)
        db_session.add(user)
        await db_session.flush()
        created_users.append(user)
        return user

    return _create_user

# 사용
async def test_사용자_주문(create_user, db_session):
    user = await create_user(email="buyer@test.com")
    # ...
```

### DB 세션 픽스처 (Testcontainers)

```python
# tests/conftest.py
import pytest
from testcontainers.postgres import PostgresContainer

@pytest.fixture(scope="session")
def postgres_container():
    with PostgresContainer("postgres:16-alpine") as pg:
        yield pg

@pytest.fixture(scope="session")
def db_engine(postgres_container):
    url = postgres_container.get_connection_url().replace(
        "psycopg2", "asyncpg"
    )
    engine = create_async_engine(url)
    yield engine
```

---

## 6. Testcontainers

### Spring Boot (Kotlin)

```kotlin
@SpringBootTest
@Testcontainers
class IntegrationTestBase {

    companion object {
        @Container
        @JvmStatic
        val postgres = PostgreSQLContainer("postgres:16-alpine")

        @Container
        @JvmStatic
        val redis = GenericContainer("redis:7-alpine").withExposedPorts(6379)

        @Container
        @JvmStatic
        val kafka = KafkaContainer(DockerImageName.parse("confluentinc/cp-kafka:7.5.0"))

        @DynamicPropertySource
        @JvmStatic
        fun configureProperties(registry: DynamicPropertyRegistry) {
            // PostgreSQL
            registry.add("spring.datasource.url") { postgres.jdbcUrl }
            registry.add("spring.datasource.username") { postgres.username }
            registry.add("spring.datasource.password") { postgres.password }
            // Redis
            registry.add("spring.data.redis.host") { redis.host }
            registry.add("spring.data.redis.port") { redis.getMappedPort(6379) }
            // Kafka
            registry.add("spring.kafka.bootstrap-servers") { kafka.bootstrapServers }
        }
    }
}
```

### Python (conftest.py)

```python
import pytest
from testcontainers.postgres import PostgresContainer
from testcontainers.redis import RedisContainer
from testcontainers.kafka import KafkaContainer

@pytest.fixture(scope="session")
def postgres():
    with PostgresContainer("postgres:16-alpine") as pg:
        yield pg

@pytest.fixture(scope="session")
def redis():
    with RedisContainer("redis:7-alpine") as r:
        yield r

@pytest.fixture(scope="session")
def kafka():
    with KafkaContainer("confluentinc/cp-kafka:7.5.0") as k:
        yield k

@pytest.fixture(scope="session")
def db_url(postgres):
    return postgres.get_connection_url().replace("psycopg2", "asyncpg")
```

---

## 7. GraphQL 테스트 패턴

### Spring @GraphQlTest + GraphQlTester

```kotlin
@GraphQlTest(ProductController::class)
class ProductGraphQlTest(
    @Autowired private val graphQlTester: GraphQlTester,
    @MockkBean private val productService: ProductService,
) : BehaviorSpec({

    Given("상품이 존재할 때") {
        every { productService.findById(1L) } returns Product(
            id = 1L, name = "테스트 상품", price = 10000
        )

        When("상품 Query를 실행하면") {
            val result = graphQlTester
                .documentName("product-by-id")  // graphql-test/product-by-id.graphql
                .variable("id", 1)
                .execute()

            Then("상품 정보를 반환한다") {
                result.path("product.name").entity(String::class.java)
                    .isEqualTo("테스트 상품")
                result.path("product.price").entity(Int::class.java)
                    .isEqualTo(10000)
            }
        }
    }

    Given("상품 생성 Mutation") {
        every { productService.create(any()) } returns Product(
            id = 2L, name = "새 상품", price = 5000
        )

        When("createProduct mutation을 실행하면") {
            val result = graphQlTester.document("""
                mutation {
                    createProduct(input: { name: "새 상품", price: 5000, categoryId: 1 }) {
                        id
                        name
                    }
                }
            """.trimIndent()).execute()

            Then("생성된 상품을 반환한다") {
                result.path("createProduct.name").entity(String::class.java)
                    .isEqualTo("새 상품")
            }
        }
    }
})
```

### GraphQL 테스트 문서 파일

```graphql
# src/test/resources/graphql-test/product-by-id.graphql
query ProductById($id: ID!) {
    product(id: $id) {
        id
        name
        price
        category {
            name
        }
    }
}
```

### Strawberry Test Client (Python)

```python
import pytest
from strawberry.test import BaseGraphQLTestClient
from app.schema import schema

class TestClient(BaseGraphQLTestClient):
    def __init__(self):
        super().__init__(schema)

@pytest.fixture
def gql_client():
    return TestClient()

def test_상품_조회(gql_client):
    result = gql_client.query("""
        query {
            products(first: 10) {
                edges {
                    node {
                        id
                        name
                        price
                    }
                }
            }
        }
    """)
    assert not result.errors
    assert len(result.data["products"]["edges"]) > 0

def test_상품_생성(gql_client):
    result = gql_client.query(
        """
        mutation CreateProduct($input: CreateProductInput!) {
            createProduct(input: $input) {
                id
                name
            }
        }
        """,
        variables={"input": {"name": "새 상품", "price": 5000, "categoryId": 1}},
    )
    assert not result.errors
    assert result.data["createProduct"]["name"] == "새 상품"

@pytest.mark.anyio
async def test_subscription(gql_client):
    """Subscription 테스트"""
    async for result in gql_client.subscribe("""
        subscription {
            orderStatusChanged(orderId: 1) {
                status
            }
        }
    """):
        assert result.data["orderStatusChanged"]["status"] in [
            "CREATED", "CONFIRMED", "SHIPPED"
        ]
        break  # 첫 번째 이벤트만 확인
```

---

## 8. Testcontainers Kafka/Redis 패턴

### Spring Boot: Kafka 통합 테스트

```kotlin
@SpringBootTest
@Testcontainers
class OrderEventIntegrationTest(
    @Autowired private val kafkaTemplate: KafkaTemplate<String, OrderEvent>,
    @Autowired private val orderRepository: OrderRepository,
) : BehaviorSpec({

    Given("주문 완료 이벤트가 발행될 때") {
        val event = OrderEvent(orderId = 1L, status = "COMPLETED", amount = 10000)

        When("Kafka Consumer가 이벤트를 수신하면") {
            kafkaTemplate.send("order.completed", event.orderId.toString(), event).get()

            Then("주문 상태가 업데이트된다") {
                // Consumer 처리 대기
                eventually(5.seconds) {
                    val order = orderRepository.findById(1L).orElseThrow()
                    order.status shouldBe OrderStatus.COMPLETED
                }
            }
        }
    }

    companion object {
        @Container
        @JvmStatic
        val kafka = KafkaContainer(DockerImageName.parse("confluentinc/cp-kafka:7.5.0"))

        @DynamicPropertySource
        @JvmStatic
        fun kafkaProperties(registry: DynamicPropertyRegistry) {
            registry.add("spring.kafka.bootstrap-servers") { kafka.bootstrapServers }
        }
    }
})
```

### Spring Boot: Redis 통합 테스트

```kotlin
@SpringBootTest
@Testcontainers
class ProductCacheTest(
    @Autowired private val productService: ProductService,
    @Autowired private val redisTemplate: StringRedisTemplate,
) : BehaviorSpec({

    Given("상품이 캐시되지 않은 상태에서") {
        redisTemplate.delete("product::1")

        When("상품을 조회하면") {
            productService.findById(1L)

            Then("캐시에 저장된다") {
                val cached = redisTemplate.opsForValue().get("product::1")
                cached.shouldNotBeNull()
            }
        }
    }

    companion object {
        @Container
        @JvmStatic
        val redis = GenericContainer("redis:7-alpine").withExposedPorts(6379)

        @DynamicPropertySource
        @JvmStatic
        fun redisProperties(registry: DynamicPropertyRegistry) {
            registry.add("spring.data.redis.host") { redis.host }
            registry.add("spring.data.redis.port") { redis.getMappedPort(6379) }
        }
    }
})
```

### Python: Kafka 테스트 픽스처

```python
import pytest
from testcontainers.kafka import KafkaContainer
from aiokafka import AIOKafkaProducer, AIOKafkaConsumer

@pytest.fixture(scope="session")
def kafka_container():
    with KafkaContainer("confluentinc/cp-kafka:7.5.0") as kafka:
        yield kafka

@pytest.fixture
async def kafka_producer(kafka_container):
    producer = AIOKafkaProducer(
        bootstrap_servers=kafka_container.get_bootstrap_server(),
        value_serializer=lambda v: json.dumps(v).encode(),
    )
    await producer.start()
    yield producer
    await producer.stop()

@pytest.mark.anyio
async def test_이벤트_발행_및_수신(kafka_producer, kafka_container):
    # 이벤트 발행
    await kafka_producer.send_and_wait(
        "order.completed",
        value={"order_id": 1, "status": "COMPLETED"},
    )

    # 이벤트 수신 확인
    consumer = AIOKafkaConsumer(
        "order.completed",
        bootstrap_servers=kafka_container.get_bootstrap_server(),
        auto_offset_reset="earliest",
        group_id="test-group",
    )
    await consumer.start()
    try:
        msg = await asyncio.wait_for(consumer.getone(), timeout=10)
        data = json.loads(msg.value)
        assert data["order_id"] == 1
    finally:
        await consumer.stop()
```

### Python: Redis 테스트 픽스처

```python
import pytest
from testcontainers.redis import RedisContainer
import redis.asyncio as aioredis

@pytest.fixture(scope="session")
def redis_container():
    with RedisContainer("redis:7-alpine") as r:
        yield r

@pytest.fixture
async def redis_client(redis_container):
    url = f"redis://{redis_container.get_container_host_ip()}:{redis_container.get_exposed_port(6379)}"
    client = aioredis.from_url(url)
    yield client
    await client.flushdb()
    await client.aclose()

@pytest.mark.anyio
async def test_캐시_저장_조회(redis_client):
    await redis_client.set("product:1", '{"name": "테스트"}', ex=60)
    result = await redis_client.get("product:1")
    assert json.loads(result)["name"] == "테스트"
```

### 테스트 격리: 토픽/키 네이밍

```kotlin
// Kotlin: 테스트 클래스별 고유 토픽
companion object {
    val testTopic = "order.completed.${UUID.randomUUID().toString().take(8)}"
}

// Python: 테스트별 고유 Redis 키 프리픽스
@pytest.fixture
def cache_prefix():
    return f"test:{uuid.uuid4().hex[:8]}"
```

---

## 9. E2E API 시나리오 테스트

### 다단계 API 시나리오 (Kotlin)

```kotlin
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class OrderE2ETest(
    @Autowired private val restTemplate: TestRestTemplate,
) : BehaviorSpec({

    Given("인증된 사용자가 주문 플로우를 진행할 때") {
        val headers = HttpHeaders().apply {
            setBearerAuth("test-jwt-token")
        }

        When("상품 생성 → 주문 생성 → 조회 → 취소 시나리오를 실행하면") {
            // Step 1: 상품 생성
            val productResponse = restTemplate.exchange<ProductResponse>(
                "/api/products", HttpMethod.POST,
                HttpEntity(CreateProductRequest("테스트 상품", 10000), headers),
            )
            productResponse.statusCode shouldBe HttpStatus.CREATED
            val productId = productResponse.body!!.id

            // Step 2: 주문 생성
            val orderResponse = restTemplate.exchange<OrderResponse>(
                "/api/orders", HttpMethod.POST,
                HttpEntity(CreateOrderRequest(productId, 2), headers),
            )
            orderResponse.statusCode shouldBe HttpStatus.CREATED
            val orderId = orderResponse.body!!.id

            // Step 3: 주문 조회 — 생성 확인
            val getResponse = restTemplate.exchange<OrderResponse>(
                "/api/orders/$orderId", HttpMethod.GET,
                HttpEntity(null, headers),
            )

            Then("주문이 정상 생성된다") {
                getResponse.statusCode shouldBe HttpStatus.OK
                getResponse.body!!.status shouldBe "CREATED"
                getResponse.body!!.totalAmount shouldBe 20000
            }

            // Step 4: 주문 취소
            val cancelResponse = restTemplate.exchange<OrderResponse>(
                "/api/orders/$orderId/cancel", HttpMethod.POST,
                HttpEntity(null, headers),
            )

            Then("주문이 취소된다") {
                cancelResponse.statusCode shouldBe HttpStatus.OK
                cancelResponse.body!!.status shouldBe "CANCELLED"
            }
        }
    }
})
```

### 다단계 API 시나리오 (Python)

```python
@pytest.mark.anyio
async def test_주문_전체_플로우(async_client, auth_headers):
    """생성 → 조회 → 수정 → 삭제 E2E 시나리오"""

    # Step 1: 상품 생성
    response = await async_client.post(
        "/api/products",
        json={"name": "테스트 상품", "price": 10000},
        headers=auth_headers,
    )
    assert response.status_code == 201
    product_id = response.json()["id"]

    # Step 2: 주문 생성
    response = await async_client.post(
        "/api/orders",
        json={"product_id": product_id, "quantity": 2},
        headers=auth_headers,
    )
    assert response.status_code == 201
    order_id = response.json()["id"]

    # Step 3: 주문 조회 — 생성 확인
    response = await async_client.get(
        f"/api/orders/{order_id}",
        headers=auth_headers,
    )
    assert response.status_code == 200
    assert response.json()["status"] == "CREATED"
    assert response.json()["total_amount"] == 20000

    # Step 4: 주문 취소
    response = await async_client.post(
        f"/api/orders/{order_id}/cancel",
        headers=auth_headers,
    )
    assert response.status_code == 200
    assert response.json()["status"] == "CANCELLED"
```

### 테스트 데이터 설정

```kotlin
// Kotlin: @Sql로 시나리오 데이터 준비
@Sql(
    scripts = ["/sql/test-products.sql", "/sql/test-users.sql"],
    executionPhase = Sql.ExecutionPhase.BEFORE_TEST_METHOD,
)
@Sql(
    scripts = ["/sql/cleanup.sql"],
    executionPhase = Sql.ExecutionPhase.AFTER_TEST_METHOD,
)
class OrderE2ETest { /* ... */ }
```

```python
# Python: Alembic fixture로 스키마 + 시드 데이터
@pytest.fixture(scope="session", autouse=True)
async def setup_database(db_engine):
    async with db_engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    yield
    async with db_engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)

@pytest.fixture
async def seed_products(db_session):
    """시나리오 테스트용 시드 데이터"""
    products = [
        Product(name="테스트 상품 A", price=10000),
        Product(name="테스트 상품 B", price=20000),
    ]
    db_session.add_all(products)
    await db_session.flush()
    return products
```
