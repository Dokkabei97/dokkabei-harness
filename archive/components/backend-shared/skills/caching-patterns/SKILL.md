---
name: caching-patterns
description: |
  캐싱 패턴 레퍼런스 — Spring Cache @Cacheable/CacheEvict, Valkey 패턴, FastAPI 캐싱, TTL 전략
  Reference for caching patterns — Spring Cache @Cacheable/CacheEvict, Valkey patterns, FastAPI caching, and TTL strategy. Use when: adding a cache layer, configuring @Cacheable/CacheEvict, caching FastAPI responses, choosing TTL and invalidation strategies.
---

# 캐싱 패턴 레퍼런스

## 1. Spring Cache Abstraction

### 어노테이션 요약

| 어노테이션 | 동작 | 사용 시기 |
|---|---|---|
| `@Cacheable` | 캐시 히트 시 메서드 실행 건너뜀, 미스 시 실행 후 저장 | 조회 메서드 |
| `@CacheEvict` | 캐시 항목 삭제 | 데이터 변경 시 무효화 |
| `@CachePut` | 항상 실행 후 결과를 캐시에 저장 | 업데이트 후 캐시 갱신 |
| `@Caching` | 여러 캐시 연산 조합 | 복합 무효화 |

```kotlin
@Service
class ProductService(private val productRepository: ProductRepository) {
    @Cacheable(cacheNames = ["products"], key = "#productId")
    fun getProduct(productId: Long): ProductResponse {
        val product = productRepository.findByIdOrNull(productId)
            ?: throw ProductNotFoundException(productId)
        return ProductResponse.from(product)
    }

    @CacheEvict(cacheNames = ["products"], key = "#productId")
    fun deleteProduct(productId: Long) = productRepository.deleteById(productId)

    @Caching(evict = [
        CacheEvict(cacheNames = ["products"], key = "#productId"),
        CacheEvict(cacheNames = ["product-list"], allEntries = true),
    ])
    fun removeProductCompletely(productId: Long) = productRepository.deleteById(productId)
}
```

### CacheManager 설정 (RedisCacheManager)

```kotlin
@Configuration
@EnableCaching
class CacheConfig(private val redisConnectionFactory: RedisConnectionFactory) {
    @Bean
    fun cacheManager(): RedisCacheManager {
        val defaultConfig = RedisCacheConfiguration.defaultCacheConfig()
            .entryTtl(Duration.ofMinutes(30))
            .serializeKeysWith(RedisSerializationContext.SerializationPair
                .fromSerializer(StringRedisSerializer()))
            .serializeValuesWith(RedisSerializationContext.SerializationPair
                .fromSerializer(GenericJackson2JsonRedisSerializer()))
            .disableCachingNullValues()

        val cacheConfigs = mapOf(
            "products" to defaultConfig.entryTtl(Duration.ofHours(1)),
            "product-list" to defaultConfig.entryTtl(Duration.ofMinutes(10)),
        )
        return RedisCacheManager.builder(redisConnectionFactory)
            .cacheDefaults(defaultConfig)
            .withInitialCacheConfigurations(cacheConfigs)
            .transactionAware()
            .build()
    }
}
```

### 키 생성 전략 (SpEL)

```kotlin
@Cacheable(cacheNames = ["products"], key = "#id")                           // 단일 파라미터
@Cacheable(cacheNames = ["products"], key = "#category + ':' + #page")       // 복합 키
@Cacheable(cacheNames = ["orders"], key = "#req.userId + ':' + #req.orderId")// 객체 필드
```

### 조건부 캐싱

```kotlin
// condition: 실행 전 판단 / unless: 실행 후 결과 기반 판단
@Cacheable(
    cacheNames = ["products"], key = "#productId",
    condition = "#productId > 0",
    unless = "#result == null || #result.soldOut",
)
fun getProduct(productId: Long): ProductResponse?
```

### 캐시 네임스페이스

```kotlin
// Bad: 모호한 이름
@Cacheable("cache1")

// Good: {서비스}:{엔티티} 형식
@Cacheable("product-service:product-detail")
```

