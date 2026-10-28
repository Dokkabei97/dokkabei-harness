---
name: resilience-patterns
description: |
  회복 탄력성 패턴 레퍼런스 — Circuit Breaker(Resilience4j), Retry, Timeout, Bulkhead, Spring WebClient 에러 처리, httpx retry
  Reference for resilience patterns — Circuit Breaker (Resilience4j), Retry, Timeout, Bulkhead, Spring WebClient error handling, and httpx retry. Use when: hardening calls to unreliable dependencies, adding circuit breakers or retries, setting timeouts, handling WebClient/httpx failures.
---

# 회복 탄력성(Resilience) 패턴 레퍼런스

## 1. Circuit Breaker

서킷 브레이커는 반복적인 실패를 감지하여 장애가 전파되는 것을 차단한다.
다운스트림 서비스가 응답하지 않을 때 빠르게 실패(fail-fast)하여 리소스 고갈을 방지한다.

### 상태 전이 다이어그램

```
CLOSED ──(실패율 >= 임계값)──→ OPEN
  ↑                              │
  │                     (waitDurationInOpenState 경과)
  │                              ↓
  └──(성공률 >= 임계값)── HALF_OPEN
                            │
                    (성공률 < 임계값)
                            ↓
                          OPEN
```

| 상태 | 설명 | 요청 처리 |
|------|------|-----------|
| `CLOSED` | 정상 상태 — 모든 요청 통과 | 실패/성공 카운트 |
| `OPEN` | 차단 상태 — 즉시 fallback 반환 | 요청 차단 |
| `HALF_OPEN` | 테스트 상태 — 제한된 요청만 허용 | 허용된 수만큼 통과 후 판정 |

### Resilience4j 설정 (application.yml)

```yaml
# application.yml
resilience4j:
  circuitbreaker:
    configs:
      default:
        slidingWindowType: COUNT_BASED          # COUNT_BASED | TIME_BASED
        slidingWindowSize: 100                   # 슬라이딩 윈도우 크기
        failureRateThreshold: 50                 # 실패율 임계값 (%)
        waitDurationInOpenState: 30s             # OPEN 유지 시간
        permittedNumberOfCallsInHalfOpenState: 10 # HALF_OPEN에서 허용 요청 수
        minimumNumberOfCalls: 20                 # 집계 최소 호출 수
        recordExceptions:                        # 실패로 기록할 예외
          - java.io.IOException
          - java.util.concurrent.TimeoutException
          - org.springframework.web.reactive.function.client.WebClientResponseException
        ignoreExceptions:                        # 무시할 예외 (실패로 카운트 안 함)
          - com.example.BusinessException
    instances:
      payment-service:
        baseConfig: default
        failureRateThreshold: 30                 # 결제는 더 민감하게
        waitDurationInOpenState: 60s
      product-service:
        baseConfig: default
```

### Kotlin/Spring Boot: @CircuitBreaker 적용

```kotlin
import io.github.resilience4j.circuitbreaker.annotation.CircuitBreaker

@Service
class PaymentService(
    private val paymentClient: PaymentClient,
    private val paymentCacheRepository: PaymentCacheRepository,
) {
    companion object {
        private const val CB_PAYMENT = "payment-service"
    }

    // @CircuitBreaker: 서킷 브레이커 적용, fallback 메서드 지정
    @CircuitBreaker(name = CB_PAYMENT, fallbackMethod = "paymentFallback")
    fun processPayment(request: PaymentRequest): PaymentResponse {
        return paymentClient.requestPayment(request)
    }

    // fallback: 원본 메서드와 동일한 파라미터 + Throwable 파라미터
    private fun paymentFallback(
        request: PaymentRequest,
        ex: Throwable,
    ): PaymentResponse {
        logger.warn("결제 서비스 장애 — fallback 실행: ${ex.message}")
        // 캐시된 결제 수단 정보로 degraded response 반환
        val cached = paymentCacheRepository.findByUserId(request.userId)
        return PaymentResponse.degraded(cached, "결제 서비스 일시 장애")
    }
}
```

### Python: pybreaker 적용

