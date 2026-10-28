# 팀 규칙 (회사 Kotlin/Go 백엔드 기준)

기존 스킬(async-event-patterns, caching-patterns, backend-testing-patterns)에서 추출한 팀 고유 규칙이다.
**프로젝트 CLAUDE.md / `.claude/rules` 가 다르게 정하면 프로젝트가 우선**한다. 개인 프로젝트에는 적용을 강제하지 않는다.

## 타임아웃 상한

증분 색인·배치·비동기 처리에서 레거시 API 동기 호출이 전체 TPS 를 끌어내리는 패턴이 반복되어 정한 상한이다.

| 호출 대상 | 상한 | 근거 |
|---|---|---|
| 레거시/서드파티 API (인덱싱 경로) | ≤ 500ms | 증분 색인 TPS 마지노선 |
| 동일 DC 내부 서비스 (REST/gRPC) | ≤ 1s | 정상 p95 의 3~5배 |
| DB 쿼리 (OLTP) | ≤ 500ms | 장시간 쿼리는 배치/리포트 경로로 분리 |
| 캐시 (Valkey) | ≤ 100ms | 캐시 실패는 빠르게 원천 폴백 |
| 메시지 브로커 publish | ≤ 1s | 동기 ack 기준 (KFK-PRD-02 의 `max.block.ms` 도 예산에 포함) |

연결 타임아웃과 응답 타임아웃을 **둘 다** 설정한다(DIST-TMO-02).

## Kafka 컨슈머 안의 외부 호출

- 레코드 리스너에서 레코드마다 동기 HTTP 를 호출하지 않는다 → 배치 리스너 + 레코드 간 병렬 + 호출별 타임아웃.
- 타임아웃된 보강 데이터는 `null` 로 두고 색인은 진행(부분 성공), 누락분은 재처리 큐로.
- 배치 처리 최악 시간이 `max.poll.interval.ms` 를 넘지 않는지 계산한다(KFK-CON-01).

```kotlin
@KafkaListener(topics = ["product.changed"], containerFactory = "batchFactory")
fun consumeBatch(events: List<ProductChangedEvent>) = runBlocking {
    val enriched = events.map { e ->
        async(Dispatchers.IO) {
            val legacy = withTimeoutOrNull(500.milliseconds) { legacyApi.fetchProduct(e.productId) }
            enrichWith(e, legacy)
        }
    }.awaitAll()
    indexService.bulkIndex(enriched)   // 반환 후 커밋 — 비동기 위임 금지(KFK-CON-04)
}
```

위 `runBlocking` 형태는 모든 Spring Kafka 버전에서 동작한다. **Spring Kafka 3.2+** 라면 리스너를 `suspend fun consumeBatch(...)` 로 선언해 리스너 스레드를 막지 않고도 완료 시점 ack 를 받을 수 있다(AckMode 자동 MANUAL — 결과 생성 전 예외 처리 주의, KFK-CON-04).

`withTimeoutOrNull` 은 취소 가능한 suspend 호출에서만 효과가 있다 — 블로킹 클라이언트라면 클라이언트 자체 타임아웃도 설정한다.

## 순차 IO·중첩 조회 금지

- 독립적인 IO 는 병렬로: Kotlin `coroutineScope { async {} }.awaitAll()`, Go `errgroup.Group`(+ `SetLimit`), Python `asyncio.gather`/`TaskGroup`. 동시성 상한을 둔다(하위 보호).
- 리스트 × 리스트 매칭은 한쪽을 먼저 `groupBy`/`associateBy`(Go `map`) 로 인덱싱해 O(N×M) → O(N+M).

## 캐시 키

| 규칙 | 예시 |
|---|---|
| `{서비스}:{엔티티}:{id}` | `product-service:product:42` |
| 목록·조회 조건 | `{서비스}:{엔티티}-list:{조건...}` |
| 스키마 변경 시 버전 접두사 교체(구 키는 TTL 로 자연 만료, 패턴 삭제 금지 — KEYS/SCAN 순회 회피, VK-KEY-01) | `product-service:product:v2:42` |
| Spring `@Cacheable` 캐시 이름도 같은 네임스페이스 | `@Cacheable("product-service:product-detail")` |

모든 키에 TTL(DIST-CACHE-02) + 지터(DIST-CACHE-01).

## TTL 출발값

| 데이터 | TTL | 무효화 |
|---|---|---|
| 상품 상세 | 1시간 | 변경 이벤트 |
| 상품 목록 | 5~10분 | 변경 이벤트 |
| 설정/코드 테이블 | 6~24시간 | 관리자 변경 시 |
| 검색 결과 | 3~5분 | TTL |
| 실시간 재고 | 30초~1분 | write-through |

출발값일 뿐이며, 적중률·stale 허용도를 측정해 조정한다.

## 테스트 격리

Testcontainers 로 Kafka/Valkey 를 공유하는 통합 테스트는 테스트 클래스(또는 케이스)별 고유 토픽·키 접두사를 쓴다.

```kotlin
val testTopic = "order.completed.${UUID.randomUUID().toString().take(8)}"
```

```python
@pytest.fixture
def cache_prefix() -> str:
    return f"test:{uuid.uuid4().hex[:8]}"
```
