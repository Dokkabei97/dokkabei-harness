---
name: search-observability
description: Use this skill when implementing search metrics collection, click-through tracking, A/B testing for search, search quality monitoring, or slow query analysis. Covers Micrometer metrics, search session analysis, and dashboard design for Kotlin/Spring Boot search services.
---

# Search Observability

검색 서비스의 관찰 가능성 구축 가이드입니다. 메트릭 수집, CTR 추적, A/B 테스트, 품질 모니터링 대시보드, 슬로우 쿼리 분석을 다룹니다.

## When to Activate

- 검색 메트릭 수집 (latency, zero-result rate, CTR) 구현 시
- 검색 A/B 테스트 프레임워크 설계 시
- 검색 품질 모니터링 대시보드 구축 시
- ES slow query 분석 및 최적화 시
- 검색 세션 분석 (reformulation rate, session success) 설계 시
- Micrometer 기반 커스텀 메트릭 구현 시

## 1. Search Metrics Collection

### Core Metrics Taxonomy

| Metric Name | Type | 설명 | Tags |
|-------------|------|------|------|
| `search.latency` | Timer | 검색 요청 응답 시간 | `query_type`, `index`, `status` |
| `search.throughput` | Counter | 검색 요청 총 수 | `query_type`, `index` |
| `search.zero_results` | Counter | 결과 0건 반환 횟수 | `query_type`, `index` |
| `search.result_count` | DistributionSummary | 검색 결과 건수 분포 | `query_type`, `index` |
| `search.click_through` | Counter | 검색 결과 클릭 수 | `query_type`, `position_bucket` |
| `search.session_success` | Counter | 검색 세션 성공 (전환) 수 | `query_type` |
| `search.circuit_breaker.open` | Gauge | 서킷 브레이커 열림 상태 | `index` |
| `search.error` | Counter | 검색 오류 발생 수 | `error_type`, `index` |

### SearchMetrics Component

```kotlin
@Component
class SearchMetrics(
    private val meterRegistry: MeterRegistry
) {
    // --- Timers ---
    private fun latencyTimer(queryType: String, index: String): Timer =
        Timer.builder("search.latency")
            .description("Search request latency")
            .tags("query_type", queryType, "index", index)
            .publishPercentiles(0.5, 0.95, 0.99)
            .publishPercentileHistogram()
            .minimumExpectedValue(Duration.ofMillis(1))
            .maximumExpectedValue(Duration.ofSeconds(10))
            .register(meterRegistry)

    // --- Counters ---
    private fun throughputCounter(queryType: String, index: String): Counter =
        Counter.builder("search.throughput")
            .description("Total search requests")
            .tags("query_type", queryType, "index", index)
            .register(meterRegistry)

    private fun zeroResultCounter(queryType: String, index: String): Counter =
        Counter.builder("search.zero_results")
            .description("Searches returning zero results")
            .tags("query_type", queryType, "index", index)
            .register(meterRegistry)

    private fun errorCounter(errorType: String, index: String): Counter =
        Counter.builder("search.error")
            .description("Search errors")
            .tags("error_type", errorType, "index", index)
            .register(meterRegistry)

    // --- Distribution Summary ---
    private fun resultCountSummary(queryType: String, index: String): DistributionSummary =
        DistributionSummary.builder("search.result_count")
            .description("Distribution of search result counts")
            .tags("query_type", queryType, "index", index)
            .publishPercentiles(0.5, 0.95)
            .register(meterRegistry)

    // --- Recording ---
    fun <T> recordSearch(
        queryType: String,
        index: String,
        block: () -> SearchResult<T>
    ): SearchResult<T> {
        val timer = latencyTimer(queryType, index)
        val sample = Timer.start(meterRegistry)

        return try {
            val result = block()

            sample.stop(timer)
            throughputCounter(queryType, index).increment()
            resultCountSummary(queryType, index).record(result.totalHits.toDouble())

            if (result.totalHits == 0L) {
                zeroResultCounter(queryType, index).increment()
            }

            result
        } catch (e: Exception) {
            sample.stop(timer)
            errorCounter(e.javaClass.simpleName, index).increment()
            throw e
        }
    }
}

data class SearchResult<T>(
    val items: List<T>,
    val totalHits: Long,
    val tookMs: Long
)
```