```python
import pybreaker
import logging

logger = logging.getLogger(__name__)

# 서킷 브레이커 인스턴스 생성
payment_breaker = pybreaker.CircuitBreaker(
    fail_max=5,                    # OPEN 전환까지 허용 실패 횟수
    reset_timeout=30,              # OPEN → HALF_OPEN 전환 대기 시간(초)
    exclude=[ValueError],          # 실패로 카운트하지 않을 예외
    listeners=[pybreaker.LogListener(logger)],  # 상태 변경 로깅
)


class PaymentService:
    def __init__(self, payment_client: PaymentClient):
        self._client = payment_client

    @payment_breaker
    async def process_payment(self, request: PaymentRequest) -> PaymentResponse:
        """서킷 브레이커가 적용된 결제 처리"""
        return await self._client.request_payment(request)

    async def process_payment_with_fallback(
        self, request: PaymentRequest,
    ) -> PaymentResponse:
        """fallback 포함 결제 처리"""
        try:
            return await self.process_payment(request)
        except pybreaker.CircuitBreakerError:
            logger.warning("결제 서비스 서킷 OPEN — fallback 응답 반환")
            return PaymentResponse.degraded(
                message="결제 서비스 일시 장애, 잠시 후 재시도해주세요",
            )
```

---

## 2. Retry

일시적인 장애(네트워크 글리치, 일시적 5xx)에 대해 자동 재시도한다.
멱등성이 보장되지 않는 요청(POST 결제 등)에는 신중하게 적용해야 한다.

### 멱등성 고려사항

| HTTP 메서드 | 멱등성 | 재시도 안전성 | 비고 |
|-------------|--------|---------------|------|
| `GET` | O | 안전 | 항상 재시도 가능 |
| `PUT` | O | 안전 | 전체 리소스 교체이므로 멱등 |
| `DELETE` | O | 안전 | 이미 삭제된 리소스에 대해 404 허용 |
| `POST` | X | 주의 필요 | idempotency key 필수 |
| `PATCH` | 경우에 따라 | 주의 필요 | 증분 변경 시 중복 적용 위험 |

### Resilience4j 설정 (application.yml)

```yaml
resilience4j:
  retry:
    configs:
      default:
        maxAttempts: 3                       # 최대 시도 횟수 (첫 시도 포함)
        waitDuration: 500ms                  # 재시도 간 대기 시간
        enableExponentialBackoff: true       # 지수 백오프 활성화
        exponentialBackoffMultiplier: 2      # 백오프 배수
        enableRandomizedWait: true           # 지터(jitter) 추가 — 동시 재시도 분산
        randomizedWaitFactor: 0.5            # 지터 범위 (waitDuration * factor)
        retryExceptions:
          - java.io.IOException
          - java.util.concurrent.TimeoutException
        ignoreExceptions:
          - com.example.BusinessException    # 비즈니스 예외는 재시도 불필요
    instances:
      product-service:
        baseConfig: default
        maxAttempts: 5                       # 상품 조회는 더 많이 재시도
```

### Kotlin/Spring Boot: @Retry 적용

```kotlin
import io.github.resilience4j.retry.annotation.Retry

@Service
class ProductService(
    private val productClient: ProductClient,
    private val productCacheRepository: ProductCacheRepository,
) {
    // @Retry: 지수 백오프 + 지터로 자동 재시도
    @Retry(name = "product-service", fallbackMethod = "getProductFallback")
    fun getProduct(productId: Long): ProductResponse {
        return productClient.fetchProduct(productId)
    }

    // 모든 재시도 실패 후 fallback 실행
    private fun getProductFallback(
        productId: Long,
        ex: Throwable,
    ): ProductResponse {
        logger.warn("상품 조회 재시도 모두 실패 (productId=$productId): ${ex.message}")
        // 캐시된 상품 정보 반환
        return productCacheRepository.findById(productId)
            ?.toResponse()
            ?: throw ServiceUnavailableException("상품 서비스 일시 장애")
    }
}
```

### Python: tenacity @retry 적용