---

## 2. Valkey (Redis) 연동 -- Kotlin/Spring Boot

### RedisTemplate 설정

```kotlin
@Configuration
class RedisConfig(
    @Value("\${spring.data.redis.host}") private val host: String,
    @Value("\${spring.data.redis.port}") private val port: Int,
) {
    @Bean
    fun lettuceConnectionFactory(): LettuceConnectionFactory {
        val poolConfig = GenericObjectPoolConfig<Any>().apply {
            maxTotal = 20; maxIdle = 10; minIdle = 5
            testOnBorrow = true; testWhileIdle = true
        }
        val clientConfig = LettucePoolingClientConfiguration.builder()
            .poolConfig(poolConfig).commandTimeout(Duration.ofMillis(500)).build()
        return LettuceConnectionFactory(RedisStandaloneConfiguration(host, port), clientConfig)
    }

    @Bean
    fun redisTemplate(cf: LettuceConnectionFactory): RedisTemplate<String, Any> {
        return RedisTemplate<String, Any>().apply {
            setConnectionFactory(cf)
            keySerializer = StringRedisSerializer()
            valueSerializer = GenericJackson2JsonRedisSerializer()
            hashKeySerializer = StringRedisSerializer()
            hashValueSerializer = GenericJackson2JsonRedisSerializer()
            afterPropertiesSet()
        }
    }
}
```

### Serializer 비교

| Serializer | 장점 | 단점 | 사용 시기 |
|---|---|---|---|
| `StringRedisSerializer` | 가독성, 디버깅 용이 | 문자열만 가능 | 키, 단순 값 |
| `Jackson2JsonRedisSerializer` | 타입 지정, 빠름 | 특정 클래스 바인딩 | 단일 타입 캐시 |
| `GenericJackson2JsonRedisSerializer` | 타입 정보 포함 | JSON 크기 증가 | 범용 값 저장 |

### RedisTemplate CRUD

```kotlin
@Repository
class ProductCacheRepository(private val redisTemplate: RedisTemplate<String, Any>) {
    private val ops get() = redisTemplate.opsForValue()
    private fun key(id: Long) = "product-service:product:$id"

    fun save(product: ProductCacheDto) {
        ops.set(key(product.id), product, Duration.ofHours(1))
    }
    fun findById(id: Long): ProductCacheDto? = ops.get(key(id)) as? ProductCacheDto
    fun delete(id: Long) = redisTemplate.delete(key(id))

    // 파이프라인: 다량 명령을 한 번에 전송
    fun saveAll(products: List<ProductCacheDto>) {
        redisTemplate.executePipelined { _ ->
            products.forEach { ops.set(key(it.id), it, Duration.ofHours(1)) }
            null
        }
    }
}
```

---

## 3. 캐싱 패턴

### Cache-Aside (Lazy Loading)

```kotlin
// 읽기: 캐시 확인 → 미스 시 DB 조회 → 캐시 저장
fun getProduct(productId: Long): ProductResponse {
    val cacheKey = "product:$productId"
    val cached = ops.get(cacheKey) as? ProductResponse
    if (cached != null) return cached

    val product = productRepository.findByIdOrNull(productId)
        ?: throw ProductNotFoundException(productId)
    val response = ProductResponse.from(product)
    ops.set(cacheKey, response, Duration.ofHours(1))
    return response
}

// 쓰기: DB 업데이트 → 캐시 삭제 (갱신이 아닌 삭제로 일관성 보장)
@Transactional
fun updateProduct(request: UpdateProductRequest): ProductResponse {
    val product = productRepository.findByIdOrNull(request.productId)
        ?: throw ProductNotFoundException(request.productId)
    product.update(request)
    redisTemplate.delete("product:${request.productId}")
    return ProductResponse.from(productRepository.save(product))
}
```

### Write-Through