### 사용 예시

```kotlin
@Service
class ProductSearchService(
    private val client: ElasticsearchClient,
    private val searchMetrics: SearchMetrics
) {
    fun search(keyword: String, category: String?): SearchResult<Product> {
        return searchMetrics.recordSearch(
            queryType = if (category != null) "filtered" else "keyword",
            index = "products"
        ) {
            val response = client.search({ s ->
                s.index("products")
                    .query { q ->
                        q.bool { b ->
                            b.must { m -> m.match { mt -> mt.field("title").query(keyword) } }
                            category?.let { cat ->
                                b.filter { f -> f.term { t -> t.field("category").value(cat) } }
                            }
                            b
                        }
                    }
                    .size(20)
            }, Product::class.java)

            SearchResult(
                items = response.hits().hits().mapNotNull { it.source() },
                totalHits = response.hits().total()?.value() ?: 0,
                tookMs = response.took()
            )
        }
    }
}
```

## 2. Click-Through Rate Tracking

### Event Data Classes

```kotlin
data class SearchImpressionEvent(
    val sessionId: String,
    val queryId: String,
    val query: String,
    val queryType: String,
    val resultIds: List<String>,
    val totalHits: Long,
    val experimentGroup: String = "control",
    val timestamp: Instant = Instant.now()
)

data class SearchClickEvent(
    val sessionId: String,
    val queryId: String,
    val query: String,
    val clickedDocId: String,
    val position: Int,
    val experimentGroup: String = "control",
    val timestamp: Instant = Instant.now()
) {
    val positionBucket: String
        get() = when {
            position <= 3 -> "top3"
            position <= 10 -> "top10"
            else -> "below10"
        }
}
```

### SearchClickTracker Service

```kotlin
@Service
class SearchClickTracker(
    private val kafkaPublisher: KafkaEventPublisher,
    private val meterRegistry: MeterRegistry
) {
    private val impressionCounter = Counter.builder("search.impressions")
        .description("Total search impressions")
        .register(meterRegistry)

    private val clickCounter = Counter.builder("search.clicks")
        .description("Total search result clicks")
        .register(meterRegistry)

    private fun positionClickCounter(bucket: String): Counter =
        Counter.builder("search.clicks.by_position")
            .description("Clicks by position bucket")
            .tag("position_bucket", bucket)
            .register(meterRegistry)

    fun recordImpression(event: SearchImpressionEvent) {
        impressionCounter.increment()

        kafkaPublisher.publish(
            topic = "search-impressions",
            key = event.queryId,
            value = event
        )
    }

    fun recordClick(event: SearchClickEvent) {
        clickCounter.increment()
        positionClickCounter(event.positionBucket).increment()

        kafkaPublisher.publish(
            topic = "search-clicks",
            key = event.queryId,
            value = event
        )
    }
}
```

### Position-Aware CTR 계산

Position bias를 고려한 CTR 분석:

```
Position Bucket | 기대 CTR 범위 | 해석
----------------|---------------|------
top3            | 25-40%        | 핵심 지표, relevance 직결
top10           | 10-20%        | 첫 페이지 품질 반영
below10         | 1-5%          | 롱테일 또는 탐색 행동
```

### CTR Aggregation Query (Elasticsearch)

```json
// Impression & Click 이벤트를 조인하여 CTR 계산
// click 이벤트를 search-clicks 인덱스에 적재한 뒤 집계
GET /search-impressions/_search
{
  "size": 0,
  "query": {
    "range": { "timestamp": { "gte": "now-24h" } }
  },
  "aggs": {
    "by_query": {
      "terms": { "field": "query.keyword", "size": 100, "order": { "_count": "desc" } },
      "aggs": {
        "impression_count": { "value_count": { "field": "queryId.keyword" } }
      }
    }
  }
}

// 별도 click 인덱스에서 동일 기간 클릭 수 집계
GET /search-clicks/_search
{
  "size": 0,
  "query": {
    "range": { "timestamp": { "gte": "now-24h" } }
  },
  "aggs": {
    "by_query": {
      "terms": { "field": "query.keyword", "size": 100, "order": { "_count": "desc" } },
      "aggs": {
        "click_count": { "value_count": { "field": "queryId.keyword" } },
        "by_position": {
          "terms": { "field": "positionBucket.keyword" }
        }
      }
    }
  }
}

// CTR = click_count / impression_count (GROUP BY query)
```