```python
from tenacity import (
    retry,
    stop_after_attempt,
    wait_exponential_jitter,
    retry_if_exception_type,
    before_sleep_log,
)
import httpx
import logging

logger = logging.getLogger(__name__)


class ProductService:
    def __init__(self, client: httpx.AsyncClient):
        self._client = client

    @retry(
        stop=stop_after_attempt(3),                         # 최대 3회 시도
        wait=wait_exponential_jitter(
            initial=0.5,                                    # 초기 대기 0.5초
            max=10,                                         # 최대 대기 10초
            jitter=2,                                       # 지터 최대 2초
        ),
        retry=retry_if_exception_type((
            httpx.ConnectTimeout,
            httpx.ReadTimeout,
            httpx.ConnectError,
        )),
        before_sleep=before_sleep_log(logger, logging.WARNING),  # 재시도 전 로깅
    )
    async def get_product(self, product_id: int) -> ProductResponse:
        """tenacity 재시도가 적용된 상품 조회"""
        response = await self._client.get(f"/api/products/{product_id}")
        response.raise_for_status()
        return ProductResponse.model_validate(response.json())
```

---

## 3. Timeout

타임아웃을 설정하지 않으면 다운스트림 장애가 스레드/커넥션 고갈로 이어진다.
connection timeout과 read timeout을 구분하여 적절한 값을 설정해야 한다.

### 타임아웃 유형 구분

| 유형 | 설명 | 권장값 | 위험 시나리오 |
|------|------|--------|---------------|
| `connectionTimeout` | TCP 연결 수립 대기 | 1~3초 | 서버 접근 불가 시 빠른 실패 |
| `readTimeout` | 응답 데이터 수신 대기 | 3~30초 (API별 상이) | 서버 처리 지연 |
| `writeTimeout` | 요청 데이터 전송 대기 | 5~10초 | 대용량 요청 전송 |
| `callTimeout` | 전체 호출 (연결+전송+수신) | readTimeout * 1.5 | 전체 호출 시간 제한 |

### Resilience4j: @TimeLimiter 적용

```kotlin
import io.github.resilience4j.timelimiter.annotation.TimeLimiter
import java.util.concurrent.CompletableFuture

@Service
class ExternalApiService(
    private val externalClient: ExternalClient,
) {
    // @TimeLimiter: 비동기 메서드에 타임아웃 적용
    // 반환 타입이 CompletableFuture/Mono 이어야 함
    @TimeLimiter(name = "external-api", fallbackMethod = "timeoutFallback")
    fun fetchExternalData(query: String): CompletableFuture<ExternalData> {
        return CompletableFuture.supplyAsync {
            externalClient.search(query)
        }
    }

    private fun timeoutFallback(
        query: String,
        ex: Throwable,
    ): CompletableFuture<ExternalData> {
        logger.warn("외부 API 타임아웃 (query=$query): ${ex.message}")
        return CompletableFuture.completedFuture(ExternalData.empty())
    }
}
```

```yaml
# application.yml
resilience4j:
  timelimiter:
    configs:
      default:
        timeoutDuration: 5s                  # 기본 타임아웃
        cancelRunningFuture: true            # 타임아웃 시 Future 취소
    instances:
      external-api:
        baseConfig: default
        timeoutDuration: 10s                 # 외부 API는 여유있게
      internal-api:
        baseConfig: default
        timeoutDuration: 3s                  # 내부 API는 짧게
```

### Python: asyncio.wait_for 적용

```python
import asyncio
import httpx


class ExternalApiService:
    def __init__(self, client: httpx.AsyncClient):
        self._client = client

    async def fetch_with_timeout(
        self,
        url: str,
        timeout_seconds: float = 5.0,
    ) -> dict:
        """개별 호출에 대한 명시적 타임아웃"""
        try:
            response = await asyncio.wait_for(
                self._client.get(url),
                timeout=timeout_seconds,
            )
            response.raise_for_status()
            return response.json()
        except asyncio.TimeoutError:
            logger.warning(f"타임아웃 발생: {url} ({timeout_seconds}초 초과)")
            raise ServiceTimeoutError(f"{url} 호출 타임아웃")

    async def fetch_multiple_with_timeout(
        self,
        urls: list[str],
        per_call_timeout: float = 5.0,
        total_timeout: float = 15.0,
    ) -> list[dict | None]:
        """여러 호출을 동시에 수행하되, 전체 타임아웃 제한"""
        async def _safe_fetch(url: str) -> dict | None:
            try:
                return await asyncio.wait_for(
                    self._client.get(url),
                    timeout=per_call_timeout,
                )
            except (asyncio.TimeoutError, httpx.HTTPError):
                logger.warning(f"개별 호출 실패: {url}")
                return None

        # 전체 작업에 대한 상위 타임아웃
        results = await asyncio.wait_for(
            asyncio.gather(*[_safe_fetch(url) for url in urls]),
            timeout=total_timeout,
        )
        return results
```