```kotlin
// 쓰기: DB + 캐시 동시 업데이트 — 읽기 시 항상 캐시에 최신 데이터
@Transactional
fun updateProduct(request: UpdateProductRequest): ProductResponse {
    val product = productRepository.findByIdOrNull(request.productId)
        ?: throw ProductNotFoundException(request.productId)
    product.update(request)
    val response = ProductResponse.from(productRepository.save(product))
    ops.set("product:${product.id}", response, Duration.ofHours(1))
    return response
}
```

### Write-Behind (Write-Back)

```kotlin
// 캐시에 먼저 저장, DB 반영은 이벤트로 비동기 처리
fun updateProduct(request: UpdateProductRequest): ProductResponse {
    val response = ProductResponse(request.productId, request.name, request.price)
    ops.set("product:${request.productId}", response, Duration.ofHours(1))
    applicationEventPublisher.publishEvent(ProductUpdateEvent(request.productId, request))
    return response
}

@Async
@TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
fun handleProductUpdate(event: ProductUpdateEvent) {
    val product = productRepository.findByIdOrNull(event.productId) ?: return
    product.update(event.request)
    productRepository.save(product)
}
```

### 패턴 비교

| 패턴 | 읽기 성능 | 쓰기 성능 | 일관성 | 복잡도 | 적합한 경우 |
|---|---|---|---|---|---|
| Cache-Aside | 높음 | 보통 | 최종 일관성 | 낮음 | 읽기 비율이 높은 서비스 |
| Write-Through | 높음 | 보통 | 강한 일관성 | 중간 | 읽기/쓰기 빈도 비슷 |
| Write-Behind | 높음 | 매우 높음 | 약한 일관성 | 높음 | 쓰기 빈번, 즉시 일관성 불필요 |

### Cache Stampede 방지

**분산 락 (Redisson)**

```kotlin
fun getProduct(productId: Long): ProductResponse {
    val cacheKey = "product:$productId"
    ops.get(cacheKey)?.let { return it as ProductResponse }

    // 분산 락: 하나의 요청만 DB 접근
    val lock = redissonClient.getLock("lock:$cacheKey")
    if (!lock.tryLock(5, 10, TimeUnit.SECONDS)) {
        Thread.sleep(100)
        return ops.get(cacheKey) as? ProductResponse
            ?: throw CacheLoadException("캐시 로드 실패: $cacheKey")
    }
    try {
        // Double-check: 락 대기 중 다른 스레드가 캐시를 채웠을 수 있음
        ops.get(cacheKey)?.let { return it as ProductResponse }
        val response = ProductResponse.from(
            productRepository.findByIdOrNull(productId) ?: throw ProductNotFoundException(productId)
        )
        ops.set(cacheKey, response, Duration.ofHours(1))
        return response
    } finally {
        if (lock.isHeldByCurrentThread) lock.unlock()
    }
}
```

**확률적 조기 만료 (PER)**

```kotlin
// TTL 임박 시 확률적으로 캐시 갱신하여 stampede 방지
val ttl = redisTemplate.getExpire(cacheKey, TimeUnit.SECONDS)
val threshold = 300L  // 5분
if (ttl in 1 until threshold) {
    val probability = beta * ln(random.nextDouble()) * -1
    if (probability > ttl.toDouble() / threshold) refreshCache(productId, cacheKey)
}
```

---

## 4. FastAPI 캐싱

### redis.asyncio 클라이언트 설정

```python
import redis.asyncio as aioredis
from contextlib import asynccontextmanager
from fastapi import Depends, FastAPI

redis_client: aioredis.Redis | None = None

@asynccontextmanager
async def lifespan(app: FastAPI):
    global redis_client
    redis_client = aioredis.Redis(
        host="localhost", port=6379, decode_responses=True,
        max_connections=20, socket_timeout=1.0,
    )
    await redis_client.ping()
    yield
    await redis_client.close()

app = FastAPI(lifespan=lifespan)

async def get_redis() -> aioredis.Redis:
    if redis_client is None:
        raise RuntimeError("Redis 클라이언트가 초기화되지 않음")
    return redis_client
```

### 수동 캐싱 패턴 (DI 기반)

