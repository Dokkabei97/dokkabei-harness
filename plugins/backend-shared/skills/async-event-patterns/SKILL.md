---
name: async-event-patterns
description: "비동기 & 이벤트 패턴 레퍼런스 — Kotlin Coroutines, Spring Kafka Producer/Consumer, FastAPI BackgroundTasks, PG/Valkey/Kafka 인프라 연동"
---

# 비동기 & 이벤트 패턴 레퍼런스

## 1. Kotlin Coroutines 통합

### suspend fun in Controller

Spring WebFlux 또는 Spring MVC(3.2+)에서 `suspend fun`을 컨트롤러 핸들러로 사용할 수 있다.
WebFlux 환경에서는 네이티브 코루틴 지원, MVC 환경에서는 내부적으로 `DeferredResult`로 변환된다.

```kotlin
@RestController
@RequestMapping("/api/v1/orders")
class OrderController(
    private val orderService: OrderService,
) {
    // suspend fun: 비동기 논블로킹 처리
    @GetMapping("/{orderId}")
    suspend fun getOrder(@PathVariable orderId: Long): OrderResponse {
        return orderService.getOrder(orderId)
    }

    // Flow 반환: SSE 스트리밍
    @GetMapping("/stream", produces = [MediaType.TEXT_EVENT_STREAM_VALUE])
    fun streamOrders(): Flow<OrderEvent> {
        return orderService.orderEvents()
    }
}
```

### Flow / Channel 패턴

`Flow`는 콜드 스트림(구독 시 생성), `Channel`은 핫 스트림(생산자-소비자 분리)이다.

```kotlin
@Service
class OrderEventService(
    private val orderRepository: OrderRepository,
) {
    // Flow: 콜드 스트림 — 구독할 때마다 새로 실행
    fun recentOrdersFlow(): Flow<Order> = flow {
        val orders = orderRepository.findRecentOrders()
        orders.forEach { order ->
            emit(order)
            delay(100) // 백프레셔 조절
        }
    }.flowOn(Dispatchers.IO) // IO 디스패처에서 실행

    // Channel: 핫 스트림 — 여러 소비자가 공유
    private val _orderChannel = Channel<OrderEvent>(Channel.BUFFERED)
    val orderChannel: ReceiveChannel<OrderEvent> = _orderChannel

    suspend fun publishEvent(event: OrderEvent) {
        _orderChannel.send(event)
    }
}
```

### CoroutineScope 관리 (서비스 레이어)

서비스에서 코루틴 스코프를 관리할 때는 구조화된 동시성(structured concurrency)을 지켜야 한다.
Bean 생명주기와 코루틴 스코프를 연결하여 메모리 누수를 방지한다.

```kotlin
@Service
class NotificationService(
    private val notificationClient: NotificationClient,
) : DisposableBean {
    // 서비스 전용 스코프 — Bean 소멸 시 취소
    private val scope = CoroutineScope(
        SupervisorJob() + Dispatchers.Default + CoroutineName("notification-service")
    )

    fun sendAsync(userId: Long, message: String) {
        // fire-and-forget: 실패해도 호출자에 영향 없음
        scope.launch {
            try {
                notificationClient.send(userId, message)
            } catch (e: Exception) {
                logger.error(e) { "알림 전송 실패: userId=$userId" }
            }
        }
    }

    override fun destroy() {
        scope.cancel() // Bean 소멸 시 모든 코루틴 취소
    }
}
```

### Dispatchers.IO for Blocking 호출 래핑

JDBC, 파일 I/O 등 블로킹 호출은 반드시 `Dispatchers.IO`에서 실행한다.

```kotlin
@Service
class ProductService(
    private val productRepository: ProductRepository, // JPA — 블로킹
) {
    // Good: 블로킹 호출을 IO 디스패처로 래핑
    suspend fun getProduct(id: Long): Product = withContext(Dispatchers.IO) {
        productRepository.findByIdOrNull(id)
            ?: throw ProductNotFoundException(id)
    }

    // Bad: 코루틴 컨텍스트에서 블로킹 호출 직접 실행
    // suspend fun getProduct(id: Long): Product {
    //     return productRepository.findByIdOrNull(id) // 스레드 블로킹!
    // }
}
```

### Structured Concurrency

`coroutineScope`는 모든 자식이 완료될 때까지 대기하며, 하나가 실패하면 나머지를 취소한다.
`supervisorScope`는 자식 실패가 다른 자식에 전파되지 않는다.

```kotlin
@Service
class OrderAggregationService(
    private val orderService: OrderService,
    private val userService: UserService,
    private val productService: ProductService,
) {
    // coroutineScope: 하나 실패 시 전체 취소 — 일관성 보장
    suspend fun getOrderDetail(orderId: Long): OrderDetailResponse = coroutineScope {
        val order = async { orderService.getOrder(orderId) }
        val user = async { userService.getUser(order.await().userId) }
        val products = async { productService.getProducts(order.await().productIds) }
        OrderDetailResponse(order.await(), user.await(), products.await())
    }

    // supervisorScope: 부분 실패 허용 — 추천/리뷰 등 부가 데이터
    suspend fun getOrderDetailWithExtras(orderId: Long): OrderDetailWithExtras = supervisorScope {
        val order = async { orderService.getOrder(orderId) }
        val recommendations = async {
            try { recommendService.getRecommendations(orderId) }
            catch (e: Exception) { emptyList() } // 실패해도 빈 리스트
        }
        val reviews = async {
            try { reviewService.getReviews(orderId) }
            catch (e: Exception) { emptyList() }
        }
        OrderDetailWithExtras(order.await(), recommendations.await(), reviews.await())
    }
}
```

