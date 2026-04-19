---
name: observability-patterns
description: "관측성 패턴 레퍼런스 — OpenTelemetry 기반 로깅/트레이싱/메트릭, OTel Collector, Actuator, Health Check"
---

# 관측성(Observability) 패턴 레퍼런스 — OpenTelemetry 기준

## 1. 구조적 로깅 (Structured Logging)

### Kotlin/Spring Boot: SLF4J + Logback JSON

MDC(Mapped Diagnostic Context)를 활용하여 request-id, trace-id 등을 자동 전파한다.
OTel Logback Appender를 사용하면 trace context가 로그에 자동 주입된다.

```kotlin
// build.gradle.kts — 의존성
dependencies {
    implementation("net.logstash.logback:logstash-logback-encoder:7.4")
    implementation("io.opentelemetry.instrumentation:opentelemetry-logback-appender-1.33:2.4.0-alpha")
}
```

```xml
<!-- logback-spring.xml -->
<configuration>
    <appender name="JSON" class="ch.qos.logback.core.ConsoleAppender">
        <encoder class="net.logstash.logback.encoder.LogstashEncoder">
            <includeMdcKeyName>request_id</includeMdcKeyName>
            <includeMdcKeyName>user_id</includeMdcKeyName>
        </encoder>
    </appender>

    <!-- OTel Log Bridge: trace_id, span_id를 로그에 자동 주입 -->
    <appender name="OTEL"
        class="io.opentelemetry.instrumentation.logback.appender.v1_0.OpenTelemetryAppender">
        <appender-ref ref="JSON" />
    </appender>

    <root level="INFO">
        <appender-ref ref="OTEL" />
    </root>
</configuration>
```

```kotlin
import org.slf4j.LoggerFactory
import org.slf4j.MDC

@Component
class RequestLoggingFilter : OncePerRequestFilter() {
    private val log = LoggerFactory.getLogger(javaClass)

    override fun doFilterInternal(
        request: HttpServletRequest,
        response: HttpServletResponse,
        filterChain: FilterChain,
    ) {
        val requestId = request.getHeader("X-Request-ID") ?: UUID.randomUUID().toString()
        MDC.put("request_id", requestId)
        try {
            log.info("요청 시작: {} {}", request.method, request.requestURI)
            filterChain.doFilter(request, response)
        } finally {
            MDC.clear()
        }
    }
}
```

### Python/FastAPI: structlog + contextvars

```python
import structlog
import uuid
from contextvars import ContextVar

# contextvars로 요청 범위 컨텍스트 관리
request_id_var: ContextVar[str] = ContextVar("request_id", default="")
trace_id_var: ContextVar[str] = ContextVar("trace_id", default="")

structlog.configure(
    processors=[
        structlog.contextvars.merge_contextvars,    # contextvars 자동 병합
        structlog.processors.add_log_level,
        structlog.processors.TimeStamper(fmt="iso"),
        structlog.processors.JSONRenderer(),         # JSON 포맷 출력
    ],
    wrapper_class=structlog.make_filtering_bound_logger(logging.INFO),
)

logger = structlog.get_logger()
```

```python
from opentelemetry.sdk._logs import LoggerProvider
from opentelemetry.sdk._logs.export import BatchLogRecordProcessor
from opentelemetry.exporter.otlp.proto.grpc._log_exporter import OTLPLogExporter

# OTel Log Bridge 설정
logger_provider = LoggerProvider()
logger_provider.add_log_record_processor(
    BatchLogRecordProcessor(OTLPLogExporter(endpoint="http://otel-collector:4317"))
)

# structlog과 OTel 연동 미들웨어
from starlette.middleware.base import BaseHTTPMiddleware

class ObservabilityMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        request_id = request.headers.get("X-Request-ID", str(uuid.uuid4()))
        # contextvars에 바인딩 — 이후 모든 로그에 자동 포함
        structlog.contextvars.clear_contextvars()
        structlog.contextvars.bind_contextvars(
            request_id=request_id,
            method=request.method,
            path=request.url.path,
        )
        logger.info("요청 시작")
        response = await call_next(request)
        logger.info("요청 완료", status_code=response.status_code)
        return response
```