```python
import json
from typing import Any
import redis.asyncio as aioredis

class CacheService:
    def __init__(self, redis: aioredis.Redis):
        self.redis = redis

    async def get(self, key: str) -> Any | None:
        data = await self.redis.get(key)
        return json.loads(data) if data else None

    async def set(self, key: str, value: Any, ttl: int = 3600) -> None:
        await self.redis.set(key, json.dumps(value, default=str), ex=ttl)

    async def delete_pattern(self, pattern: str) -> None:
        """SCAN 기반 일괄 삭제 (KEYS 대신)"""
        cursor = 0
        while True:
            cursor, keys = await self.redis.scan(cursor, match=pattern, count=100)
            if keys:
                await self.redis.delete(*keys)
            if cursor == 0:
                break

@router.get("/{product_id}")
async def get_product(
    product_id: int,
    cache: CacheService = Depends(get_cache_service),
    db: AsyncSession = Depends(get_db),
):
    cache_key = f"product-service:product:{product_id}"
    cached = await cache.get(cache_key)
    if cached is not None:
        return cached

    product = await product_repository.find_by_id(db, product_id)
    if not product:
        raise HTTPException(status_code=404, detail="상품을 찾을 수 없습니다")

    response = ProductResponse.from_entity(product).model_dump()
    await cache.set(cache_key, response, ttl=3600)
    return response
```

### fastapi-cache2 데코레이터

```python
from fastapi_cache.decorator import cache

@router.get("/{product_id}")
@cache(expire=3600, namespace="product")
async def get_product(product_id: int, db: AsyncSession = Depends(get_db)):
    """@cache: 자동 캐시 키 생성 및 TTL 관리"""
    product = await product_repository.find_by_id(db, product_id)
    if not product:
        raise HTTPException(status_code=404)
    return ProductResponse.from_entity(product)
```

### 캐시 키 컨벤션

| 패턴 | 예시 |
|---|---|
| `{서비스}:{엔티티}:{id}` | `product-service:product:42` |
| `{서비스}:{엔티티}:{작업}:{파라미터}` | `product-service:product-list:electronics:1` |

---

## 5. TTL 전략 & 무효화

### 시간 기반 만료

| 전략 | 설명 | 적합한 경우 |
|---|---|---|
| Fixed TTL | 고정 시간 후 만료 | 변경 빈도 예측 가능 |
| Sliding TTL | 접근 시 TTL 리셋 | 핫 데이터 유지 |
| Adaptive TTL | 변경 빈도 따라 동적 조절 | 불규칙한 변경 주기 |

```kotlin
// Fixed TTL
ops.set("product:$id", product, Duration.ofHours(1))

// Sliding TTL: 접근 시 리셋
fun getWithSlidingTtl(key: String, ttl: Duration): Any? {
    val value = ops.get(key)
    if (value != null) redisTemplate.expire(key, ttl)
    return value
}

// Adaptive TTL: 변경 빈도 기반
fun adaptiveTtl(entityId: Long, baseMin: Long = 60): Duration {
    val changes = changeLogRepository.countRecent(entityId, 24)
    val multiplier = when {
        changes > 10 -> 0.1; changes > 5 -> 0.3; changes > 1 -> 0.5; else -> 1.0
    }
    return Duration.ofMinutes((baseMin * multiplier).toLong())
}
```

### 태그 기반 무효화

```kotlin
// 태그 세트로 관련 캐시 그룹 관리
fun putWithTags(key: String, value: Any, ttl: Duration, vararg tags: String) {
    ops.set(key, value, ttl)
    tags.forEach { setOps.add("cache-tag:$it", key) }
}

fun evictByTag(tag: String) {
    val keys = setOps.members("cache-tag:$tag") ?: emptySet()
    if (keys.isNotEmpty()) redisTemplate.delete(keys)
    redisTemplate.delete("cache-tag:$tag")
}
```

### 캐시 워밍