---

## 2. Spring Kafka Producer

### ProducerConfig 설정

```kotlin
@Configuration
@EnableKafka
class KafkaProducerConfig {

    @Bean
    fun producerFactory(): ProducerFactory<String, Any> {
        val props = mapOf(
            ProducerConfig.BOOTSTRAP_SERVERS_CONFIG to "kafka-broker:9092",
            ProducerConfig.KEY_SERIALIZER_CLASS_CONFIG to StringSerializer::class.java,
            ProducerConfig.VALUE_SERIALIZER_CLASS_CONFIG to JsonSerializer::class.java,
            // 신뢰성 설정
            ProducerConfig.ACKS_CONFIG to "all",           // 모든 ISR 확인
            ProducerConfig.RETRIES_CONFIG to 3,
            ProducerConfig.ENABLE_IDEMPOTENCE_CONFIG to true, // 중복 방지
            // 성능 설정
            ProducerConfig.BATCH_SIZE_CONFIG to 16_384,
            ProducerConfig.LINGER_MS_CONFIG to 5,          // 5ms 배치 대기
            ProducerConfig.COMPRESSION_TYPE_CONFIG to "lz4",
        )
        return DefaultKafkaProducerFactory(props)
    }

    @Bean
    fun kafkaTemplate(): KafkaTemplate<String, Any> {
        return KafkaTemplate(producerFactory())
    }
}
```

`@ConfigurationProperties` 방식 (프로덕션 권장):

```kotlin
@ConfigurationProperties(prefix = "app.kafka.producer")
data class KafkaProducerProperties(
    val bootstrapServers: String = "localhost:9092",
    val acks: String = "all",
    val retries: Int = 3,
    val batchSize: Int = 16_384,
    val lingerMs: Int = 5,
    val compressionType: String = "lz4",
    val idempotence: Boolean = true,
)
```

### 키 파티셔닝 전략

같은 키를 가진 메시지는 같은 파티션에 전송되어 순서가 보장된다.

```kotlin
// Good: orderId를 키로 사용 — 같은 주문의 이벤트 순서 보장
kafkaTemplate.send("order-events", order.id.toString(), orderEvent)

// Bad: 키 없이 전송 — 라운드로빈으로 파티션 분배, 순서 미보장
kafkaTemplate.send("order-events", orderEvent)
```

### KafkaTemplate Wrapper 서비스

```kotlin
@Service
class KafkaEventPublisher(
    private val kafkaTemplate: KafkaTemplate<String, Any>,
) {
    private val logger = KotlinLogging.logger {}

    // 콜백 방식: 논블로킹
    fun publish(topic: String, key: String, event: Any) {
        val future = kafkaTemplate.send(topic, key, event)
        future.whenComplete { result, ex ->
            if (ex != null) {
                logger.error(ex) { "Kafka 전송 실패: topic=$topic, key=$key" }
                // 재시도 큐 또는 DLQ 처리
            } else {
                val metadata = result.recordMetadata
                logger.debug {
                    "Kafka 전송 성공: topic=${metadata.topic()}, " +
                        "partition=${metadata.partition()}, offset=${metadata.offset()}"
                }
            }
        }
    }

    // 동기 방식: 전송 완료까지 대기 (트랜잭션 내부에서 사용)
    fun publishSync(topic: String, key: String, event: Any) {
        try {
            kafkaTemplate.send(topic, key, event).get(5, TimeUnit.SECONDS)
        } catch (e: Exception) {
            logger.error(e) { "Kafka 동기 전송 실패: topic=$topic, key=$key" }
            throw KafkaPublishException("메시지 전송 실패", e)
        }
    }
}
```

### 트랜잭셔널 프로듀서

DB 트랜잭션과 Kafka 메시지 전송을 원자적으로 처리한다.

```kotlin
@Configuration
class KafkaTransactionConfig {
    @Bean
    fun kafkaTransactionManager(
        producerFactory: ProducerFactory<String, Any>,
    ): KafkaTransactionManager<String, Any> {
        return KafkaTransactionManager(producerFactory)
    }
}

@Service
class OrderService(
    private val orderRepository: OrderRepository,
    private val kafkaTemplate: KafkaTemplate<String, Any>,
) {
    // DB 트랜잭션 + Kafka 트랜잭션 연동
    @Transactional
    fun createOrder(request: CreateOrderRequest): Order {
        val order = orderRepository.save(Order.from(request))
        // executeInTransaction: Kafka 트랜잭션 범위 내에서 전송
        kafkaTemplate.executeInTransaction {
            it.send("order-events", order.id.toString(), OrderCreatedEvent(order))
        }
        return order
    }
}
```

---

## 3. Spring Kafka Consumer

### Consumer 설정 및 @KafkaListener

