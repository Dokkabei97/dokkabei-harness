---
name: hexagonal-architecture
description: "헥사고날 아키텍처 가이드 — 포트/어댑터 구조, 패키지 레이아웃(Kotlin/Python), 의존성 방향, 모듈 경계"
---

# 헥사고날 아키텍처 가이드

## 1. 핵심 개념

헥사고날 아키텍처(Ports & Adapters)는 비즈니스 로직을 인프라스트럭처로부터 격리하여
도메인의 순수성과 테스트 용이성을 확보하는 아키텍처 패턴이다.

| Layer | 역할 | 예시 |
|---|---|---|
| **Domain** | 핵심 비즈니스 로직, 불변 규칙 | Entity, Value Object, Domain Service, Domain Event |
| **Port (인바운드)** | 외부→애플리케이션 진입 인터페이스 | `CreateOrderUseCase`, `GetOrderUseCase` |
| **Port (아웃바운드)** | 애플리케이션→외부 시스템 인터페이스 | `OrderRepository`, `PaymentGateway` |
| **Adapter (인바운드)** | 외부 요청을 포트로 변환 | REST Controller, Kafka Consumer, gRPC Service |
| **Adapter (아웃바운드)** | 아웃바운드 포트의 구체적 구현 | JPA Repo impl, Redis Adapter, Kafka Producer |
| **Application Service** | 유스케이스 오케스트레이션, 트랜잭션 경계 | `CreateOrderService` |

```
[인바운드 Adapter] → [인바운드 Port] → [Application Service] → [아웃바운드 Port] → [아웃바운드 Adapter]
  (Controller)       (UseCase IF)        (Service Impl)       (Repository IF)     (JPA Repo Impl)
                                              ↓
                                         [Domain]
                                    (Entity, VO, Service)
```

| 구성 요소 | 설명 | 특징 |
|---|---|---|
| **Entity** | 고유 식별자를 가진 도메인 객체 | 동일성은 ID로 판단 |
| **Value Object** | 값으로 동등성을 판단하는 불변 객체 | 불변, 모든 속성 비교 |
| **Domain Service** | 단일 엔티티에 속하지 않는 비즈니스 로직 | 상태 없음 |
| **Domain Event** | 도메인에서 발생한 사건 | 과거 시제 명명 (`OrderCreated`) |

---

## 2. Kotlin 패키지 레이아웃

```
com.example.order/
├── domain/
│   ├── model/          # Entity, Value Object
│   ├── service/        # Domain Service
│   └── event/          # Domain Event
├── application/
│   ├── port/
│   │   ├── in/         # Use Case 인터페이스 (CreateOrderUseCase)
│   │   └── out/        # Repository/Gateway 인터페이스 (OrderRepository)
│   └── service/        # Use Case 구현체 (CreateOrderService)
├── adapter/
│   ├── in/
│   │   ├── web/        # REST/GraphQL Controller + dto/
│   │   └── kafka/      # Kafka Consumer
│   └── out/
│       ├── persistence/# JPA Repository 구현 + entity/
│       ├── redis/      # Redis/Valkey Adapter
│       └── kafka/      # Kafka Producer
└── common/             # 공유 유틸, 설정, 예외
```

### Domain 모델

```kotlin
// domain/model/Money.kt — Value Object (프레임워크 어노테이션 없음)
data class Money(val amount: BigDecimal, val currency: Currency) {
    init { require(amount >= BigDecimal.ZERO) { "금액은 0 이상이어야 합니다" } }
    operator fun plus(other: Money): Money {
        require(currency == other.currency) { "통화가 일치해야 합니다" }
        return Money(amount + other.amount, currency)
    }
}

// domain/model/Order.kt — Entity (JPA 어노테이션 없음, 순수 도메인)
class Order private constructor(
    val id: OrderId, val buyerId: UserId,
    private val _lines: MutableList<OrderLine>, private var _status: OrderStatus,
) {
    val totalAmount: Money
        get() = _lines.fold(Money.ZERO_KRW) { acc, line -> acc + line.subtotal }

    fun cancel(): OrderCancelledEvent {
        check(_status == OrderStatus.CREATED) { "생성 상태만 취소 가능 (현재: $_status)" }
        _status = OrderStatus.CANCELLED
        return OrderCancelledEvent(id, buyerId, totalAmount)
    }

    companion object {
        fun create(buyerId: UserId, lines: List<OrderLine>): Pair<Order, OrderCreatedEvent> {
            require(lines.isNotEmpty()) { "주문 항목이 비어있습니다" }
            val order = Order(OrderId.generate(), buyerId, lines.toMutableList(), OrderStatus.CREATED)
            return order to OrderCreatedEvent(order.id, buyerId, order.totalAmount)
        }
    }
}
```