```kotlin
@EventListener(ApplicationReadyEvent::class)
fun warmUpCache() {
    val hotProducts = productRepository.findTopViewedProducts(
        since = LocalDateTime.now().minusDays(7), limit = 100,
    )
    redisTemplate.executePipelined { _ ->
        hotProducts.forEach { ops.set("product:${it.id}", ProductResponse.from(it), Duration.ofHours(1)) }
        null
    }
}
```

### 캐시 버전닝

```kotlin
// 스키마 변경 시 키 프리픽스에 버전 포함 — 기존 캐시 자연 만료
object CacheKeyVersion { const val PRODUCT = "v2"; const val ORDER = "v1" }
fun productCacheKey(id: Long) = "product:${CacheKeyVersion.PRODUCT}:$id"
```

### TTL 권장 가이드

| 데이터 유형 | 권장 TTL | 무효화 방식 |
|---|---|---|
| 상품 상세 | 1시간 | 이벤트 기반 |
| 상품 목록 | 5~10분 | 이벤트 기반 |
| 사용자 세션 | 24시간 | 로그아웃 시 삭제 |
| 설정/코드 테이블 | 6~24시간 | 관리자 변경 시 |
| 검색 결과 | 3~5분 | TTL 만료 |
| 실시간 재고 | 30초~1분 | Write-Through |

---

## 6. 직렬화 & 호환성

### 포맷 비교

| 포맷 | 크기 | 속도 | 스키마 | 가독성 |
|---|---|---|---|---|
| JSON | 1.0x (기준) | 보통 | 없음 | 우수 |
| MessagePack | 0.6~0.7x | 빠름 | 없음 | 바이너리 |
| Protobuf | 0.3~0.5x | 매우 빠름 | .proto 필수 | 바이너리 |

### Jackson Polymorphic Type Handling (Spring)

```kotlin
// Bad: GenericJackson2JsonRedisSerializer — 클래스명 변경 시 역직렬화 실패
// {"@class":"com.example.ProductResponse", ...}

// Good: 타입 명시 직렬화로 안정성 확보
@Bean
fun productRedisTemplate(cf: LettuceConnectionFactory): RedisTemplate<String, ProductResponse> {
    return RedisTemplate<String, ProductResponse>().apply {
        setConnectionFactory(cf)
        keySerializer = StringRedisSerializer()
        valueSerializer = Jackson2JsonRedisSerializer(ProductResponse::class.java)
        afterPropertiesSet()
    }
}
```

### Pydantic Model Serialization (Python)

```python
# Good: model_dump_json() — Pydantic이 직렬화 보장
cached = product.model_dump_json()

# 캐시 조회 시 역직렬화
product = ProductResponse.model_validate_json(data)
```

### 스키마 진화 시 하위 호환성

```kotlin
// 필드 추가: 기본값 지정 → V1 캐시 역직렬화 안전
data class ProductResponseV2(
    val id: Long, val name: String, val price: BigDecimal,
    val discountRate: Double = 0.0,       // 새 필드
    val tags: List<String> = emptyList(), // 새 필드
)

// 필드 제거: ignoreUnknown으로 무시
@JsonIgnoreProperties(ignoreUnknown = true)
data class ProductResponseV3(val id: Long, val name: String, val price: BigDecimal)
```

```python
class ProductResponseV2(BaseModel):
    id: int; name: str; price: int
    discount_rate: float = 0.0
    tags: list[str] = Field(default_factory=list)
    class Config:
        extra = "ignore"  # 알 수 없는 필드 무시
```

### 대용량 값 압축

| 알고리즘 | 압축률 | 속도 | 적합한 경우 |
|---|---|---|---|
| Snappy | 보통 (2~4x) | 매우 빠름 | 대부분의 캐시 (속도 우선) |
| LZ4 | 보통 (2~4x) | 매우 빠름 | Snappy 유사, 약간 높은 압축률 |
| Gzip | 높음 (5~10x) | 느림 | 네트워크 전송 (크기 우선) |
| Zstd | 높음 (5~10x) | 빠름 | 큰 데이터, 높은 압축률 + 적절한 속도 |