---

## 4. Bulkhead

벌크헤드는 리소스를 격리하여 하나의 다운스트림 장애가 전체 시스템에 영향을 미치지 않도록 한다.
선박의 격벽처럼 장애를 해당 구획에 가둔다.

### Resilience4j: 벌크헤드 유형 비교

| 항목 | Thread Pool Bulkhead | Semaphore Bulkhead |
|------|---------------------|--------------------|
| 격리 방식 | 독립 스레드 풀 | 세마포어 (동시성 제한) |
| 리소스 사용 | 스레드 풀당 스레드 할당 | 기존 스레드에서 실행 |
| 큐잉 | O (coreThreadPoolSize + queueCapacity) | X |
| 타임아웃 | O (keepAliveDuration) | X (별도 TimeLimiter 필요) |
| 적합한 상황 | 블로킹 I/O, 서비스별 격리 필요 | 비동기/리액티브, 가벼운 제한 |
| 오버헤드 | 상대적으로 높음 | 낮음 |

### Kotlin/Spring Boot: Bulkhead 설정

```yaml
# application.yml
resilience4j:
  bulkhead:
    configs:
      default:
        maxConcurrentCalls: 25               # 최대 동시 호출 수
        maxWaitDuration: 0ms                 # 대기 없이 즉시 실패
    instances:
      payment-service:
        baseConfig: default
        maxConcurrentCalls: 10               # 결제는 보수적으로
      notification-service:
        maxConcurrentCalls: 50               # 알림은 여유있게

  thread-pool-bulkhead:
    configs:
      default:
        maxThreadPoolSize: 10
        coreThreadPoolSize: 5
        queueCapacity: 20
        keepAliveDuration: 100ms
    instances:
      heavy-computation:
        baseConfig: default
        maxThreadPoolSize: 4                 # 무거운 작업은 스레드 제한
```

```kotlin
import io.github.resilience4j.bulkhead.annotation.Bulkhead

@Service
class NotificationService(
    private val notificationClient: NotificationClient,
) {
    // Semaphore bulkhead — 동시 호출 50개 제한
    @Bulkhead(name = "notification-service")
    fun sendNotification(request: NotificationRequest): NotificationResponse {
        return notificationClient.send(request)
    }

    // Thread pool bulkhead — 독립 스레드 풀에서 실행
    @Bulkhead(name = "heavy-computation", type = Bulkhead.Type.THREADPOOL)
    fun generateReport(request: ReportRequest): CompletableFuture<ReportResponse> {
        return CompletableFuture.supplyAsync {
            // CPU 집약적인 리포트 생성
            reportGenerator.generate(request)
        }
    }
}
```

### Python: asyncio.Semaphore 적용

```python
import asyncio


class BulkheadClient:
    """다운스트림 서비스별 동시성 제한"""

    def __init__(
        self,
        client: httpx.AsyncClient,
        max_concurrent: int = 10,
    ):
        self._client = client
        self._semaphore = asyncio.Semaphore(max_concurrent)

    async def request(
        self,
        method: str,
        url: str,
        **kwargs,
    ) -> httpx.Response:
        """세마포어로 동시 요청 수 제한"""
        async with self._semaphore:
            return await self._client.request(method, url, **kwargs)


# 서비스별 독립 벌크헤드 생성
payment_bulkhead = BulkheadClient(payment_client, max_concurrent=10)
product_bulkhead = BulkheadClient(product_client, max_concurrent=30)
notification_bulkhead = BulkheadClient(notification_client, max_concurrent=50)
```

---

## 5. Spring WebClient 에러 처리