### Port & Application Service

```kotlin
// application/port/in/CreateOrderUseCase.kt — 인바운드 포트
interface CreateOrderUseCase {
    fun execute(command: CreateOrderCommand): OrderId
}
data class CreateOrderCommand(val buyerId: UserId, val items: List<OrderItemCommand>)

// application/port/out/OrderRepository.kt — 아웃바운드 포트 (도메인 모델만 다룸)
interface OrderRepository {
    fun save(order: Order): Order
    fun findById(id: OrderId): Order?
}
interface PaymentGateway {
    fun requestPayment(orderId: OrderId, amount: Money): PaymentResult
}

// application/service/CreateOrderService.kt — Use Case 구현체
@Service
class CreateOrderService(
    private val orderRepository: OrderRepository,
    private val paymentGateway: PaymentGateway,
    private val eventPublisher: DomainEventPublisher,
) : CreateOrderUseCase {
    @Transactional
    override fun execute(command: CreateOrderCommand): OrderId {
        val lines = command.items.map { OrderLine(it.productId, it.quantity, it.unitPrice) }
        val (order, event) = Order.create(command.buyerId, lines)
        val result = paymentGateway.requestPayment(order.id, order.totalAmount)
        check(result.isSuccess) { "결제 실패: ${result.failureReason}" }
        orderRepository.save(order)
        eventPublisher.publish(event)
        return order.id
    }
}
```

### Adapter

```kotlin
// adapter/in/web/OrderController.kt — 인바운드 어댑터
@RestController
@RequestMapping("/api/v1/orders")
class OrderController(private val createOrderUseCase: CreateOrderUseCase) {
    @PostMapping
    fun createOrder(@Valid @RequestBody request: CreateOrderRequest): ResponseEntity<OrderResponse> {
        val orderId = createOrderUseCase.execute(request.toCommand())
        return ResponseEntity.created(URI("/api/v1/orders/$orderId")).body(OrderResponse(orderId))
    }
}

// adapter/out/persistence/OrderPersistenceAdapter.kt — 아웃바운드 어댑터
@Repository
class OrderPersistenceAdapter(private val jpaRepository: OrderJpaRepository) : OrderRepository {
    override fun save(order: Order): Order = jpaRepository.save(OrderJpaEntity.from(order)).toDomain()
    override fun findById(id: OrderId): Order? = jpaRepository.findByIdOrNull(id.value)?.toDomain()
}

// adapter/out/persistence/entity/OrderJpaEntity.kt — JPA Entity (어댑터 전용)
@Entity @Table(name = "orders")
class OrderJpaEntity(@Id val id: UUID, val buyerId: UUID, val status: String, val totalAmount: BigDecimal) {
    fun toDomain(): Order = Order.reconstitute(OrderId(id), UserId(buyerId), OrderStatus.valueOf(status))
    companion object { fun from(order: Order) = OrderJpaEntity(order.id.value, order.buyerId.value, order.status.name, order.totalAmount.amount) }
}
```

---

## 3. Python 모듈 레이아웃

```
order/
├── domain/
│   ├── models.py       # Entity, Value Object (dataclass)
│   ├── services.py     # Domain Service
│   └── events.py       # Domain Event
├── application/
│   ├── ports/
│   │   ├── inbound.py  # Use Case ABC
│   │   └── outbound.py # Repository Protocol
│   └── services.py     # Use Case 구현체
├── adapters/
│   ├── inbound/
│   │   ├── api.py      # FastAPI Router
│   │   └── consumer.py # Kafka Consumer
│   └── outbound/
│       ├── sqlalchemy_repo.py
│       ├── redis_adapter.py
│       └── kafka_producer.py
└── infrastructure/
    └── config.py       # 설정, DI 구성
```