## 3. Search Session Analysis

### 핵심 세션 지표 정의

| Metric | 정의 | 계산 |
|--------|------|------|
| **Session Success Rate** | 검색 후 목표 행동(구매/클릭) 달성 비율 | `sessions_with_conversion / total_search_sessions` |
| **Reformulation Rate** | 같은 세션에서 검색어를 수정한 비율 | `sessions_with_query_change / total_search_sessions` |
| **Abandonment Rate** | 검색 결과를 보고 이탈한 비율 | `sessions_without_click / total_search_sessions` |
| **Queries Per Session** | 세션당 평균 검색 횟수 | `total_queries / total_sessions` |
| **Time to First Click** | 검색 결과 노출 후 첫 클릭까지 시간 | `click_timestamp - impression_timestamp` (median) |

### Session Health Indicators

| Indicator | Healthy | Warning | Critical |
|-----------|---------|---------|----------|
| **Zero-Result Rate** | < 5% | 5 - 10% | > 10% |
| **Reformulation Rate** | < 20% | 20 - 35% | > 35% |
| **CTR@3** (상위 3개 클릭률) | > 30% | 15 - 30% | < 15% |
| **Session Success Rate** | > 15% | 5 - 15% | < 5% |
| **Abandonment Rate** | < 30% | 30 - 50% | > 50% |
| **p99 Latency** | < 500ms | 500ms - 1s | > 1s |
| **Queries Per Session** | 1.0 - 1.5 | 1.5 - 2.5 | > 2.5 |

### Session Tracker Implementation

```kotlin
@Service
class SearchSessionTracker(
    private val redisTemplate: ReactiveStringRedisTemplate,
    private val meterRegistry: MeterRegistry
) {
    companion object {
        private const val SESSION_TTL_MINUTES = 30L
        private const val SESSION_PREFIX = "search:session:"
    }

    private val reformulationCounter = Counter.builder("search.session.reformulation")
        .description("Search query reformulations within a session")
        .register(meterRegistry)

    private val abandonmentCounter = Counter.builder("search.session.abandonment")
        .description("Search sessions without any click")
        .register(meterRegistry)

    private val successCounter = Counter.builder("search.session.success")
        .description("Search sessions with conversion")
        .register(meterRegistry)

    suspend fun trackQuery(sessionId: String, query: String) {
        val key = "$SESSION_PREFIX$sessionId"
        val previousQuery = redisTemplate.opsForHash<String, String>()
            .get(key, "last_query").awaitFirstOrNull()

        if (previousQuery != null && previousQuery != query) {
            reformulationCounter.increment()
        }

        redisTemplate.opsForHash<String, String>().putAll(key, mapOf(
            "last_query" to query,
            "query_count" to ((redisTemplate.opsForHash<String, String>()
                .get(key, "query_count").awaitFirstOrNull()?.toInt() ?: 0) + 1).toString(),
            "has_click" to "false",
            "updated_at" to Instant.now().toString()
        )).awaitFirst()

        redisTemplate.expire(key, Duration.ofMinutes(SESSION_TTL_MINUTES)).awaitFirst()
    }

    suspend fun trackClick(sessionId: String) {
        val key = "$SESSION_PREFIX$sessionId"
        redisTemplate.opsForHash<String, String>()
            .put(key, "has_click", "true").awaitFirst()
    }

    suspend fun trackConversion(sessionId: String) {
        val key = "$SESSION_PREFIX$sessionId"
        redisTemplate.opsForHash<String, String>()
            .put(key, "converted", "true").awaitFirst()
        successCounter.increment()
    }

    // 세션 만료 시 abandonment 판정 (scheduled job)
    fun evaluateExpiredSession(sessionData: Map<String, String>) {
        val hasClick = sessionData["has_click"]?.toBoolean() ?: false
        if (!hasClick) {
            abandonmentCounter.increment()
        }
    }
}
```