### 로그 레벨 전략

| Level | 사용 기준 | 예시 |
|---|---|---|
| `ERROR` | 즉시 대응 필요한 장애, 데이터 손실 위험 | DB 연결 실패, 결제 처리 실패, 데이터 정합성 깨짐 |
| `WARN` | 잠재적 문제, 곧 장애로 이어질 수 있는 상황 | 재시도 발생, 커넥션 풀 80% 도달, 비권장 API 호출 |
| `INFO` | 정상 비즈니스 이벤트, 상태 변경 | 주문 생성, 결제 완료, 배포 시작/종료 |
| `DEBUG` | 개발/디버깅 목적, 프로덕션에서는 비활성화 | SQL 쿼리, 요청/응답 상세 페이로드, 캐시 hit/miss |

### Bad/Good 비교

```kotlin
// Bad: 구조화되지 않은 문자열 로그 — 파싱 불가, 검색 어려움
log.info("User ${userId} placed order ${orderId} with total $totalAmount")

// Good: 구조적 로그 — JSON 필드로 색인 가능, 대시보드에서 필터링 가능
log.info("주문 생성 완료",
    kv("user_id", userId),
    kv("order_id", orderId),
    kv("total_amount", totalAmount),
    kv("item_count", items.size),
)
```

```python
# Bad: f-string 로그 — 구조화되지 않아 집계/필터링 불가
logger.info(f"User {user_id} placed order {order_id} with total {total_amount}")

# Good: structlog 키워드 인자 — JSON 필드로 자동 변환
logger.info("주문 생성 완료",
    user_id=user_id,
    order_id=order_id,
    total_amount=total_amount,
    item_count=len(items),
)
```

---

## 2. 분산 트레이싱 (Distributed Tracing)

### Trace/Span 개념

| 개념 | 설명 | 비유 |
|---|---|---|
| **Trace** | 하나의 요청이 여러 서비스를 거치는 전체 여정 | 택배 배송 추적 번호 |
| **Span** | Trace 내 하나의 작업 단위 (HTTP 호출, DB 쿼리 등) | 각 물류 센터 처리 기록 |
| **SpanContext** | trace_id + span_id + trace_flags, 서비스 간 전파 | 운송장의 바코드 |
| **Baggage** | Trace 전체에 전파되는 키-값 쌍 (사용자 정보 등) | 운송장의 메모 |

### Kotlin/Spring Boot: OTel Java Agent 자동 계측

JVM 에이전트를 붙이면 Spring MVC, WebFlux, JDBC, gRPC 등이 자동 계측된다.

```bash
# JVM 에이전트 설정 (Dockerfile 또는 k8s manifest)
java -javaagent:/app/opentelemetry-javaagent.jar \
  -Dotel.service.name=order-service \
  -Dotel.exporter.otlp.endpoint=http://otel-collector:4317 \
  -Dotel.resource.attributes=deployment.environment=production,service.version=1.2.0 \
  -jar app.jar
```

```yaml
# application.yml — Micrometer Tracing + OTel bridge
management:
  tracing:
    sampling:
      probability: 1.0   # 개발 환경: 전수 샘플링, 프로덕션: 0.1 권장
  otlp:
    tracing:
      endpoint: http://otel-collector:4318/v1/traces
```

```kotlin
import io.opentelemetry.instrumentation.annotations.WithSpan
import io.opentelemetry.instrumentation.annotations.SpanAttribute

@Service
class PaymentService(
    private val paymentClient: PaymentClient,
    private val orderRepository: OrderRepository,
) {
    // @WithSpan: 커스텀 span 생성 — 메서드 실행이 하나의 span으로 기록
    @WithSpan("payment.process")
    fun processPayment(
        @SpanAttribute("payment.order_id") orderId: Long,
        @SpanAttribute("payment.amount") amount: BigDecimal,
    ): PaymentResult {
        val order = orderRepository.findById(orderId)
            ?: throw OrderNotFoundException(orderId)

        // 외부 결제 API 호출 — OTel Agent가 HTTP 클라이언트를 자동 계측
        return paymentClient.charge(order.paymentMethod, amount)
    }
}
```