### Protocol vs ABC 비교

| 기준 | `Protocol` | `ABC` |
|---|---|---|
| **타입 체크** | 구조적 서브타이핑 (duck typing) | 명목적 서브타이핑 (상속 필수) |
| **상속 필요** | 불필요 — 시그니처만 일치하면 됨 | 필수 — `class Foo(ABC)` |
| **런타임 검사** | `runtime_checkable` 필요 | `isinstance()` 기본 지원 |
| **권장** | 아웃바운드 포트 | 인바운드 포트 |

### Domain 모델 & 포트

```python
# domain/models.py — 순수 dataclass, 프레임워크 의존 없음
@dataclass(frozen=True)
class Money:
    amount: Decimal
    currency: str = "KRW"
    def __add__(self, other: Money) -> Money:
        if self.currency != other.currency: raise ValueError("통화 불일치")
        return Money(self.amount + other.amount, self.currency)

@dataclass
class Order:
    id: UUID; buyer_id: UUID; lines: list[OrderLine]; status: OrderStatus = OrderStatus.CREATED

    @property
    def total_amount(self) -> Money:
        return sum((line.subtotal for line in self.lines), Money(Decimal("0")))

    def cancel(self) -> OrderCancelledEvent:
        if self.status != OrderStatus.CREATED:
            raise ValueError(f"생성 상태만 취소 가능 (현재: {self.status})")
        self.status = OrderStatus.CANCELLED
        return OrderCancelledEvent(order_id=self.id, buyer_id=self.buyer_id)

    @classmethod
    def create(cls, buyer_id: UUID, lines: list[OrderLine]) -> tuple[Order, OrderCreatedEvent]:
        if not lines: raise ValueError("주문 항목이 비어있습니다")
        order = cls(id=uuid4(), buyer_id=buyer_id, lines=lines)
        return order, OrderCreatedEvent(order_id=order.id, buyer_id=buyer_id)
```

```python
# application/ports/inbound.py — 인바운드 포트 (ABC)
class CreateOrderUseCase(ABC):
    @abstractmethod
    async def execute(self, command: CreateOrderCommand) -> UUID: ...

# application/ports/outbound.py — 아웃바운드 포트 (Protocol)
@runtime_checkable
class OrderRepository(Protocol):
    async def save(self, order: Order) -> Order: ...
    async def find_by_id(self, order_id: UUID) -> Order | None: ...

@runtime_checkable
class PaymentGateway(Protocol):
    async def request_payment(self, order_id: UUID, amount: Money) -> PaymentResult: ...
```

### Application Service & Adapter

```python
# application/services.py — Use Case 구현체
class CreateOrderService(CreateOrderUseCase):
    def __init__(self, order_repo: OrderRepository, payment: PaymentGateway, events: EventPublisher):
        self._repo, self._payment, self._events = order_repo, payment, events

    async def execute(self, command: CreateOrderCommand) -> UUID:
        lines = [OrderLine(i.product_id, i.quantity, i.unit_price) for i in command.items]
        order, event = Order.create(command.buyer_id, lines)
        result = await self._payment.request_payment(order.id, order.total_amount)
        if not result.is_success: raise PaymentFailedError(result.failure_reason)
        await self._repo.save(order)
        await self._events.publish(event)
        return order.id

# adapters/inbound/api.py — FastAPI Router (인바운드 어댑터)
router = APIRouter(prefix="/api/v1/orders", tags=["orders"])

@router.post("/", status_code=status.HTTP_201_CREATED)
async def create_order(
    request: CreateOrderRequest, use_case: CreateOrderUseCase = Depends(get_create_order_use_case),
) -> dict[str, UUID]:
    return {"order_id": await use_case.execute(request.to_command())}

# adapters/outbound/sqlalchemy_repo.py — SQLAlchemy 구현 (아웃바운드 어댑터, 상속 불필요)
class SQLAlchemyOrderRepository:
    def __init__(self, session: AsyncSession): self._session = session
    async def save(self, order: Order) -> Order:
        entity = OrderORM.from_domain(order)
        self._session.add(entity); await self._session.flush()
        return entity.to_domain()
```