```kotlin
@Configuration
class KafkaConsumerConfig {

    @Bean
    fun consumerFactory(): ConsumerFactory<String, Any> {
        val props = mapOf(
            ConsumerConfig.BOOTSTRAP_SERVERS_CONFIG to "kafka-broker:9092",
            ConsumerConfig.KEY_DESERIALIZER_CLASS_CONFIG to StringDeserializer::class.java,
            ConsumerConfig.VALUE_DESERIALIZER_CLASS_CONFIG to JsonDeserializer::class.java,
            ConsumerConfig.GROUP_ID_CONFIG to "order-service",
            ConsumerConfig.AUTO_OFFSET_RESET_CONFIG to "earliest",
            ConsumerConfig.ENABLE_AUTO_COMMIT_CONFIG to false, // 수동 커밋 권장
            // JsonDeserializer 설정
            JsonDeserializer.TRUSTED_PACKAGES to "com.example.event.*",
            JsonDeserializer.VALUE_DEFAULT_TYPE to "com.example.event.OrderEvent",
        )
        return DefaultKafkaConsumerFactory(props)
    }

    @Bean
    fun kafkaListenerContainerFactory(): ConcurrentKafkaListenerContainerFactory<String, Any> {
        val factory = ConcurrentKafkaListenerContainerFactory<String, Any>()
        factory.consumerFactory = consumerFactory()
        factory.setConcurrency(3) // 3개 컨슈머 스레드
        factory.containerProperties.ackMode = ContainerProperties.AckMode.MANUAL_IMMEDIATE
        // 에러 핸들러 설정
        factory.setCommonErrorHandler(defaultErrorHandler())
        return factory
    }
}
```

### Manual Ack 리스너

```kotlin
@Component
class OrderEventListener(
    private val orderProcessService: OrderProcessService,
) {
    private val logger = KotlinLogging.logger {}

    @KafkaListener(
        topics = ["order-events"],
        groupId = "order-processor",
        containerFactory = "kafkaListenerContainerFactory",
    )
    fun handleOrderEvent(
        @Payload event: OrderEvent,
        @Header(KafkaHeaders.RECEIVED_KEY) key: String,
        @Header(KafkaHeaders.RECEIVED_PARTITION) partition: Int,
        @Header(KafkaHeaders.OFFSET) offset: Long,
        acknowledgment: Acknowledgment,
    ) {
        logger.info { "주문 이벤트 수신: key=$key, partition=$partition, offset=$offset" }
        try {
            orderProcessService.process(event)
            acknowledgment.acknowledge() // 성공 시에만 커밋
        } catch (e: Exception) {
            logger.error(e) { "주문 이벤트 처리 실패: key=$key" }
            // acknowledge 하지 않음 → 재처리 또는 DLQ로 이동
            throw e
        }
    }
}
```

### DLQ (Dead Letter Queue) 설정

처리 실패한 메시지를 별도 토픽으로 보내 나중에 분석/재처리한다.

```kotlin
@Bean
fun defaultErrorHandler(): DefaultErrorHandler {
    // DLQ 퍼블리셔: 실패 메시지를 <원본토픽>.DLT 토픽으로 전송
    val recoverer = DeadLetterPublishingRecoverer(kafkaTemplate) { record, _ ->
        TopicPartition("${record.topic()}.DLT", record.partition())
    }
    // 3회 재시도 후 DLQ 전송, 1초 간격 백오프
    val backOff = FixedBackOff(1000L, 3L)
    return DefaultErrorHandler(recoverer, backOff).apply {
        // 재시도하지 않을 예외 등록 (비즈니스 예외)
        addNotRetryableExceptions(
            InvalidOrderException::class.java,
            DuplicateEventException::class.java,
        )
    }
}
```

### Batch Consumer 패턴

대량 메시지를 일괄 처리하여 처리량을 높인다.

```kotlin
@Bean
fun batchKafkaListenerContainerFactory(): ConcurrentKafkaListenerContainerFactory<String, Any> {
    val factory = ConcurrentKafkaListenerContainerFactory<String, Any>()
    factory.consumerFactory = consumerFactory()
    factory.isBatchListener = true // 배치 모드 활성화
    factory.setConcurrency(3)
    factory.containerProperties.ackMode = ContainerProperties.AckMode.MANUAL_IMMEDIATE
    return factory
}

@Component
class BatchOrderEventListener(
    private val orderBatchService: OrderBatchService,
) {
    @KafkaListener(
        topics = ["order-events"],
        groupId = "order-batch-processor",
        containerFactory = "batchKafkaListenerContainerFactory",
    )
    fun handleBatch(
        @Payload events: List<OrderEvent>,
        acknowledgment: Acknowledgment,
    ) {
        logger.info { "배치 수신: ${events.size}건" }
        orderBatchService.processBatch(events)
        acknowledgment.acknowledge()
    }
}
```

---

## 4. Spring ApplicationEvent

### 이벤트 클래스 설계

```kotlin
// 도메인 이벤트 기본 클래스
abstract class DomainEvent(
    val eventId: String = UUID.randomUUID().toString(),
    val occurredAt: Instant = Instant.now(),
)

// 주문 완료 이벤트
data class OrderCompletedEvent(
    val orderId: Long,
    val userId: Long,
    val totalAmount: BigDecimal,
    val items: List<OrderItem>,
) : DomainEvent()
```

### ApplicationEventPublisher 사용