```kotlin
import io.opentelemetry.api.trace.Span
import io.opentelemetry.api.baggage.Baggage

@Service
class OrderService {
    // 수동 span attribute 추가
    fun createOrder(request: CreateOrderRequest): Order {
        val currentSpan = Span.current()
        currentSpan.setAttribute("order.item_count", request.items.size.toLong())
        currentSpan.setAttribute("order.total_amount", request.totalAmount.toDouble())

        // Baggage: 다운스트림 서비스에 사용자 정보 전파
        Baggage.current().toBuilder()
            .put("user.tier", request.userTier)
            .build()
            .makeCurrent()

        return processOrder(request)
    }
}
```

### Python/FastAPI: 자동 계측 + 수동 Span

```bash
# 자동 계측 패키지 설치
pip install opentelemetry-distro opentelemetry-exporter-otlp
opentelemetry-bootstrap -a install
```

```python
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
from opentelemetry.sdk.resources import Resource

# TracerProvider 초기화
resource = Resource.create({
    "service.name": "order-service",
    "service.version": "1.2.0",
    "deployment.environment": "production",
})

provider = TracerProvider(resource=resource)
provider.add_span_processor(
    BatchSpanProcessor(OTLPSpanExporter(endpoint="http://otel-collector:4317"))
)
trace.set_tracer_provider(provider)

# FastAPI 자동 계측 — 모든 엔드포인트에 span 생성
FastAPIInstrumentor.instrument_app(app)
```

```python
from opentelemetry import trace, baggage
from opentelemetry.context import attach, detach

tracer = trace.get_tracer(__name__)

class PaymentService:
    async def process_payment(self, order_id: int, amount: int) -> PaymentResult:
        # 수동 span 생성
        with tracer.start_as_current_span(
            "payment.process",
            attributes={
                "payment.order_id": order_id,
                "payment.amount": amount,
            },
        ) as span:
            try:
                result = await self.payment_client.charge(order_id, amount)
                span.set_attribute("payment.status", result.status)
                return result
            except PaymentError as e:
                # span에 에러 정보 기록
                span.set_status(trace.StatusCode.ERROR, str(e))
                span.record_exception(e)
                raise

    async def create_order(self, request: CreateOrderRequest) -> Order:
        # Baggage 전파: 다운스트림 서비스에 사용자 정보 전달
        ctx = baggage.set_baggage("user.tier", request.user_tier)
        token = attach(ctx)
        try:
            return await self._process(request)
        finally:
            detach(token)
```

### W3C TraceContext 전파

```
# HTTP 헤더로 trace context가 자동 전파됨
traceparent: 00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01
tracestate: vendor1=value1
```

OTel SDK는 기본적으로 W3C TraceContext propagator를 사용하며,
Spring Boot와 FastAPI 모두 자동 계측 시 헤더를 자동으로 주입/추출한다.

---

## 3. 메트릭 수집 (Metrics)

### RED 메서드 — 서비스 수준 핵심 메트릭

| 메트릭 | 설명 | Kotlin/Spring Boot | Python/FastAPI |
|---|---|---|---|
| **R**ate (요청률) | 초당 요청 수 | `http.server.requests` (자동) | Counter로 수동 수집 |
| **E**rror (에러율) | 에러 응답 비율 | `http.server.requests` outcome=SERVER_ERROR | Counter (status >= 400) |
| **D**uration (응답시간) | 요청 처리 시간 | Timer (자동), `@Timed` | Histogram으로 수동 수집 |

### Kotlin/Spring Boot: Micrometer + OTel Bridge

```kotlin
// build.gradle.kts
dependencies {
    implementation("io.micrometer:micrometer-registry-otlp")
    implementation("org.springframework.boot:spring-boot-starter-actuator")
}
```

```yaml
# application.yml
management:
  endpoints:
    web:
      exposure:
        include: health,info,prometheus,metrics
  otlp:
    metrics:
      export:
        url: http://otel-collector:4318/v1/metrics
        step: 30s
  metrics:
    tags:
      application: order-service
      environment: ${SPRING_PROFILES_ACTIVE:local}
```