WebClient는 Spring WebFlux의 비동기 HTTP 클라이언트다.
리액티브 파이프라인에서 resilience 패턴을 자연스럽게 조합할 수 있다.

### WebClient 설정 Bean

```kotlin
import io.netty.channel.ChannelOption
import io.netty.handler.timeout.ReadTimeoutHandler
import io.netty.handler.timeout.WriteTimeoutHandler
import org.springframework.http.client.reactive.ReactorClientHttpConnector
import org.springframework.web.reactive.function.client.ExchangeFilterFunction
import org.springframework.web.reactive.function.client.WebClient
import reactor.netty.http.client.HttpClient
import reactor.netty.resources.ConnectionProvider
import java.time.Duration
import java.util.concurrent.TimeUnit

@Configuration
class WebClientConfig {

    @Bean
    fun paymentWebClient(): WebClient {
        // 커넥션 풀 설정
        val connectionProvider = ConnectionProvider.builder("payment-pool")
            .maxConnections(100)                         // 최대 커넥션 수
            .maxIdleTime(Duration.ofSeconds(20))         // 유휴 커넥션 TTL
            .maxLifeTime(Duration.ofSeconds(60))         // 커넥션 최대 수명
            .pendingAcquireTimeout(Duration.ofSeconds(5)) // 커넥션 획득 대기
            .evictInBackground(Duration.ofSeconds(30))   // 백그라운드 정리 주기
            .build()

        // Netty HttpClient 설정
        val httpClient = HttpClient.create(connectionProvider)
            .option(ChannelOption.CONNECT_TIMEOUT_MILLIS, 3000) // 연결 타임아웃
            .doOnConnected { conn ->
                conn.addHandlerLast(ReadTimeoutHandler(10, TimeUnit.SECONDS))
                conn.addHandlerLast(WriteTimeoutHandler(5, TimeUnit.SECONDS))
            }
            .responseTimeout(Duration.ofSeconds(10))     // 응답 타임아웃

        return WebClient.builder()
            .baseUrl("https://payment-api.internal")
            .clientConnector(ReactorClientHttpConnector(httpClient))
            .defaultHeader("Content-Type", "application/json")
            .filter(loggingFilter())                      // 로깅 필터
            .filter(metricsFilter())                      // 메트릭 필터
            .build()
    }

    // 요청/응답 로깅 필터
    private fun loggingFilter(): ExchangeFilterFunction {
        return ExchangeFilterFunction.ofRequestProcessor { request ->
            logger.info("WebClient 요청: ${request.method()} ${request.url()}")
            Mono.just(request)
        }
    }

    // 메트릭 수집 필터
    private fun metricsFilter(): ExchangeFilterFunction {
        return ExchangeFilterFunction.ofResponseProcessor { response ->
            logger.info("WebClient 응답: ${response.statusCode()}")
            Mono.just(response)
        }
    }
}
```

### 에러 핸들링 패턴

```kotlin
import org.springframework.web.reactive.function.client.WebClient
import reactor.core.publisher.Mono
import reactor.util.retry.Retry
import java.time.Duration

@Service
class PaymentWebClientService(
    private val paymentWebClient: WebClient,
) {
    fun requestPayment(request: PaymentRequest): Mono<PaymentResponse> {
        return paymentWebClient
            .post()
            .uri("/api/v1/payments")
            .bodyValue(request)
            .retrieve()
            // 상태별 에러 핸들링
            .onStatus({ it.is4xxClientError }) { response ->
                response.bodyToMono(ErrorResponse::class.java)
                    .flatMap { error ->
                        Mono.error(ClientException("클라이언트 오류: ${error.message}"))
                    }
            }
            .onStatus({ it.is5xxServerError }) { response ->
                Mono.error(ServerException("결제 서버 오류: ${response.statusCode()}"))
            }
            .bodyToMono(PaymentResponse::class.java)
            // 리액티브 재시도: 지수 백오프 + 5xx만 재시도
            .retryWhen(
                Retry.backoff(3, Duration.ofMillis(500))
                    .maxBackoff(Duration.ofSeconds(5))
                    .jitter(0.5)
                    .filter { it is ServerException }    // 서버 오류만 재시도
                    .onRetryExhaustedThrow { _, signal ->
                        // 모든 재시도 실패 시 마지막 예외 래핑
                        ServiceUnavailableException(
                            "결제 서비스 재시도 소진",
                            signal.failure(),
                        )
                    }
            )
            // 타임아웃
            .timeout(Duration.ofSeconds(15))
            // 최종 fallback
            .onErrorResume { ex ->
                logger.error("결제 요청 최종 실패: ${ex.message}", ex)
                Mono.just(PaymentResponse.failed(ex.message))
            }
    }
}
```