## 4. A/B Testing Framework

### Architecture

```
User Request
    │
    ▼
┌─────────────────────┐
│  ExperimentService   │  consistent hashing on user_id
│  (bucket assignment) │  → deterministic group allocation
└─────────┬───────────┘
          │
    ┌─────┴─────┐
    ▼           ▼
 Control    Variant(s)
 (기존)     (변경안)
    │           │
    ▼           ▼
┌─────────────────────┐
│    Metrics tagged    │  experiment_group=control|variant_a|variant_b
│    by experiment     │
└─────────┬───────────┘
          │
          ▼
┌─────────────────────┐
│  Statistical Test    │  chi-squared, Mann-Whitney U
│  (significance)      │
└─────────────────────┘
```

### ExperimentService Implementation

```kotlin
@Service
class SearchExperimentService(
    private val experimentConfigRepository: ExperimentConfigRepository,
    private val meterRegistry: MeterRegistry
) {
    companion object {
        private val HASH_FUNCTION = Hashing.murmur3_128()
        private const val TOTAL_BUCKETS = 10000
    }

    data class ExperimentVariant(
        val experimentId: String,
        val variantName: String,       // "control", "variant_a", "variant_b"
        val trafficPercentage: Int,    // 0-100
        val config: Map<String, Any>   // variant-specific 설정
    )

    data class ExperimentConfig(
        val experimentId: String,
        val name: String,
        val enabled: Boolean,
        val variants: List<ExperimentVariant>,
        val startDate: Instant,
        val endDate: Instant?
    )

    fun assignVariant(userId: String, experimentId: String): ExperimentVariant {
        val config = experimentConfigRepository.findById(experimentId)
            ?: return defaultControlVariant(experimentId)

        if (!config.enabled || Instant.now().isBefore(config.startDate)) {
            return defaultControlVariant(experimentId)
        }
        if (config.endDate != null && Instant.now().isAfter(config.endDate)) {
            return defaultControlVariant(experimentId)
        }

        // Consistent hashing: user_id + experiment_id → bucket
        val hashInput = "$userId:$experimentId"
        val hashCode = HASH_FUNCTION.hashString(hashInput, Charsets.UTF_8)
        val bucket = (hashCode.asInt().absoluteValue % TOTAL_BUCKETS)

        // Bucket → variant 매핑
        var cumulativeBucket = 0
        for (variant in config.variants) {
            cumulativeBucket += (variant.trafficPercentage * TOTAL_BUCKETS / 100)
            if (bucket < cumulativeBucket) {
                recordAssignment(experimentId, variant.variantName)
                return variant
            }
        }

        return defaultControlVariant(experimentId)
    }

    private fun recordAssignment(experimentId: String, variantName: String) {
        Counter.builder("search.experiment.assignment")
            .tags("experiment_id", experimentId, "variant", variantName)
            .register(meterRegistry)
            .increment()
    }

    private fun defaultControlVariant(experimentId: String) = ExperimentVariant(
        experimentId = experimentId,
        variantName = "control",
        trafficPercentage = 100,
        config = emptyMap()
    )
}
```

### Metrics Tagged by Experiment Group

```kotlin
// 검색 실행 시 experiment group 태그 추가
fun <T> recordSearchWithExperiment(
    queryType: String,
    index: String,
    experimentGroup: String,
    block: () -> SearchResult<T>
): SearchResult<T> {
    val timer = Timer.builder("search.latency")
        .tags(
            "query_type", queryType,
            "index", index,
            "experiment_group", experimentGroup
        )
        .publishPercentiles(0.5, 0.95, 0.99)
        .register(meterRegistry)

    val sample = Timer.start(meterRegistry)
    val result = block()
    sample.stop(timer)

    Counter.builder("search.throughput")
        .tags("query_type", queryType, "experiment_group", experimentGroup)
        .register(meterRegistry)
        .increment()

    return result
}
```

### Experiment Design Template

실험 설계 시 아래 항목을 반드시 정의:

```
┌─────────────────────────────────────────────────────┐
│              Experiment Design Document              │
├──────────────────┬──────────────────────────────────┤
│ Experiment ID    │ exp_reranking_v2_2024q1          │
│ Hypothesis       │ BM25 + personalization reranking │
│                  │ 이 CTR@3을 5%p 이상 향상시킨다     │
├──────────────────┼──────────────────────────────────┤
│ Control          │ 기존 BM25 scoring만 사용          │
│ Variant A        │ BM25 + click popularity rerank   │
│ Variant B        │ BM25 + user preference rerank    │
├──────────────────┼──────────────────────────────────┤
│ Traffic Split    │ control 40% / A 30% / B 30%      │
│ Duration         │ 2주 (최소 1주 학습 + 1주 평가)     │
├──────────────────┼──────────────────────────────────┤
│ Primary Metric   │ CTR@3                            │
│ Secondary Metric │ Session Success Rate, MRR         │
│ Guardrail Metric │ p99 latency < 500ms              │
│                  │ zero-result rate 변화 < 1%p       │
│                  │ error rate 변화 < 0.1%p           │
├──────────────────┼──────────────────────────────────┤
│ MDE              │ 5%p (Minimum Detectable Effect)   │
│ Significance     │ alpha = 0.05, power = 0.80       │
│ Sample Size      │ ~12,000 sessions per variant     │
│                  │ (계산: power analysis 기반)        │
└──────────────────┴──────────────────────────────────┘
```

**Guardrail Metric 규칙**: Primary metric이 개선되더라도 guardrail metric이 악화되면 실험 실패로 판정. latency 증가, error rate 증가, zero-result 악화 등은 반드시 모니터링.

## 5. Slow Query Analysis

### Common Slow Query Root Causes

| 패턴 | 증상 | Root Cause | Solution |
|------|------|-----------|----------|
| 항상 느린 쿼리 | 특정 쿼리가 일관되게 > 500ms | 비효율적 쿼리 구조 (wildcard leading, nested 과다) | 쿼리 리라이트, 인덱스 구조 변경 |
| 간헐적 느린 쿼리 | 같은 쿼리가 때때로만 느림 | GC pause, hot shard, 리소스 경합 | JVM 튜닝, shard rebalancing |
| 데이터 증가 후 느려짐 | 인덱스 크기 증가와 함께 점진적 악화 | shard 크기 과대 (> 50GB) | shard 분할, ILM rollover 설정 |
| Aggregation 느림 | 집계 쿼리만 느림 | high cardinality field 집계 | `execution_hint: map`, 별도 집계 인덱스 |
| Fetch phase 느림 | 검색은 빠르나 결과 반환 느림 | `_source` 크기 과대, stored fields 과다 | `_source` 필터링, `source_excludes` |
| 정렬 느림 | sort 포함 시 느림 | fielddata 미사용, doc_values 비활성 | `doc_values: true` 확인, 정렬 필드 최적화 |
| 스크롤 타임아웃 | scroll 요청 실패 | scroll context 너무 많음, 메모리 부족 | `search_after`로 전환, `max_open_scroll_context` 조정 |

### SearchSlowQueryAspect (AOP)

```kotlin
@Aspect
@Component
class SearchSlowQueryAspect(
    private val meterRegistry: MeterRegistry
) {
    companion object {
        private val logger = LoggerFactory.getLogger(SearchSlowQueryAspect::class.java)
        private const val SLOW_THRESHOLD_MS = 200L
        private const val VERY_SLOW_THRESHOLD_MS = 1000L
    }

    private val slowQueryCounter = Counter.builder("search.slow_query")
        .description("Slow search queries (> ${SLOW_THRESHOLD_MS}ms)")
        .register(meterRegistry)

    private val verySlowQueryCounter = Counter.builder("search.very_slow_query")
        .description("Very slow search queries (> ${VERY_SLOW_THRESHOLD_MS}ms)")
        .register(meterRegistry)

    @Around("@annotation(SearchOperation)")
    fun detectSlowQuery(joinPoint: ProceedingJoinPoint): Any? {
        val startTime = System.currentTimeMillis()
        val result = joinPoint.proceed()
        val elapsed = System.currentTimeMillis() - startTime

        if (elapsed > VERY_SLOW_THRESHOLD_MS) {
            verySlowQueryCounter.increment()
            logger.error(
                "[VERY_SLOW_QUERY] method={}, elapsed={}ms, args={}",
                joinPoint.signature.toShortString(),
                elapsed,
                joinPoint.args.contentToString()
            )
        } else if (elapsed > SLOW_THRESHOLD_MS) {
            slowQueryCounter.increment()
            logger.warn(
                "[SLOW_QUERY] method={}, elapsed={}ms, args={}",
                joinPoint.signature.toShortString(),
                elapsed,
                joinPoint.args.contentToString()
            )
        }

        return result
    }
}

// 마커 어노테이션
@Target(AnnotationTarget.FUNCTION)
@Retention(AnnotationRetention.RUNTIME)
annotation class SearchOperation
```