```kotlin
import io.micrometer.core.annotation.Timed
import io.micrometer.core.instrument.Counter
import io.micrometer.core.instrument.MeterRegistry
import io.micrometer.core.instrument.Timer

@Service
class OrderService(
    private val meterRegistry: MeterRegistry,
    private val orderRepository: OrderRepository,
) {
    // Counter: 주문 생성 횟수
    private val orderCounter = Counter.builder("order.created.total")
        .description("생성된 주문 수")
        .tag("service", "order-service")
        .register(meterRegistry)

    // Gauge: 대기 중인 주문 수 (현재 값을 반영)
    init {
        meterRegistry.gauge("order.pending.count", this) {
            orderRepository.countByStatus(OrderStatus.PENDING).toDouble()
        }
    }

    // @Timed: 메서드 실행 시간을 자동 측정
    @Timed(
        value = "order.creation.duration",
        description = "주문 생성 소요 시간",
        percentiles = [0.5, 0.95, 0.99],
    )
    fun createOrder(request: CreateOrderRequest): Order {
        val order = orderRepository.save(Order.from(request))
        orderCounter.increment()
        return order
    }

    // Timer: 외부 API 호출 시간 수동 측정
    fun callExternalApi(orderId: Long) {
        val timer = Timer.builder("external.api.duration")
            .tag("api", "payment")
            .register(meterRegistry)

        timer.record {
            paymentClient.process(orderId)
        }
    }
}
```

### Python/FastAPI: OTel Metrics API

```python
from opentelemetry import metrics
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader
from opentelemetry.exporter.otlp.proto.grpc.metric_exporter import OTLPMetricExporter

# MeterProvider 초기화
metric_reader = PeriodicExportingMetricReader(
    OTLPMetricExporter(endpoint="http://otel-collector:4317"),
    export_interval_millis=30000,
)
meter_provider = MeterProvider(metric_readers=[metric_reader], resource=resource)
metrics.set_meter_provider(meter_provider)

meter = metrics.get_meter(__name__)
```

```python
# Counter: 주문 생성 횟수
order_counter = meter.create_counter(
    name="order.created.total",
    description="생성된 주문 수",
    unit="1",
)

# Histogram: 요청 처리 시간 분포
request_duration = meter.create_histogram(
    name="http.server.duration",
    description="HTTP 요청 처리 시간",
    unit="ms",
)

# UpDownCounter: 현재 활성 연결 수 (증감 가능)
active_connections = meter.create_up_down_counter(
    name="http.server.active_connections",
    description="현재 활성 HTTP 연결 수",
)
```

```python
import time
from starlette.middleware.base import BaseHTTPMiddleware

class MetricsMiddleware(BaseHTTPMiddleware):
    """RED 메서드 메트릭을 자동 수집하는 미들웨어"""

    async def dispatch(self, request: Request, call_next):
        active_connections.add(1)
        start = time.perf_counter()

        try:
            response = await call_next(request)
            elapsed_ms = (time.perf_counter() - start) * 1000

            # Rate + Duration
            request_duration.record(
                elapsed_ms,
                attributes={
                    "http.method": request.method,
                    "http.route": request.url.path,
                    "http.status_code": response.status_code,
                },
            )

            # Error rate
            if response.status_code >= 400:
                order_counter.add(1, attributes={
                    "type": "error",
                    "status_code": response.status_code,
                })

            return response
        finally:
            active_connections.add(-1)
```

### Actuator 엔드포인트 설정

```yaml
# application.yml — Prometheus 스크래핑용 Actuator
management:
  endpoints:
    web:
      exposure:
        include: health,prometheus,info,metrics
  endpoint:
    health:
      show-details: when_authorized
    prometheus:
      enabled: true
  prometheus:
    metrics:
      export:
        enabled: true
```

| Endpoint | 용도 | 접근 제어 |
|---|---|---|
| `/actuator/prometheus` | Prometheus 메트릭 스크래핑 | 내부 네트워크만 허용 |
| `/actuator/metrics` | 개별 메트릭 조회 (JSON) | 개발/디버깅용 |
| `/actuator/health` | 헬스 체크 (아래 섹션 참고) | 쿠버네티스 probe |
| `/actuator/info` | 빌드 정보, git 커밋 | 배포 확인용 |