```kotlin
@Service
class OrderService(
    private val orderRepository: OrderRepository,
    private val eventPublisher: ApplicationEventPublisher,
) {
    @Transactional
    fun completeOrder(orderId: Long) {
        val order = orderRepository.findByIdOrNull(orderId)
            ?: throw OrderNotFoundException(orderId)
        order.complete()
        orderRepository.save(order)

        // 이벤트 발행 — 트랜잭션 커밋 후 처리됨 (TransactionalEventListener 사용 시)
        eventPublisher.publishEvent(
            OrderCompletedEvent(
                orderId = order.id,
                userId = order.userId,
                totalAmount = order.totalAmount,
                items = order.items,
            )
        )
    }
}
```

### @EventListener vs @TransactionalEventListener

| 어노테이션 | 실행 시점 | 사용 시기 |
|---|---|---|
| `@EventListener` | 이벤트 발행 즉시 (트랜잭션 내부) | 같은 트랜잭션 내 동기 후처리 |
| `@TransactionalEventListener(AFTER_COMMIT)` | 트랜잭션 커밋 후 | 알림, 캐시 갱신, 외부 연동 |
| `@TransactionalEventListener(AFTER_ROLLBACK)` | 트랜잭션 롤백 후 | 보상 로직, 실패 알림 |

```kotlin
@Component
class OrderEventHandler(
    private val notificationService: NotificationService,
    private val cacheService: CacheService,
    private val analyticsService: AnalyticsService,
) {
    // 트랜잭션 커밋 후 실행 — DB 반영이 확정된 후 알림 발송
    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    fun onOrderCompleted(event: OrderCompletedEvent) {
        notificationService.sendOrderConfirmation(event.userId, event.orderId)
        cacheService.evictOrderCache(event.orderId)
    }

    // @Async: 별도 스레드에서 비동기 실행
    @Async
    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    fun onOrderCompletedAsync(event: OrderCompletedEvent) {
        // 무거운 작업: 분석 데이터 적재
        analyticsService.recordOrderCompletion(event)
    }
}
```

### @Async 활성화 설정

```kotlin
@Configuration
@EnableAsync
class AsyncConfig : AsyncConfigurer {
    override fun getAsyncExecutor(): Executor {
        val executor = ThreadPoolTaskExecutor()
        executor.corePoolSize = 5
        executor.maxPoolSize = 20
        executor.queueCapacity = 100
        executor.setThreadNamePrefix("async-event-")
        executor.initialize()
        return executor
    }

    override fun getAsyncUncaughtExceptionHandler(): AsyncUncaughtExceptionHandler {
        return AsyncUncaughtExceptionHandler { ex, method, params ->
            logger.error(ex) { "비동기 이벤트 처리 실패: ${method.name}" }
        }
    }
}
```

---

## 5. FastAPI BackgroundTasks

### 기본 사용법

`BackgroundTasks`는 응답 반환 후 백그라운드에서 작업을 실행한다. 별도 인프라 없이 간단한 후처리에 적합하다.

```python
from fastapi import BackgroundTasks, FastAPI

app = FastAPI()

def send_notification(user_id: int, message: str) -> None:
    """동기 함수도 BackgroundTasks에서 실행 가능"""
    # 이메일 발송, 슬랙 알림 등
    notification_client.send(user_id=user_id, message=message)

async def update_analytics(order_id: int) -> None:
    """비동기 함수도 지원"""
    await analytics_service.record_order(order_id)

@app.post("/orders/{order_id}/complete")
async def complete_order(
    order_id: int,
    background_tasks: BackgroundTasks,
) -> dict:
    order = await order_service.complete(order_id)

    # 응답 반환 후 백그라운드 실행
    background_tasks.add_task(send_notification, order.user_id, "주문 완료")
    background_tasks.add_task(update_analytics, order_id)

    return {"status": "completed", "order_id": order_id}
```

### BackgroundTasks 한계 vs 대안

| 항목 | BackgroundTasks | Celery / ARQ |
|---|---|---|
| 인프라 의존성 | 없음 (인프로세스) | Redis/RabbitMQ 필요 |
| 재시도 | 수동 구현 필요 | 내장 재시도 정책 |
| 모니터링 | 없음 | Flower / ARQ Dashboard |
| 분산 처리 | 불가 (단일 프로세스) | 워커 스케일아웃 가능 |
| 적합한 용도 | 알림, 로깅, 캐시 갱신 | 이미지 처리, 대량 메일, 데이터 파이프라인 |

```python
# Good: BackgroundTasks — 가벼운 후처리
background_tasks.add_task(send_slack_notification, channel, message)

# Bad: BackgroundTasks — 오래 걸리는 작업 (타임아웃 위험)
# background_tasks.add_task(process_large_csv, file_path)  # Celery/ARQ 사용 권장
```

---

## 6. Python asyncio Kafka (aiokafka)

### AIOKafkaProducer 설정 및 사용