---

## 4. 의존성 방향 규칙

### 핵심 원칙

의존성은 반드시 **바깥에서 안으로**: `Adapter → Application → Domain`

| 규칙 | 설명 |
|---|---|
| **Domain은 외부 의존성 ZERO** | 프레임워크 import 금지, 순수 언어 기능만 사용 |
| **Application은 Domain만 의존** | Port 인터페이스로 외부와 소통, 어댑터 직접 참조 금지 |
| **Adapter는 Application+Domain 의존** | 구체적 구현 담당, 프레임워크 어노테이션 사용 가능 |
| **Adapter끼리 직접 참조 금지** | Web Adapter → Persistence Adapter 직접 호출 불가 |

### 의존성 역전 (DIP)

```
전통적 (Bad):   Service → JpaRepository (구체 클래스)
헥사고날 (Good): Service → OrderRepository (인터페이스/포트) ← OrderPersistenceAdapter (구현)
```

### Bad vs Good (Kotlin)

```kotlin
// Bad — Domain이 JPA에 의존
@Entity @Table(name = "orders")
class Order(@Id @GeneratedValue val id: Long?, @Enumerated(EnumType.STRING) var status: OrderStatus)
// 문제: 테스트 시 DB 필요, 저장소 전환 불가

// Good — 순수 Domain + 별도 JPA Entity
class Order(val id: OrderId, private var _status: OrderStatus) {
    fun cancel(): OrderCancelledEvent { /* 비즈니스 로직만 */ }
}
@Entity class OrderJpaEntity(@Id val id: UUID, val status: String) {
    fun toDomain(): Order = /* ... */
    companion object { fun from(order: Order) = /* ... */ }
}
```

### Bad vs Good (Python)

```python
# Bad — Domain이 SQLAlchemy에 의존
class Order(DeclarativeBase):
    __tablename__ = "orders"
    id: Mapped[UUID] = mapped_column(primary_key=True)

# Good — 순수 dataclass + 별도 ORM
@dataclass
class Order:
    id: UUID; status: OrderStatus
    def cancel(self) -> OrderCancelledEvent: ...

class OrderORM(Base):  # 어댑터 레이어에만 존재
    __tablename__ = "orders"
    def to_domain(self) -> Order: ...
    @classmethod
    def from_domain(cls, order: Order) -> OrderORM: ...
```

---

## 5. 모듈 경계 & 접근 제어

### Kotlin: ArchUnit 테스트

```kotlin
@AnalyzeClasses(packages = ["com.example.order"])
class HexagonalArchitectureTest {
    @ArchTest val `도메인은 어댑터에 의존하지 않는다` =
        noClasses().that().resideInAPackage("..domain..")
            .should().dependOnClassesThat().resideInAPackage("..adapter..")

    @ArchTest val `애플리케이션은 어댑터에 의존하지 않는다` =
        noClasses().that().resideInAPackage("..application..")
            .should().dependOnClassesThat().resideInAPackage("..adapter..")

    @ArchTest val `도메인은 Spring에 의존하지 않는다` =
        noClasses().that().resideInAPackage("..domain..")
            .should().dependOnClassesThat()
            .resideInAnyPackage("org.springframework..", "jakarta.persistence..")
}
```

### Python: import-linter

```toml
# pyproject.toml
[tool.importlinter]
root_package = "order"

[[tool.importlinter.contracts]]
name = "헥사고날 의존성 방향"
type = "layers"
layers = ["order.adapters", "order.application", "order.domain"]

[[tool.importlinter.contracts]]
name = "도메인은 외부 프레임워크 금지"
type = "forbidden"
source_modules = ["order.domain"]
forbidden_modules = ["sqlalchemy", "fastapi", "redis", "aiokafka"]
```

### 크로스 모듈 통신

다른 도메인(Bounded Context)은 **published port(인바운드 포트)** 를 통해서만 호출한다.