---

## 4. Health Check 패턴

### Kotlin/Spring Boot: Actuator Health Indicators

```yaml
# application.yml
management:
  endpoint:
    health:
      show-details: when_authorized
      group:
        liveness:
          include: livenessState
        readiness:
          include: readinessState,db,redis,kafka
  health:
    livenessstate:
      enabled: true
    readinessstate:
      enabled: true
```

```kotlin
import org.springframework.boot.actuate.health.Health
import org.springframework.boot.actuate.health.HealthIndicator

// 커스텀 HealthIndicator: Redis 연결 확인
@Component
class RedisHealthIndicator(
    private val redisTemplate: StringRedisTemplate,
) : HealthIndicator {

    override fun health(): Health {
        return try {
            val result = redisTemplate.connectionFactory?.connection?.ping()
            if (result == "PONG") {
                Health.up()
                    .withDetail("connection", "active")
                    .build()
            } else {
                Health.down()
                    .withDetail("reason", "unexpected response: $result")
                    .build()
            }
        } catch (ex: Exception) {
            Health.down(ex)
                .withDetail("reason", "연결 실패")
                .build()
        }
    }
}

// 커스텀 HealthIndicator: Kafka 브로커 연결 확인
@Component
class KafkaHealthIndicator(
    private val kafkaAdmin: AdminClient,
) : HealthIndicator {

    override fun health(): Health {
        return try {
            val nodes = kafkaAdmin.describeCluster()
                .nodes()
                .get(5, TimeUnit.SECONDS)
            Health.up()
                .withDetail("broker_count", nodes.size)
                .build()
        } catch (ex: Exception) {
            Health.down(ex)
                .withDetail("reason", "브로커 연결 실패")
                .build()
        }
    }
}
```

### Python/FastAPI: 커스텀 Health Endpoint

```python
from enum import Enum
from pydantic import BaseModel
from sqlalchemy import text

class HealthStatus(str, Enum):
    UP = "UP"
    DOWN = "DOWN"

class ComponentHealth(BaseModel):
    status: HealthStatus
    detail: str | None = None

class HealthResponse(BaseModel):
    status: HealthStatus
    components: dict[str, ComponentHealth]

async def check_db(db: AsyncSession) -> ComponentHealth:
    try:
        await db.execute(text("SELECT 1"))
        return ComponentHealth(status=HealthStatus.UP)
    except Exception as e:
        return ComponentHealth(status=HealthStatus.DOWN, detail=str(e))

async def check_redis(redis: Redis) -> ComponentHealth:
    try:
        if await redis.ping():
            return ComponentHealth(status=HealthStatus.UP)
        return ComponentHealth(status=HealthStatus.DOWN, detail="ping 실패")
    except Exception as e:
        return ComponentHealth(status=HealthStatus.DOWN, detail=str(e))

@app.get("/health/live", response_model=ComponentHealth)
async def liveness():
    """Liveness: 애플리케이션 프로세스가 살아있는지만 확인"""
    return ComponentHealth(status=HealthStatus.UP)

@app.get("/health/ready", response_model=HealthResponse)
async def readiness(
    db: AsyncSession = Depends(get_db),
    redis: Redis = Depends(get_redis),
):
    """Readiness: 트래픽을 받을 준비가 됐는지 확인 (의존 서비스 포함)"""
    components = {
        "db": await check_db(db),
        "redis": await check_redis(redis),
    }
    overall = HealthStatus.UP if all(
        c.status == HealthStatus.UP for c in components.values()
    ) else HealthStatus.DOWN

    return HealthResponse(status=overall, components=components)
```

### Liveness vs Readiness vs Startup Probe

| Probe | 목적 | 실패 시 동작 | 체크 대상 |
|---|---|---|---|
| **Liveness** | 프로세스가 살아있는지 확인 | 컨테이너 재시작 | 애플리케이션 프로세스만 (외부 의존성 X) |
| **Readiness** | 트래픽을 받을 준비가 됐는지 확인 | 서비스 엔드포인트에서 제외 | DB, Redis, Kafka 등 의존 서비스 포함 |
| **Startup** | 초기 기동이 완료됐는지 확인 | 기동 실패로 간주, 재시작 | 느린 초기화 (캐시 워밍, 마이그레이션 등) |