```python
from aiokafka import AIOKafkaProducer
from pydantic import BaseModel
import json

class OrderEvent(BaseModel):
    order_id: int
    user_id: int
    total_amount: float
    event_type: str  # "created", "completed", "cancelled"

class KafkaProducerService:
    def __init__(self, bootstrap_servers: str = "kafka-broker:9092"):
        self._producer: AIOKafkaProducer | None = None
        self._bootstrap_servers = bootstrap_servers

    async def start(self) -> None:
        self._producer = AIOKafkaProducer(
            bootstrap_servers=self._bootstrap_servers,
            value_serializer=lambda v: json.dumps(v).encode("utf-8"),
            key_serializer=lambda k: k.encode("utf-8") if k else None,
            acks="all",
            enable_idempotence=True,
            compression_type="lz4",
        )
        await self._producer.start()

    async def stop(self) -> None:
        if self._producer:
            await self._producer.stop()

    async def publish(self, topic: str, key: str, event: BaseModel) -> None:
        """Pydantic 모델을 직렬화하여 Kafka 전송"""
        if not self._producer:
            raise RuntimeError("Kafka producer가 시작되지 않음")
        await self._producer.send_and_wait(
            topic=topic,
            key=key,
            value=event.model_dump(),
        )
```

### AIOKafkaConsumer 설정 및 사용

```python
from aiokafka import AIOKafkaConsumer
import asyncio
import json
from pydantic import ValidationError

class KafkaConsumerService:
    def __init__(
        self,
        topic: str,
        group_id: str,
        bootstrap_servers: str = "kafka-broker:9092",
    ):
        self._topic = topic
        self._consumer: AIOKafkaConsumer | None = None
        self._group_id = group_id
        self._bootstrap_servers = bootstrap_servers
        self._running = False

    async def start(self) -> None:
        self._consumer = AIOKafkaConsumer(
            self._topic,
            bootstrap_servers=self._bootstrap_servers,
            group_id=self._group_id,
            auto_offset_reset="earliest",
            enable_auto_commit=False,  # 수동 커밋
            value_deserializer=lambda v: json.loads(v.decode("utf-8")),
        )
        await self._consumer.start()
        self._running = True

    async def stop(self) -> None:
        self._running = False
        if self._consumer:
            await self._consumer.stop()

    async def consume(self, handler: Callable) -> None:
        """메시지 소비 루프"""
        if not self._consumer:
            raise RuntimeError("Kafka consumer가 시작되지 않음")
        try:
            async for message in self._consumer:
                if not self._running:
                    break
                try:
                    event = OrderEvent.model_validate(message.value)
                    await handler(event)
                    # 처리 성공 시 수동 커밋
                    await self._consumer.commit()
                except ValidationError as e:
                    logger.error(f"메시지 역직렬화 실패: {e}")
                    await self._consumer.commit()  # 잘못된 메시지는 스킵
                except Exception as e:
                    logger.error(f"메시지 처리 실패: {e}")
                    # 커밋하지 않음 → 재처리
        except asyncio.CancelledError:
            logger.info("Consumer 루프 취소됨")
```

### FastAPI Lifespan에서 Kafka 라이프사이클 관리

```python
from contextlib import asynccontextmanager
from fastapi import FastAPI
import asyncio

kafka_producer = KafkaProducerService()
order_consumer = KafkaConsumerService(
    topic="order-events",
    group_id="order-service",
)

@asynccontextmanager
async def lifespan(app: FastAPI):
    """앱 시작/종료 시 Kafka 클라이언트 라이프사이클 관리"""
    # 시작: Kafka 클라이언트 초기화
    await kafka_producer.start()
    await order_consumer.start()

    # 컨슈머를 백그라운드 태스크로 실행
    consumer_task = asyncio.create_task(
        order_consumer.consume(handle_order_event)
    )

    yield  # 앱 실행 중

    # 종료: 정리
    await order_consumer.stop()
    consumer_task.cancel()
    await kafka_producer.stop()

app = FastAPI(lifespan=lifespan)

async def handle_order_event(event: OrderEvent) -> None:
    """주문 이벤트 핸들러"""
    match event.event_type:
        case "created":
            await process_new_order(event)
        case "completed":
            await finalize_order(event)
        case "cancelled":
            await rollback_order(event)
        case _:
            logger.warning(f"알 수 없는 이벤트 타입: {event.event_type}")
```

---

## 7. PG Notify/Listen

PostgreSQL의 LISTEN/NOTIFY는 경량 pub/sub 메커니즘이다.
별도 메시지 브로커 없이 DB 내에서 실시간 알림을 전달할 수 있다.

### 사용 시기

- 캐시 무효화 알림 (테이블 변경 시 애플리케이션 캐시 갱신)
- 설정 변경 전파 (여러 인스턴스에 동시 전달)
- 경량 이벤트 (메시지 유실 허용 가능한 경우)

> **주의**: LISTEN/NOTIFY는 메시지 보존을 보장하지 않는다. 리스너가 연결되지 않은 상태에서 전송된 메시지는 유실된다. 신뢰성이 필요하면 Kafka/Valkey Streams를 사용한다.

### Kotlin: NOTIFY 발행

```kotlin
@Service
class CacheInvalidationNotifier(
    private val jdbcTemplate: JdbcTemplate,
) {
    // NOTIFY 발행: 채널에 페이로드 전송
    fun notifyInvalidation(tableName: String, recordId: Long) {
        val payload = """{"table":"$tableName","id":$recordId}"""
        jdbcTemplate.execute("NOTIFY cache_invalidation, '$payload'")
    }
}
```