```kotlin
// Bad — 다른 도메인 어댑터 직접 참조
class CreateOrderService(private val productJpaRepository: ProductJpaRepository)

// Good — published 포트 사용
class CreateOrderService(private val productQueryPort: ProductQueryPort)
interface ProductQueryPort { fun findPrice(productId: ProductId): Money }
```

### Bounded Context 간 통신 패턴

| 패턴 | 적합한 경우 | 주의사항 |
|---|---|---|
| **동기 API 호출** | 즉시 응답 필요, 같은 프로세스 | 결합도 높음, 장애 전파 |
| **이벤트 기반 비동기** | 느슨한 결합, 최종 일관성 | 이벤트 순서, 멱등성 필요 |
| **Saga 패턴** | 여러 도메인 분산 트랜잭션 | 보상 트랜잭션 설계 필수 |

```kotlin
// 이벤트 기반 비동기 — 주문→배송 도메인 통신
@Service
class CreateOrderService(...) : CreateOrderUseCase {
    override fun execute(command: CreateOrderCommand): OrderId {
        val (order, event) = Order.create(command.buyerId, lines)
        orderRepository.save(order)
        eventPublisher.publish(event) // OrderCreatedEvent 발행
        return order.id
    }
}

@Component // 배송 도메인 인바운드 어댑터
class OrderEventConsumer(private val prepareShipmentUseCase: PrepareShipmentUseCase) {
    @KafkaListener(topics = ["order.created"])
    fun handleOrderCreated(event: OrderCreatedEvent) {
        prepareShipmentUseCase.execute(PrepareShipmentCommand(orderId = event.orderId))
    }
}
```

---

## 6. 마이그레이션 전략: 레이어드 → 헥사고날

### 전환 단계

#### 단계 1: Domain 모델 분리 — JPA 어노테이션 제거, 순수 도메인 추출

```kotlin
// Before: @Entity class Order(@Id val id: Long, var status: String)
// After:  class Order(val id: OrderId, private var _status: OrderStatus) { fun cancel() = ... }
//         @Entity class OrderJpaEntity(@Id val id: UUID) { fun toDomain() / from() }
```

#### 단계 2: Port 인터페이스 추출 — Repository를 인터페이스로 분리, 구현체를 어댑터로 이동

```kotlin
// Before: Service → OrderJpaRepository (Spring Data 직접 의존)
// After:  Service → OrderRepository (인터페이스) ← OrderPersistenceAdapter (구현)
```

#### 단계 3: Adapter 분리 — Controller/Repository를 어댑터 패키지로 이동

```
Before: controller/ + service/ + repository/ + entity/
After:  domain/model/ + application/port/ + application/service/ + adapter/in/web/ + adapter/out/persistence/
```

#### 단계 4: Use Case 인터페이스 도입 — Service를 인터페이스와 구현체로 분리

```kotlin
interface CreateOrderUseCase { fun execute(command: CreateOrderCommand): OrderId }
@Service class CreateOrderService(...) : CreateOrderUseCase { override fun execute(...) = ... }
```

### Strangler Fig 패턴

한 번에 전체 전환하지 않고 모듈 단위로 점진적 전환:
1. 도메인 복잡도가 **높은** 모듈부터 (비즈니스 규칙이 많은 곳)
2. 새로 작성하는 모듈은 처음부터 헥사고날로
3. 기존 모듈은 변경 발생 시 함께 전환 (Boy Scout Rule)

### 주의사항

| 항목 | 설명 |
|---|---|
| **성급한 전환 금지** | CRUD 모듈은 레이어드로 충분할 수 있음 |
| **복잡도 높은 곳부터** | 비즈니스 규칙 많고 변경 빈도 높은 모듈 우선 |
| **변환 비용 인식** | Domain ↔ JPA Entity 매핑 보일러플레이트 trade-off |
| **팀 합의 필수** | 아키텍처 전환은 팀 전체 합의 후 진행 |
| **테스트 선행** | 전환 전 통합 테스트 확보 → 리팩토링 안전망 |
| **DI 컨테이너 활용** | Spring/FastAPI DI로 포트-어댑터 바인딩 관리 |