### Kubernetes Probe 설정

```yaml
# k8s deployment manifest
spec:
  containers:
    - name: order-service
      livenessProbe:
        httpGet:
          path: /actuator/health/liveness    # Spring Boot
          # path: /health/live               # FastAPI
          port: 8080
        initialDelaySeconds: 30
        periodSeconds: 10
        failureThreshold: 3
      readinessProbe:
        httpGet:
          path: /actuator/health/readiness   # Spring Boot
          # path: /health/ready              # FastAPI
          port: 8080
        initialDelaySeconds: 10
        periodSeconds: 5
        failureThreshold: 3
      startupProbe:
        httpGet:
          path: /actuator/health/liveness
          port: 8080
        initialDelaySeconds: 0
        periodSeconds: 5
        failureThreshold: 30   # 최대 150초 대기 (5s * 30)
```

---

## 5. OTel Collector 연동 & Exporter 설정

### OTel Collector 아키텍처

```
┌──────────────────────────────────────────────────────┐
│                  OTel Collector                       │
│                                                      │
│  ┌──────────┐    ┌────────────┐    ┌──────────────┐  │
│  │ Receiver │───▶│ Processor  │───▶│   Exporter   │  │
│  │          │    │            │    │              │  │
│  │ - OTLP   │    │ - batch    │    │ - OTLP       │  │
│  │ - Jaeger │    │ - memory   │    │ - Prometheus │  │
│  │ - Prom   │    │   _limiter │    │ - Jaeger     │  │
│  │          │    │ - filter   │    │ - Loki       │  │
│  └──────────┘    └────────────┘    └──────────────┘  │
│                                                      │
│  Pipelines:                                          │
│    traces:  otlp → batch → jaeger                    │
│    metrics: otlp → batch → prometheus                │
│    logs:    otlp → batch → loki                      │
└──────────────────────────────────────────────────────┘
```

```yaml
# otel-collector-config.yml
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
      http:
        endpoint: 0.0.0.0:4318

processors:
  batch:
    timeout: 5s
    send_batch_size: 1024
  memory_limiter:
    check_interval: 1s
    limit_mib: 512
    spike_limit_mib: 128
  filter:
    # 헬스체크 span 필터링 — 불필요한 트레이스 제거
    traces:
      span:
        - 'attributes["http.route"] == "/health/live"'
        - 'attributes["http.route"] == "/actuator/health"'

exporters:
  otlp/jaeger:
    endpoint: jaeger-collector:4317
    tls:
      insecure: true
  prometheus:
    endpoint: 0.0.0.0:8889
  loki:
    endpoint: http://loki:3100/loki/api/v1/push

service:
  pipelines:
    traces:
      receivers: [otlp]
      processors: [memory_limiter, filter, batch]
      exporters: [otlp/jaeger]
    metrics:
      receivers: [otlp]
      processors: [memory_limiter, batch]
      exporters: [prometheus]
    logs:
      receivers: [otlp]
      processors: [memory_limiter, batch]
      exporters: [loki]
```

### Kotlin: OTLP Exporter 설정

```yaml
# application.yml — Spring Boot OTel 설정
management:
  otlp:
    tracing:
      endpoint: http://otel-collector:4318/v1/traces
    metrics:
      export:
        url: http://otel-collector:4318/v1/metrics
        step: 30s

# OTel Java Agent 사용 시 JVM 옵션으로 설정
# -Dotel.exporter.otlp.endpoint=http://otel-collector:4317
# -Dotel.service.name=order-service
# -Dotel.resource.attributes=deployment.environment=production
```

```yaml
# k8s deployment — 환경변수로 OTel 설정 주입
spec:
  containers:
    - name: order-service
      env:
        - name: OTEL_SERVICE_NAME
          value: order-service
        - name: OTEL_EXPORTER_OTLP_ENDPOINT
          value: http://otel-collector:4317
        - name: OTEL_RESOURCE_ATTRIBUTES
          value: "deployment.environment=production,service.version=1.2.0"
        - name: OTEL_TRACES_SAMPLER
          value: parentbased_traceidratio
        - name: OTEL_TRACES_SAMPLER_ARG
          value: "0.1"
```