### retrieve() vs exchangeToMono() 비교

| 항목 | `retrieve()` | `exchangeToMono()` |
|------|-------------|---------------------|
| 사용 용이성 | 간단 — `onStatus()`로 에러 처리 | 복잡 — 직접 응답 객체 처리 |
| 메모리 관리 | 자동 (body 소비 안 하면 경고) | 수동 — 반드시 body를 소비해야 함 |
| 헤더 접근 | 불편 (별도 `toEntity()` 필요) | 자유로움 |
| 권장 | 대부분의 경우 | 응답 헤더/상태 기반 분기 필요 시 |

```kotlin
// Bad: exchangeToMono에서 body를 소비하지 않으면 메모리 누수
fun badExample(): Mono<String> {
    return webClient.get().uri("/api/data")
        .exchangeToMono { response ->
            if (response.statusCode().is2xxSuccessful) {
                response.bodyToMono(String::class.java)
            } else {
                Mono.error(RuntimeException("실패"))
                // body를 소비하지 않아 커넥션 누수 발생!
            }
        }
}

// Good: 모든 분기에서 body를 소비
fun goodExample(): Mono<String> {
    return webClient.get().uri("/api/data")
        .exchangeToMono { response ->
            if (response.statusCode().is2xxSuccessful) {
                response.bodyToMono(String::class.java)
            } else {
                response.bodyToMono(String::class.java)  // body 소비 후 에러
                    .flatMap { body ->
                        Mono.error(RuntimeException("실패: $body"))
                    }
            }
        }
}
```

---

## 6. httpx 클라이언트 패턴

httpx는 Python의 모던 HTTP 클라이언트로, async/sync 양쪽 모두 지원한다.
FastAPI 환경에서 다운스트림 호출 시 권장되는 클라이언트다.

### httpx.AsyncClient 생명주기 관리

```python
from contextlib import asynccontextmanager
import httpx
from fastapi import FastAPI, Depends


@asynccontextmanager
async def lifespan(app: FastAPI):
    """애플리케이션 생명주기에 맞춰 클라이언트 관리"""
    # 시작: 클라이언트 생성
    app.state.http_client = httpx.AsyncClient(
        base_url="https://api.internal",
        timeout=httpx.Timeout(
            connect=5.0,    # TCP 연결 타임아웃
            read=30.0,      # 응답 수신 타임아웃
            write=10.0,     # 요청 전송 타임아웃
            pool=10.0,      # 커넥션 풀 대기 타임아웃
        ),
        limits=httpx.Limits(
            max_connections=100,           # 전체 최대 커넥션
            max_keepalive_connections=20,  # Keep-alive 커넥션
            keepalive_expiry=30,           # Keep-alive 만료(초)
        ),
        headers={"User-Agent": "my-service/1.0"},
        event_hooks={
            "request": [log_request],
            "response": [log_response],
        },
    )
    yield
    # 종료: 클라이언트 정리
    await app.state.http_client.aclose()


app = FastAPI(lifespan=lifespan)


async def log_request(request: httpx.Request):
    """요청 이벤트 훅 — 로깅"""
    logger.info(f"요청: {request.method} {request.url}")


async def log_response(response: httpx.Response):
    """응답 이벤트 훅 — 로깅 및 메트릭"""
    request = response.request
    logger.info(
        f"응답: {request.method} {request.url} "
        f"status={response.status_code} "
        f"elapsed={response.elapsed.total_seconds():.3f}s"
    )
```

### httpx 의존성 주입 + tenacity 재시도