### ES Slow Log 설정

```json
// 인덱스 레벨 slow log 설정
PUT /products/_settings
{
  "index.search.slowlog.threshold.query.warn": "1s",
  "index.search.slowlog.threshold.query.info": "500ms",
  "index.search.slowlog.threshold.query.debug": "200ms",
  "index.search.slowlog.threshold.fetch.warn": "500ms",
  "index.search.slowlog.threshold.fetch.info": "200ms",
  "index.search.slowlog.level": "info",
  "index.search.slowlog.source": "1000"
}
```

### Slow Query 분석 워크플로우

```
1. 탐지: slow_query counter 알림 또는 ES slow log
    │
    ▼
2. 쿼리 식별: _tasks API 또는 slow log에서 원인 쿼리 추출
    │
    ▼
3. 프로파일링: _search + "profile": true 로 phase별 시간 확인
    │    ├── Query phase: scoring, filtering
    │    ├── Collect phase: aggregation
    │    └── Fetch phase: _source 로딩
    │
    ▼
4. 원인 분석: 위 Root Causes 테이블 대조
    │
    ▼
5. 해결: 쿼리 리라이트 / 인덱스 변경 / 인프라 튜닝
    │
    ▼
6. 검증: 변경 전후 latency 비교 (A/B 또는 before/after)
```

## 6. Search Quality Monitoring Dashboard

### Dashboard Layout

```
┌─────────────────────────────────────────────────────────────────────┐
│                    Search Quality Dashboard                         │
├─────────────────────┬──────────────────────┬────────────────────────┤
│  Row 1: Real-time Health                                            │
├─────────────────────┬──────────────────────┬────────────────────────┤
│  Zero-Result Rate   │  CTR@3               │  p99 Latency           │
│  ┌───────────┐      │  ┌───────────┐       │  ┌───────────┐        │
│  │   3.2%    │      │  │  34.5%    │       │  │  287ms    │        │
│  │  (< 5% )  │      │  │  (> 30% ) │       │  │  (< 500ms)│        │
│  └───────────┘      │  └───────────┘       │  └───────────┘        │
├─────────────────────┴──────────────────────┴────────────────────────┤
│  Row 2: Volume & Performance                                        │
├──────────────────────────────────┬──────────────────────────────────┤
│  QPS (time series)               │  Latency Distribution            │
│  ┌──────────────────────────┐    │  ┌──────────────────────────┐   │
│  │  ╱╲    ╱╲                │    │  │  p50: ──── 45ms          │   │
│  │ ╱  ╲╱╱  ╲  ╱╲           │    │  │  p95: ─ ─  182ms         │   │
│  │╱         ╲╱  ╲          │    │  │  p99: ····· 287ms         │   │
│  │            ╲   ╲         │    │  │                           │   │
│  │  00:00  06:00  12:00  18│    │  │  00:00  06:00  12:00  18 │   │
│  └──────────────────────────┘    │  └──────────────────────────┘   │
├──────────────────────────────────┴──────────────────────────────────┤
│  Row 3: Result Quality                                              │
├──────────────────────────────────┬──────────────────────────────────┤
│  Zero-Result Top 20 Queries      │  Low-CTR Top 20 Queries          │
│  ┌──────────────────────────┐    │  ┌──────────────────────────┐   │
│  │  Query          │ Count  │    │  │  Query        │ CTR │Imp │   │
│  │  ───────────────┼────── │    │  │  ────────────┼─────┼─── │   │
│  │  "xyz브랜드"    │  342  │    │  │  "이어폰"    │ 2.1%│8.2k│   │
│  │  "asd제품"      │  218  │    │  │  "가방"      │ 3.4%│5.1k│   │
│  │  "신규브랜드"   │  195  │    │  │  "신발"      │ 4.2%│4.8k│   │
│  │  ...            │  ...  │    │  │  ...         │ ... │ .. │   │
│  └──────────────────────────┘    │  └──────────────────────────┘   │
├──────────────────────────────────┴──────────────────────────────────┤
│  Row 4: A/B Test Results                                            │
├──────────────────────────────────┬──────────────────────────────────┤
│  CTR by Variant                  │  Latency by Variant              │
│  ┌──────────────────────────┐    │  ┌──────────────────────────┐   │
│  │  ■ control:  32.1%       │    │  │  ■ control:  p99 280ms   │   │
│  │  ■ variant_a: 36.8% (+4.7)   │  │  ■ variant_a: p99 295ms   │   │
│  │  ■ variant_b: 33.2% (+1.1)   │  │  ■ variant_b: p99 310ms   │   │
│  │  (p-value: 0.003*)       │    │  │  (guardrail: < 500ms OK) │   │
│  └──────────────────────────┘    │  └──────────────────────────┘   │
├──────────────────────────────────┴──────────────────────────────────┤
│  Row 5: System Health                                               │
├──────────────────────────────────┬──────────────────────────────────┤
│  ES Cluster Health               │  Circuit Breaker / Slow Query    │
│  ┌──────────────────────────┐    │  ┌──────────────────────────┐   │
│  │  Status: GREEN            │    │  │  CB Open:  0             │   │
│  │  Nodes:  5/5              │    │  │  Slow (>200ms): 12/min   │   │
│  │  Shards: 120 active       │    │  │  Very Slow (>1s): 0/min  │   │
│  │  Heap:   62% avg          │    │  │                          │   │
│  └──────────────────────────┘    │  └──────────────────────────┘   │
└──────────────────────────────────┴──────────────────────────────────┘
```