### Python: 환경변수 기반 설정

```bash
# 환경변수만으로 OTel 설정 — 코드 변경 없이 동작
export OTEL_SERVICE_NAME=order-service
export OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4317
export OTEL_RESOURCE_ATTRIBUTES="deployment.environment=production,service.version=1.2.0"
export OTEL_TRACES_SAMPLER=parentbased_traceidratio
export OTEL_TRACES_SAMPLER_ARG=0.1
export OTEL_LOGS_EXPORTER=otlp
export OTEL_METRICS_EXPORTER=otlp

# opentelemetry-instrument로 자동 계측 실행
opentelemetry-instrument uvicorn main:app --host 0.0.0.0 --port 8000
```

```python
# 프로그래밍 방식 설정 (세밀한 제어가 필요할 때)
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter

exporter = OTLPSpanExporter(
    endpoint="http://otel-collector:4317",
    headers={"x-api-key": "secret"},  # 인증이 필요한 경우
    timeout=10,
)

provider = TracerProvider(resource=resource)
provider.add_span_processor(
    BatchSpanProcessor(
        exporter,
        max_queue_size=2048,
        max_export_batch_size=512,
        schedule_delay_millis=5000,
    )
)
```

### 샘플링 전략

| 전략 | 설명 | 적합한 환경 |
|---|---|---|
| `always_on` | 모든 요청 트레이싱 | 개발/스테이징 |
| `always_off` | 트레이싱 비활성화 | 부하 테스트 |
| `traceidratio` | trace_id 해시 기반 확률 샘플링 (예: 0.1 = 10%) | 프로덕션 (트래픽 높을 때) |
| `parentbased_traceidratio` | 부모 span이 있으면 따르고, 없으면 ratio 적용 | 프로덕션 (권장) |
| `parentbased_always_on` | 부모 span이 있으면 따르고, 없으면 전수 | 프로덕션 (트래픽 낮을 때) |

```kotlin
// Kotlin: 프로그래밍 방식 샘플러 설정 (특수한 경우)
import io.opentelemetry.sdk.trace.samplers.Sampler

val sampler = Sampler.parentBased(
    Sampler.traceIdRatioBased(0.1)  // 루트 span의 10%만 샘플링
)
```

```python
# Python: 커스텀 샘플러 — 특정 경로는 항상 샘플링
from opentelemetry.sdk.trace.sampling import (
    ParentBasedTraceIdRatio,
    ALWAYS_ON,
    Decision,
    SamplingResult,
)

class CustomSampler:
    """결제 관련 요청은 전수 샘플링, 나머지는 10%"""

    def __init__(self):
        self.default = ParentBasedTraceIdRatio(0.1)
        self.always_on = ALWAYS_ON

    def should_sample(self, context, trace_id, name, kind, attributes, links):
        # 결제 span은 전수 트레이싱
        if name.startswith("payment.") or "payment" in attributes.get("http.route", ""):
            return self.always_on.should_sample(
                context, trace_id, name, kind, attributes, links
            )
        return self.default.should_sample(
            context, trace_id, name, kind, attributes, links
        )
```

---

## 6. 에러 로깅 vs 스로잉 — 기능적 분리

에러 로깅과 예외 스로잉은 **서로 다른 기능**이다. 동시에 사용하거나 혼동하면 장애 진단이 어려워진다.

### 원칙

| 상황 | 로깅 | 스로잉 | 이유 |
|---|---|---|---|
| 비즈니스 실패 (예상된 에러) | 경우에 따라 | ✅ (ex: 도메인 예외) | 상위에서 처리 결정 |
| 시스템 장애 (예상 못함) | ✅ ERROR | ✅ | 복구 불가, 상위 전파 필요 |
| 복구 가능한 외부 호출 실패 | ✅ WARN + 재시도 | ❌ (재시도 후 성공하면 됨) | 정상 흐름의 일부 |
| 로깅만 하고 삼키기 (swallow) | ✅ ERROR | ❌ | **안티패턴** — 호출자가 상태 모름 |
| 로깅 + 다른 예외로 랩핑 | ✅ | ✅ | 체인 유지 (`cause = e`) |