```python
from fastapi import Depends, Request
from tenacity import (
    retry,
    stop_after_attempt,
    wait_exponential_jitter,
    retry_if_exception_type,
)
import httpx


def get_http_client(request: Request) -> httpx.AsyncClient:
    """FastAPI 의존성: 앱 수준 httpx 클라이언트 반환"""
    return request.app.state.http_client


class ProductService:
    def __init__(self, client: httpx.AsyncClient):
        self._client = client

    @retry(
        stop=stop_after_attempt(3),
        wait=wait_exponential_jitter(initial=0.5, max=10, jitter=2),
        retry=retry_if_exception_type((
            httpx.ConnectTimeout,
            httpx.ReadTimeout,
            httpx.ConnectError,
        )),
    )
    async def get_product(self, product_id: int) -> dict:
        """재시도 적용된 상품 조회"""
        response = await self._client.get(f"/products/{product_id}")
        response.raise_for_status()
        return response.json()

    @retry(
        stop=stop_after_attempt(3),
        wait=wait_exponential_jitter(initial=1, max=15),
        retry=retry_if_exception_type((httpx.ConnectTimeout, httpx.ReadTimeout)),
    )
    async def search_products(self, query: str) -> list[dict]:
        """재시도 적용된 상품 검색"""
        response = await self._client.get(
            "/products/search",
            params={"q": query},
        )
        response.raise_for_status()
        return response.json()["items"]


# 라우터에서 사용
@router.get("/products/{product_id}")
async def get_product(
    product_id: int,
    client: httpx.AsyncClient = Depends(get_http_client),
):
    service = ProductService(client)
    return await service.get_product(product_id)
```

---

## 7. 조합 패턴

Resilience 패턴은 단독보다 조합하여 사용할 때 효과적이다.
적용 순서가 중요하며, 데코레이터 체인의 바깥쪽부터 평가된다.

### Resilience4j 데코레이터 적용 순서

```
요청 → CircuitBreaker → Retry → TimeLimiter → Bulkhead → 실제 호출
       (가장 바깥)                              (가장 안쪽)
```

- **CircuitBreaker**: 가장 바깥 — 전체 실패율 기반으로 요청 차단
- **Retry**: 그 안쪽 — 실패 시 재시도 (재시도 횟수만큼 CircuitBreaker에 기록)
- **TimeLimiter**: 그 안쪽 — 개별 호출 타임아웃 (타임아웃 → Retry → CircuitBreaker 실패 기록)
- **Bulkhead**: 가장 안쪽 — 동시 호출 수 제한

### Kotlin/Spring Boot: 복합 resilience 설정

```yaml
# application.yml — 복합 설정
resilience4j:
  circuitbreaker:
    instances:
      downstream-api:
        slidingWindowSize: 100
        failureRateThreshold: 50
        waitDurationInOpenState: 30s
        permittedNumberOfCallsInHalfOpenState: 10

  retry:
    instances:
      downstream-api:
        maxAttempts: 3
        waitDuration: 500ms
        enableExponentialBackoff: true
        exponentialBackoffMultiplier: 2

  timelimiter:
    instances:
      downstream-api:
        timeoutDuration: 5s

  bulkhead:
    instances:
      downstream-api:
        maxConcurrentCalls: 20
        maxWaitDuration: 0ms
```

```kotlin
@Service
class DownstreamService(
    private val downstreamClient: DownstreamClient,
    private val cacheService: CacheService,
) {
    // 패턴 조합: CircuitBreaker → Retry → TimeLimiter → Bulkhead
    // 어노테이션 순서가 아닌 Resilience4j 내부 우선순위에 따라 적용됨
    @CircuitBreaker(name = "downstream-api", fallbackMethod = "fallback")
    @Retry(name = "downstream-api")
    @TimeLimiter(name = "downstream-api")
    @Bulkhead(name = "downstream-api")
    fun fetchData(request: DataRequest): CompletableFuture<DataResponse> {
        return CompletableFuture.supplyAsync {
            downstreamClient.fetch(request)
        }
    }

    // fallback 체인: 캐시 → 기본값 → degraded response
    private fun fallback(
        request: DataRequest,
        ex: Throwable,
    ): CompletableFuture<DataResponse> {
        logger.warn("downstream-api 장애 — fallback 체인 시작: ${ex.message}")

        // 1단계: 캐시 응답 시도
        val cached = cacheService.get(request.cacheKey)
        if (cached != null) {
            logger.info("캐시 fallback 성공: ${request.cacheKey}")
            return CompletableFuture.completedFuture(cached)
        }

        // 2단계: 기본값(degraded response) 반환
        logger.warn("캐시 없음 — degraded response 반환")
        return CompletableFuture.completedFuture(
            DataResponse.degraded("서비스 일시 장애, 제한된 정보만 제공됩니다")
        )
    }
}
```