### PromQL Example Queries

```promql
# Row 1: Zero-Result Rate (last 5 minutes)
sum(rate(search_zero_results_total[5m]))
/
sum(rate(search_throughput_total[5m]))

# Row 1: CTR@3
sum(rate(search_clicks_by_position_total{position_bucket="top3"}[5m]))
/
sum(rate(search_impressions_total[5m]))

# Row 1: p99 Latency
histogram_quantile(0.99, sum(rate(search_latency_seconds_bucket[5m])) by (le))

# Row 2: QPS
sum(rate(search_throughput_total[1m]))

# Row 2: Latency percentiles
histogram_quantile(0.50, sum(rate(search_latency_seconds_bucket[5m])) by (le))
histogram_quantile(0.95, sum(rate(search_latency_seconds_bucket[5m])) by (le))
histogram_quantile(0.99, sum(rate(search_latency_seconds_bucket[5m])) by (le))

# Row 4: CTR by experiment variant
sum(rate(search_clicks_by_position_total{position_bucket="top3"}[1h])) by (experiment_group)
/
sum(rate(search_impressions_total[1h])) by (experiment_group)

# Row 4: p99 Latency by variant
histogram_quantile(0.99,
  sum(rate(search_latency_seconds_bucket[1h])) by (le, experiment_group)
)

# Row 5: Slow query rate
sum(rate(search_slow_query_total[5m]))

# Row 5: Circuit breaker status
search_circuit_breaker_open
```

### Alert Rules