### 안티패턴 1: 로그 찍고 스로잉도 하기 (이중 보고)

```kotlin
// BAD: 같은 에러가 두 번 로깅됨 (메서드에서 찍고, @ControllerAdvice에서 또 찍음)
@Service
class ElasticsearchTemplate(private val client: ElasticsearchClient) {
    fun bulkIndex(requests: List<IndexRequest>) {
        try {
            client.bulk(BulkRequest.Builder().operations(...).build())
        } catch (e: ElasticsearchException) {
            logger.error("ES bulk indexing failed: ${e.message}", e) // 로그 1회
            throw SearchInfraException("bulk failed", e)              // @ControllerAdvice에서 또 로그
        }
    }
}

// GOOD: 둘 중 하나만. 통상적으로 "상위 전파"가 좋음
fun bulkIndex(requests: List<IndexRequest>) {
    try {
        client.bulk(BulkRequest.Builder().operations(...).build())
    } catch (e: ElasticsearchException) {
        throw SearchInfraException("bulk indexing failed for ${requests.size} requests", e)
        // 최종 로깅은 @ControllerAdvice 또는 global handler에서 1회
    }
}
```

### 안티패턴 2: 예외 삼키기 (swallow)

```kotlin
// BAD: catch만 하고 아무것도 안 함
try {
    client.bulk(...)
} catch (e: IOException) {
    logger.error("ignored", e) // 상위는 성공한 줄 앎
}

// GOOD: 복구 불가능하면 재시도 or 스로잉
try {
    retryTemplate.execute { client.bulk(...) }
} catch (e: IOException) {
    throw BulkIndexingException("after ${retryAttempts} retries", e)
}
```

### 안티패턴 3: 성공 건수만 로깅

```kotlin
// BAD: 실패 분석 불가능
val response = client.bulk(request)
logger.info("Bulk completed: success=${response.items().count { !it.isFailed }}")

// GOOD: 실패 operation + 원인 별도 기록
val failures = response.items().filter { it.isFailed }
if (failures.isNotEmpty()) {
    logger.error(
        "Bulk partial failure: total={}, failed={}, first_error='{}'",
        response.items().size,
        failures.size,
        failures.first().error()?.reason(),
    )
    failures.take(10).forEach { item ->
        logger.error(
            "  op={} index={} id={} error={}",
            item.operationType(), item.index(), item.id(), item.error()?.reason()
        )
    }
}
```

### 안티패턴 4: 도메인 맥락 누락

```kotlin
// BAD: "sync failed" 만으로 어느 도메인인지 모름
logger.error("sync failed", e)

// GOOD: 도메인 + ID + 작업 종류 명시
logger.error("역싱크 실패: catalogId={} op={} reason={}", catalogId, op, e.message, e)
```

### 롤백과 로깅

트랜잭션 내에서 로깅만 하고 계속 진행하면 **부분 성공 상태**가 커밋될 위험. 복구 불가능한 에러는 반드시 스로잉해서 롤백 트리거.

```kotlin
@Transactional
fun updateProducts(changes: List<ProductChange>) {
    changes.forEach { change ->
        try {
            productRepository.update(change)
        } catch (e: DataIntegrityViolationException) {
            // BAD: 로그만 찍고 다음 건으로 — 부분 성공 커밋됨
            // logger.error("update failed for ${change.id}", e)
            // return@forEach

            // GOOD: 롤백 트리거
            throw BulkUpdateException("failed at ${change.id}", e)
        }
    }
}
```

### 체크리스트
- [ ] 같은 예외를 중간 계층과 global handler에서 **중복 로깅**하지 않는가
- [ ] 복구 불가능한 에러를 **삼키지**(log + swallow) 않는가
- [ ] 배치 작업의 로깅이 **성공 건수뿐 아니라 실패 건수+원인**을 포함하는가
- [ ] 로그 메시지에 **도메인 맥락**(entity id, operation type)이 있는가
- [ ] 트랜잭션 내 에러 처리가 **부분 성공을 허용**하고 있지 않은가