### Kotlin: R2DBC로 LISTEN

```kotlin
@Component
class PgNotificationListener(
    private val connectionFactory: ConnectionFactory,
    private val cacheService: CacheService,
) {
    private val logger = KotlinLogging.logger {}

    @PostConstruct
    fun startListening() {
        // R2DBC로 비동기 LISTEN
        Mono.from(connectionFactory.create())
            .flatMapMany { connection ->
                val pgConnection = connection.unwrap(io.r2dbc.postgresql.api.PostgresqlConnection::class.java)
                pgConnection.createStatement("LISTEN cache_invalidation")
                    .execute()
                    .thenMany(pgConnection.getNotifications())
            }
            .doOnNext { notification ->
                logger.info { "PG 알림 수신: ${notification.parameter}" }
                val payload = objectMapper.readTree(notification.parameter)
                val tableName = payload["table"].asText()
                val recordId = payload["id"].asLong()
                cacheService.evict(tableName, recordId)
            }
            .doOnError { e -> logger.error(e) { "PG LISTEN 오류" } }
            .retry(3)
            .subscribe()
    }
}
```

### Python: asyncpg LISTEN 패턴

```python
import asyncpg
import json

class PgNotificationListener:
    def __init__(self, dsn: str):
        self._dsn = dsn
        self._conn: asyncpg.Connection | None = None

    async def start(self, channel: str, handler: Callable) -> None:
        """LISTEN 시작 — 알림 수신 시 handler 콜백 호출"""
        self._conn = await asyncpg.connect(self._dsn)
        await self._conn.add_listener(channel, self._make_callback(handler))
        logger.info(f"PG LISTEN 시작: channel={channel}")

    async def stop(self) -> None:
        if self._conn:
            await self._conn.close()

    @staticmethod
    def _make_callback(handler: Callable):
        def callback(connection, pid, channel, payload):
            data = json.loads(payload)
            asyncio.create_task(handler(data))
        return callback

# 사용 예시
async def on_cache_invalidation(data: dict) -> None:
    table = data["table"]
    record_id = data["id"]
    await cache_service.evict(table, record_id)

listener = PgNotificationListener(dsn="postgresql://user:pass@localhost/mydb")
await listener.start("cache_invalidation", on_cache_invalidation)
```

---

## 8. Valkey (Redis) Pub/Sub & Streams

### Pub/Sub vs Streams 비교

| 항목 | Pub/Sub | Streams |
|---|---|---|
| 전달 보장 | 없음 (연결 중인 구독자만 수신) | 있음 (메시지 보존) |
| 메시지 보존 | 없음 (fire-and-forget) | 있음 (MAXLEN으로 관리) |
| Consumer Group | 미지원 | 지원 (XREADGROUP) |
| 메시지 ACK | 없음 | XACK으로 확인 |
| 재처리 | 불가 | XPENDING + XCLAIM |
| 적합한 용도 | 실시간 알림, 캐시 무효화 | 이벤트 소싱, 작업 큐, 로그 스트림 |

### Kotlin: Spring Data Redis Pub/Sub

```kotlin
@Configuration
class RedisSubConfig {

    @Bean
    fun redisMessageListenerContainer(
        connectionFactory: RedisConnectionFactory,
    ): RedisMessageListenerContainer {
        val container = RedisMessageListenerContainer()
        container.setConnectionFactory(connectionFactory)
        container.addMessageListener(
            orderNotificationListener(),
            ChannelTopic("order-notifications"),
        )
        return container
    }

    @Bean
    fun orderNotificationListener(): MessageListener {
        return MessageListener { message, _ ->
            val payload = String(message.body)
            logger.info { "Valkey 메시지 수신: $payload" }
            // 알림 처리 로직
        }
    }
}

@Service
class RedisPublisher(
    private val redisTemplate: StringRedisTemplate,
) {
    fun publishNotification(channel: String, message: String) {
        redisTemplate.convertAndSend(channel, message)
    }
}
```

### Kotlin: Valkey Streams (Consumer Group)

```kotlin
@Configuration
class RedisStreamConfig {

    @Bean
    fun streamMessageListenerContainer(
        connectionFactory: RedisConnectionFactory,
    ): StreamMessageListenerContainer<String, MapRecord<String, String, String>> {
        val options = StreamMessageListenerContainer.StreamMessageListenerContainerOptions
            .builder()
            .pollTimeout(Duration.ofSeconds(2))
            .build()

        val container = StreamMessageListenerContainer.create(connectionFactory, options)

        // Consumer Group 생성 (없으면)
        try {
            redisTemplate.opsForStream<String, String>()
                .createGroup("order-stream", ReadOffset.from("0"), "order-processor-group")
        } catch (e: Exception) {
            // 이미 존재하면 무시
        }

        // Consumer 등록
        container.receive(
            Consumer.from("order-processor-group", "consumer-1"),
            StreamOffset.create("order-stream", ReadOffset.lastConsumed()),
            orderStreamListener(),
        )

        container.start()
        return container
    }

    @Bean
    fun orderStreamListener(): StreamListener<String, MapRecord<String, String, String>> {
        return StreamListener { message ->
            val data = message.value
            logger.info { "Stream 메시지 수신: id=${message.id}, data=$data" }
            try {
                processOrderStreamMessage(data)
                // 처리 성공 시 ACK
                redisTemplate.opsForStream<String, String>()
                    .acknowledge("order-stream", "order-processor-group", message.id)
            } catch (e: Exception) {
                logger.error(e) { "Stream 메시지 처리 실패: id=${message.id}" }
                // ACK하지 않음 → XPENDING으로 재처리 가능
            }
        }
    }
}

@Service
class RedisStreamPublisher(
    private val redisTemplate: StringRedisTemplate,
) {
    fun publish(streamKey: String, data: Map<String, String>): RecordId {
        val record = MapRecord.create(streamKey, data)
        return redisTemplate.opsForStream<String, String>().add(record)
    }
}
```