```yaml
# Prometheus alerting rules
groups:
  - name: search_quality_alerts
    rules:
      # Zero-result rate 급등
      - alert: SearchHighZeroResultRate
        expr: |
          sum(rate(search_zero_results_total[10m]))
          / sum(rate(search_throughput_total[10m]))
          > 0.10
        for: 5m
        labels:
          severity: critical
          team: search
        annotations:
          summary: "Zero-result rate > 10% for 5 minutes"
          description: "현재 zero-result rate: {{ $value | humanizePercentage }}"

      # CTR@3 급락
      - alert: SearchLowCTR
        expr: |
          sum(rate(search_clicks_by_position_total{position_bucket="top3"}[30m]))
          / sum(rate(search_impressions_total[30m]))
          < 0.15
        for: 15m
        labels:
          severity: warning
          team: search
        annotations:
          summary: "CTR@3 dropped below 15% for 15 minutes"

      # p99 latency 급등
      - alert: SearchHighLatency
        expr: |
          histogram_quantile(0.99,
            sum(rate(search_latency_seconds_bucket[5m])) by (le)
          ) > 1.0
        for: 5m
        labels:
          severity: critical
          team: search
        annotations:
          summary: "Search p99 latency > 1s for 5 minutes"

      # Slow query rate 급등
      - alert: SearchSlowQuerySpike
        expr: sum(rate(search_slow_query_total[5m])) > 10
        for: 5m
        labels:
          severity: warning
          team: search
        annotations:
          summary: "Slow query rate > 10/sec for 5 minutes"

      # 실험 guardrail: variant latency 악화
      - alert: ExperimentGuardrailLatency
        expr: |
          histogram_quantile(0.99,
            sum(rate(search_latency_seconds_bucket{experiment_group!="control"}[1h])) by (le, experiment_group)
          )
          > 0.5
        for: 30m
        labels:
          severity: warning
          team: search
        annotations:
          summary: "Experiment variant p99 latency exceeds 500ms guardrail"
```

## 7. Anti-Patterns

| Anti-Pattern | Severity | 문제 | 올바른 접근 |
|-------------|----------|------|-----------|
| Zero-result 추적 없음 | **Critical** | 검색 실패를 감지할 수 없어 사용자 이탈 원인 파악 불가 | `search.zero_results` counter + Top-N 쿼리 대시보드 |
| Position 무시한 CTR 측정 | **High** | 1위 클릭과 20위 클릭을 동일 가치로 취급, relevance 왜곡 | `position_bucket` 태그로 top3/top10/below10 분리 측정 |
| Guardrail 없는 A/B 테스트 | **High** | Primary metric 개선에만 집중, latency/error 악화 미감지 | p99 latency, error rate, zero-result rate를 guardrail로 설정 |
| 메트릭 수집만 하고 대시보드/알림 미구축 | **Medium** | 데이터가 있어도 아무도 보지 않으면 무의미 | 대시보드 + 임계값 기반 알림 필수 구축 |
| Slow query 알림 미설정 | **High** | 성능 저하를 사후에야 발견, 장애 확대 | AOP 기반 감지 + ES slow log + 알림 연동 |
| 세션 추적 시 개인정보 미처리 | **High** | user_id 등 개인식별정보를 메트릭/로그에 노출 | 익명화된 session_id 사용, PII 제거 후 집계 |
| 실험 기간 부족 | **Medium** | 충분한 표본 없이 결론 도출, 통계적 유의성 미달 | Power analysis로 필요 표본 크기 산출, 최소 2주 운영 |
| 메트릭 카디널리티 폭발 | **High** | query 원문을 태그로 사용하여 time-series DB 부하 | 쿼리 원문은 로그/ES로, 메트릭 태그는 `query_type` 같은 저카디널리티 값만 |

```kotlin
// BAD: 쿼리 원문을 메트릭 태그로 사용 (카디널리티 폭발)
Counter.builder("search.query")
    .tag("query", userQuery)  // 수백만 가지 값 → Prometheus OOM
    .register(meterRegistry)

// GOOD: 저카디널리티 분류값을 태그로, 원문은 별도 저장
Counter.builder("search.query")
    .tag("query_type", classifyQueryType(userQuery))  // "keyword", "filtered", "autocomplete"
    .register(meterRegistry)

// 쿼리 원문은 Kafka → ES 인덱스로 저장하여 분석
kafkaPublisher.publish("search-queries", queryEvent)
```

---

**Remember**: 검색 관찰 가능성의 핵심은 '검색 결과가 없는 쿼리'와 '클릭되지 않는 결과'를 빠르게 찾아내는 것입니다. zero-result 모니터링과 CTR 추적은 검색 품질 개선의 출발점입니다. 메트릭을 수집만 하고 대시보드와 알림을 만들지 않으면 의미가 없습니다.