### 모니터링 메트릭 연동 (Micrometer)

```kotlin
// build.gradle.kts
dependencies {
    implementation("io.github.resilience4j:resilience4j-micrometer")
    implementation("io.micrometer:micrometer-registry-prometheus")
}
```

```yaml
# application.yml — Actuator 메트릭 노출
management:
  endpoints:
    web:
      exposure:
        include: health, prometheus, metrics
  metrics:
    tags:
      application: my-service
    distribution:
      percentiles-histogram:
        resilience4j.circuitbreaker.calls: true
```

주요 메트릭:

| 메트릭 | 설명 |
|--------|------|
| `resilience4j.circuitbreaker.state` | 서킷 브레이커 상태 (0=CLOSED, 1=OPEN, 2=HALF_OPEN) |
| `resilience4j.circuitbreaker.calls` | 호출 결과 (successful, failed, not_permitted) |
| `resilience4j.circuitbreaker.failure.rate` | 현재 실패율 |
| `resilience4j.retry.calls` | 재시도 결과 (successful_without_retry, successful_with_retry, failed_with/without_retry) |
| `resilience4j.bulkhead.available.concurrent.calls` | 벌크헤드 잔여 동시 호출 수 |
| `resilience4j.timelimiter.calls` | 타임리미터 결과 (successful, timeout, failed) |

### Python 조합 패턴: pybreaker + tenacity + asyncio

```python
import asyncio
import pybreaker
from tenacity import (
    retry,
    stop_after_attempt,
    wait_exponential_jitter,
    retry_if_exception_type,
)
import httpx
import logging

logger = logging.getLogger(__name__)

# 서킷 브레이커 인스턴스
downstream_breaker = pybreaker.CircuitBreaker(
    fail_max=5,
    reset_timeout=30,
    listeners=[pybreaker.LogListener(logger)],
)


class ResilientDownstreamService:
    """서킷 브레이커 + 재시도 + 타임아웃 + 벌크헤드를 조합한 서비스"""

    def __init__(
        self,
        client: httpx.AsyncClient,
        max_concurrent: int = 20,
        timeout_seconds: float = 5.0,
    ):
        self._client = client
        self._semaphore = asyncio.Semaphore(max_concurrent)  # 벌크헤드
        self._timeout = timeout_seconds

    @downstream_breaker                                       # 서킷 브레이커 (가장 바깥)
    @retry(                                                   # 재시도
        stop=stop_after_attempt(3),
        wait=wait_exponential_jitter(initial=0.5, max=10),
        retry=retry_if_exception_type((
            httpx.ConnectTimeout,
            httpx.ReadTimeout,
            httpx.ConnectError,
        )),
    )
    async def fetch_data(self, path: str) -> dict:
        """조합 패턴이 적용된 다운스트림 호출"""
        # 벌크헤드: 동시 호출 수 제한
        async with self._semaphore:
            # 타임아웃: 개별 호출 시간 제한
            response = await asyncio.wait_for(
                self._client.get(path),
                timeout=self._timeout,
            )
            response.raise_for_status()
            return response.json()

    async def fetch_data_with_fallback(
        self,
        path: str,
        cache: dict | None = None,
    ) -> dict:
        """fallback 체인 포함 호출"""
        try:
            return await self.fetch_data(path)
        except pybreaker.CircuitBreakerError:
            logger.warning(f"서킷 OPEN — fallback 반환: {path}")
        except Exception as ex:
            logger.error(f"모든 재시도 실패 — fallback 반환: {path}, {ex}")

        # fallback 체인: 캐시 → 기본값
        if cache is not None:
            return cache
        return {"status": "degraded", "message": "서비스 일시 장애"}
```