### Python: redis.asyncio Pub/Sub

```python
import redis.asyncio as aioredis

class ValkeyPubSubService:
    def __init__(self, url: str = "redis://localhost:6379"):
        self._redis = aioredis.from_url(url)
        self._pubsub = self._redis.pubsub()

    async def subscribe(self, channel: str, handler: Callable) -> None:
        """채널 구독 및 메시지 수신 루프"""
        await self._pubsub.subscribe(channel)
        async for message in self._pubsub.listen():
            if message["type"] == "message":
                data = json.loads(message["data"])
                await handler(data)

    async def publish(self, channel: str, data: dict) -> None:
        """채널에 메시지 발행"""
        await self._redis.publish(channel, json.dumps(data))

    async def close(self) -> None:
        await self._pubsub.unsubscribe()
        await self._redis.close()
```

### Python: Valkey Streams (Consumer Group)

```python
import redis.asyncio as aioredis

class ValkeyStreamService:
    def __init__(self, url: str = "redis://localhost:6379"):
        self._redis = aioredis.from_url(url)

    async def create_group(self, stream: str, group: str) -> None:
        """Consumer Group 생성 (없으면)"""
        try:
            await self._redis.xgroup_create(stream, group, id="0", mkstream=True)
        except aioredis.ResponseError:
            pass  # 이미 존재

    async def produce(self, stream: str, data: dict, maxlen: int = 10000) -> str:
        """스트림에 메시지 추가"""
        message_id = await self._redis.xadd(stream, data, maxlen=maxlen)
        return message_id

    async def consume(
        self,
        stream: str,
        group: str,
        consumer: str,
        handler: Callable,
        batch_size: int = 10,
    ) -> None:
        """Consumer Group으로 메시지 소비"""
        while True:
            messages = await self._redis.xreadgroup(
                groupname=group,
                consumername=consumer,
                streams={stream: ">"},
                count=batch_size,
                block=2000,  # 2초 대기
            )
            for stream_name, stream_messages in messages:
                for message_id, data in stream_messages:
                    try:
                        await handler(data)
                        # 처리 성공 시 ACK
                        await self._redis.xack(stream, group, message_id)
                    except Exception as e:
                        logger.error(f"Stream 메시지 처리 실패: {message_id}, {e}")
                        # ACK하지 않음 → 나중에 XPENDING으로 재처리

    async def reprocess_pending(
        self,
        stream: str,
        group: str,
        consumer: str,
        idle_ms: int = 60_000,
    ) -> None:
        """미처리(pending) 메시지 재처리 — idle_ms 이상 방치된 메시지"""
        pending = await self._redis.xpending_range(
            stream, group, min="-", max="+", count=100,
        )
        for entry in pending:
            if entry["time_since_delivered"] >= idle_ms:
                # 다른 소비자로부터 메시지 인계
                claimed = await self._redis.xclaim(
                    stream, group, consumer,
                    min_idle_time=idle_ms,
                    message_ids=[entry["message_id"]],
                )
                for message_id, data in claimed:
                    logger.info(f"Pending 메시지 재처리: {message_id}")
                    # 재처리 로직 실행

    async def close(self) -> None:
        await self._redis.close()
```

### FastAPI Lifespan에서 Valkey Stream 통합

```python
stream_service = ValkeyStreamService()

@asynccontextmanager
async def lifespan(app: FastAPI):
    # 시작
    await stream_service.create_group("order-stream", "order-processor")
    consumer_task = asyncio.create_task(
        stream_service.consume(
            stream="order-stream",
            group="order-processor",
            consumer="worker-1",
            handler=handle_order_stream,
        )
    )
    yield
    # 종료
    consumer_task.cancel()
    await stream_service.close()

async def handle_order_stream(data: dict) -> None:
    """Valkey Stream 메시지 핸들러"""
    event_type = data.get(b"event_type", b"").decode()
    order_id = int(data.get(b"order_id", b"0").decode())
    logger.info(f"Stream 이벤트 처리: type={event_type}, order_id={order_id}")
    # 비즈니스 로직 실행
```

---

## 9. 외부 API 타임아웃 정책 & IO 병렬화

증분 색인/배치/비동기 처리에서 **레거시 API 호출**이 전체 TPS를 저해하는 패턴이 반복된다.
동기 호출 + 타임아웃 미설정 = 한 요청이 전체 처리량 블록.

### 9.1. 타임아웃 상한 기준

| 호출 대상 | 권장 타임아웃 상한 | 근거 |
|---|---|---|
| 레거시/서드파티 API (인덱싱 경로) | **≤ 500ms** | 증분 색인 TPS를 지키기 위한 마지노선 |
| 동일 DC 내부 서비스 (REST/gRPC) | ≤ 1s | 정상 latency p95의 3~5배 |
| DB 쿼리 (OLTP) | ≤ 500ms | 장시간 쿼리는 대시보드/슬로우쿼리로 분리 |
| 캐시 (Valkey/Redis) | ≤ 100ms | 캐시 실패는 빠르게 폴백 |
| 메시지 브로커 publish | ≤ 1s | sync ack 모드 기준 |

### 9.2. Kotlin WebClient 타임아웃

```kotlin
// BAD: 타임아웃 미설정 — 레거시 API가 30초 걸리면 전체 컨슈머 블록
@Bean
fun legacyWebClient(): WebClient = WebClient.builder()
    .baseUrl("http://legacy.internal")
    .build()

// GOOD: 연결/응답 타임아웃 명시
@Bean
fun legacyWebClient(): WebClient {
    val httpClient = HttpClient.create()
        .responseTimeout(Duration.ofMillis(500))
        .option(ChannelOption.CONNECT_TIMEOUT_MILLIS, 300)
    return WebClient.builder()
        .baseUrl("http://legacy.internal")
        .clientConnector(ReactorClientHttpConnector(httpClient))
        .build()
}
```

### 9.3. 동기 → 비동기 전환 (증분색인 TPS 보호)

```kotlin
// BAD: Kafka 컨슈머 내부에서 동기 HTTP 호출
@KafkaListener(topics = ["product.changed"])
fun consume(event: ProductChangedEvent) {
    val legacy = legacyApi.fetchProduct(event.productId) // 동기, 타임아웃 없음
    val enriched = enrichWith(event, legacy)
    indexService.index(enriched)
}

// GOOD: 코루틴으로 병렬 처리 + 타임아웃
@KafkaListener(topics = ["product.changed"], containerFactory = "batchFactory")
fun consumeBatch(events: List<ProductChangedEvent>) = runBlocking {
    val enriched = events.map { event ->
        async(Dispatchers.IO) {
            val legacy = withTimeoutOrNull(500.milliseconds) {
                legacyApi.fetchProduct(event.productId)
            }
            enrichWith(event, legacy)
        }
    }.awaitAll()
    indexService.bulkIndex(enriched)
}
```

### 9.4. IO 병렬화 패턴

```kotlin
// BAD: for 루프 순차 호출 — N건 × latency = 총 대기시간
fun enrichMany(ids: List<Long>): List<Product> {
    return ids.map { id ->
        val base = baseApi.fetch(id)  // 100ms
        val meta = metaApi.fetch(id)  // 100ms
        Product.from(base, meta)       // 총 200ms × N
    }
}

// GOOD: 각 ID 내부 병렬 + 전체 병렬
suspend fun enrichMany(ids: List<Long>): List<Product> = coroutineScope {
    ids.map { id ->
        async {
            val base = async { baseApi.fetch(id) }
            val meta = async { metaApi.fetch(id) }
            Product.from(base.await(), meta.await())
        }
    }.awaitAll()
}
```

### 9.5. 시간복잡도 — for × map 중첩 주의

```kotlin
// BAD: O(N × M) — 외부 리스트 × 내부 맵 조회 반복
fun analyze(keywords: List<String>, tokens: List<Token>): AnalysisResult {
    return keywords.flatMap { kw ->
        tokens.filter { tk -> match(kw, tk) }  // O(M)
            .map { tk -> reverse(tk) }          // O(L_tk)
    }
}

// GOOD: 인덱스 미리 구축 — O(N + M)
fun analyze(keywords: List<String>, tokens: List<Token>): AnalysisResult {
    val tokensByKey = tokens.groupBy { it.key }  // O(M)
    return keywords.flatMap { kw ->
        tokensByKey[kw.lowercase()].orEmpty().map { reverse(it) }  // O(1) lookup
    }
}
```

### 9.6. Python `asyncio` 병렬 호출

```python
# BAD: 순차
async def enrich(ids: list[int]) -> list[Product]:
    return [await fetch(id) for id in ids]

# GOOD: asyncio.gather
import asyncio
async def enrich(ids: list[int]) -> list[Product]:
    return await asyncio.gather(*(fetch(id) for id in ids))

# GOOD + 타임아웃
async def enrich(ids: list[int]) -> list[Product]:
    async def fetch_with_timeout(id: int) -> Product | None:
        try:
            return await asyncio.wait_for(fetch(id), timeout=0.5)
        except asyncio.TimeoutError:
            return None
    return await asyncio.gather(*(fetch_with_timeout(id) for id in ids))
```

### 체크리스트
- [ ] 외부 API 호출에 **연결/응답 타임아웃**이 설정되어 있는가
- [ ] 증분 색인/배치 처리 경로의 외부 API 타임아웃이 **≤ 500ms**인가
- [ ] Kafka 컨슈머 내부에서 **동기 HTTP 호출**이 있지 않은가 (코루틴/gather로 전환)
- [ ] `for` 루프에서 순차 IO 호출 대신 **병렬 실행**했는가
- [ ] 중첩 루프(`for` × `map`)의 시간복잡도를 확인했는가 (인덱스/해시맵 활용)
