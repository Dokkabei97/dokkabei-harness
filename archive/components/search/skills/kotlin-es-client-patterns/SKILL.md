---
name: kotlin-es-client-patterns
description: Use this skill when implementing Elasticsearch integration in Kotlin or Python applications. Covers client setup, search implementation, bulk indexing, testing, and common mistakes with the elasticsearch-java v8 client and elasticsearch-py.
---

# Kotlin + Elasticsearch Client Patterns

Kotlin 기반 Elasticsearch 클라이언트 구현 패턴을 제공합니다. elasticsearch-java v8 (co.elastic.clients) 중심으로, coroutine 통합, 테스트 전략, 그리고 Python 서브스택 패턴까지 다룹니다.

## When to Activate

- Elasticsearch Java/Kotlin 클라이언트 설정 또는 업그레이드 시
- 검색 API 구현 또는 쿼리 빌더 작성 시
- Bulk indexing 파이프라인 구축 또는 성능 튜닝 시
- ES 관련 테스트 코드 작성 또는 리팩토링 시
- Kotlin coroutine과 ES 클라이언트 통합 시
- Python elasticsearch-py 클라이언트 사용 시

## 1. Client Setup

### elasticsearch-java v8 Configuration

```kotlin
@Configuration
class ElasticsearchConfig(
    @Value("\${elasticsearch.hosts}") private val hosts: List<String>,
    @Value("\${elasticsearch.username}") private val username: String,
    @Value("\${elasticsearch.password}") private val password: String
) {
    @Bean
    fun elasticsearchClient(): ElasticsearchClient {
        // RestClient (low-level HTTP transport)
        val restClient = RestClient.builder(
            *hosts.map { HttpHost.create(it) }.toTypedArray()
        ).setHttpClientConfigCallback { httpBuilder ->
            httpBuilder.setDefaultCredentialsProvider(
                BasicCredentialsProvider().apply {
                    setCredentials(
                        AuthScope.ANY,
                        UsernamePasswordCredentials(username, password)
                    )
                }
            )
            // 커넥션 풀 설정
            httpBuilder.setMaxConnTotal(100)
            httpBuilder.setMaxConnPerRoute(20)
        }.setRequestConfigCallback { requestBuilder ->
            requestBuilder
                .setConnectTimeout(5_000)
                .setSocketTimeout(60_000)
        }.build()

        // JSON mapper transport
        val transport = RestClientTransport(restClient, JacksonJsonpMapper())
        return ElasticsearchClient(transport)
    }
}
```

### Sniffing (노드 자동 감지)

```kotlin
// Sniffer로 클러스터 노드 자동 감지
val sniffer = Sniffer.builder(restClient)
    .setSniffIntervalMillis(60_000)        // 1분 간격 스니핑
    .setSniffAfterFailureDelayMillis(5_000) // 실패 후 5초 후 재스니핑
    .build()

// 애플리케이션 종료 시 반드시 close
@PreDestroy
fun cleanup() {
    sniffer.close()
    restClient.close()
}
```

### Retry & Backoff

```kotlin
// RestClient 레벨 retry는 내장 (max 3회 기본)
// 애플리케이션 레벨 retry는 직접 구현
suspend fun <T> withRetry(
    maxAttempts: Int = 3,
    initialDelay: Long = 100,
    maxDelay: Long = 5000,
    block: suspend () -> T
): T {
    var lastException: Exception? = null
    var delay = initialDelay

    repeat(maxAttempts) { attempt ->
        try {
            return block()
        } catch (e: ElasticsearchException) {
            if (e.status() == 429) { // Too Many Requests
                lastException = e
                delay(delay)
                delay = (delay * 2).coerceAtMost(maxDelay)
            } else throw e
        } catch (e: IOException) {
            lastException = e
            delay(delay)
            delay = (delay * 2).coerceAtMost(maxDelay)
        }
    }
    throw lastException!!
}
```

### Health Check

```kotlin
@Component
class ElasticsearchHealthIndicator(
    private val client: ElasticsearchClient
) : HealthIndicator {
    override fun health(): Health {
        return try {
            val response = client.cluster().health()
            when (response.status()) {
                HealthStatus.Green -> Health.up()
                    .withDetail("status", "green")
                    .withDetail("numberOfNodes", response.numberOfNodes())
                    .build()
                HealthStatus.Yellow -> Health.up()
                    .withDetail("status", "yellow")
                    .build()
                HealthStatus.Red -> Health.down()
                    .withDetail("status", "red")
                    .build()
            }
        } catch (e: Exception) {
            Health.down(e).build()
        }
    }
}
```

### Legacy: Java High Level REST Client

```kotlin
// ES 7.x 이하 레거시 프로젝트용 (deprecated in 7.15+)
// 마이그레이션 계획 수립 필요
val client = RestHighLevelClient(
    RestClient.builder(HttpHost("localhost", 9200, "http"))
)
// 주의: 8.x에서 제거 예정. 신규 코드는 elasticsearch-java 사용
```

## 2. Search Implementation

### Typesafe Query Builder API

```kotlin
// elasticsearch-java v8의 typesafe builder
fun searchProducts(keyword: String, category: String?, priceRange: IntRange?): List<Product> {
    val response = client.search({ s ->
        s.index("products")
            .query { q ->
                q.bool { b ->
                    // must: full-text 검색
                    b.must { m ->
                        m.multiMatch { mm ->
                            mm.query(keyword)
                                .fields("title^3", "title.search^2", "description")
                                .type(TextQueryType.BestFields)
                        }
                    }
                    // filter: exact match (스코어 무관)
                    category?.let { cat ->
                        b.filter { f -> f.term { t -> t.field("category").value(cat) } }
                    }
                    priceRange?.let { range ->
                        b.filter { f ->
                            f.range { r ->
                                r.field("price")
                                    .gte(JsonData.of(range.first))
                                    .lte(JsonData.of(range.last))
                            }
                        }
                    }
                    b
                }
            }
            .source { src ->
                src.filter { f -> f.includes("title", "price", "category", "thumbnail_url") }
            }
            .size(20)
    }, Product::class.java)

    return response.hits().hits().mapNotNull { it.source() }
}
```

### Raw JSON Query (복잡한 쿼리)

```kotlin
// 매우 복잡한 쿼리는 JSON 직접 사용 가능
fun searchWithRawJson(queryJson: String): SearchResponse<JsonData> {
    val reader = StringReader(queryJson)
    val request = SearchRequest.of { s ->
        s.index("products").withJson(reader)
    }
    return client.search(request, JsonData::class.java)
}
```

### Scroll vs search_after Pagination

```kotlin
// search_after (권장: stateless, 병렬 가능)
fun searchAfterPagination(keyword: String, searchAfter: List<FieldValue>?): SearchPage {
    val response = client.search({ s ->
        s.index("products")
            .query { q -> q.match { m -> m.field("title").query(keyword) } }
            .sort { sort -> sort.field { f -> f.field("_score").order(SortOrder.Desc) } }
            .sort { sort -> sort.field { f -> f.field("_id").order(SortOrder.Asc) } }
            .size(20)
            .apply {
                searchAfter?.let { sa -> searchAfter(sa) }
            }
    }, Product::class.java)

    val hits = response.hits().hits()
    val lastSort = hits.lastOrNull()?.sort()

    return SearchPage(
        items = hits.mapNotNull { it.source() },
        nextSearchAfter = lastSort,
        total = response.hits().total()?.value() ?: 0
    )
}
```

### Multi-Search (msearch) for Parallel Queries

```kotlin
// 여러 쿼리를 하나의 HTTP 요청으로 실행
fun parallelSearch(keyword: String): AggregatedSearchResult {
    val response = client.msearch({ ms ->
        ms.searches(
            // 상품 검색
            { rs -> rs
                .header { h -> h.index("products") }
                .body { b -> b.query { q -> q.match { m -> m.field("title").query(keyword) } }.size(10) }
            },
            // 카테고리 집계
            { rs -> rs
                .header { h -> h.index("products") }
                .body { b ->
                    b.size(0).aggregations("categories") { a ->
                        a.terms { t -> t.field("category").size(10) }
                    }
                }
            },
            // 브랜드 추천
            { rs -> rs
                .header { h -> h.index("brands") }
                .body { b -> b.query { q -> q.match { m -> m.field("name").query(keyword) } }.size(5) }
            }
        )
    }, JsonData::class.java)

    // 각 응답 개별 처리
    val productHits = response.responses()[0].result().hits()
    val categoryAggs = response.responses()[1].result().aggregations()
    val brandHits = response.responses()[2].result().hits()

    return AggregatedSearchResult(productHits, categoryAggs, brandHits)
}
```

### Kotlin Coroutine Integration

```kotlin
// ES 클라이언트는 동기 API이므로 suspend fun wrapper 필요
@Service
class SearchService(
    private val client: ElasticsearchClient,
    private val searchDispatcher: CoroutineDispatcher = Dispatchers.IO
) {
    // IO 디스패처에서 블로킹 호출 실행
    suspend fun search(request: SearchRequest): SearchResponse<Product> =
        withContext(searchDispatcher) {
            client.search(request, Product::class.java)
        }

    // 여러 인덱스 병렬 검색
    suspend fun parallelSearch(keyword: String): CombinedResult = coroutineScope {
        val products = async { searchProducts(keyword) }
        val suggestions = async { searchSuggestions(keyword) }
        val relatedKeywords = async { findRelatedKeywords(keyword) }

        CombinedResult(
            products = products.await(),
            suggestions = suggestions.await(),
            relatedKeywords = relatedKeywords.await()
        )
    }
}
```

## 3. Bulk Indexing

### BulkProcessor Pattern

```kotlin
// elasticsearch-java v8 BulkIngester
@Component
class ProductIndexer(
    private val client: ElasticsearchClient
) {
    private val bulkIngester = BulkIngester.of { b ->
        b.client(client)
            .maxOperations(500)         // 500건마다 flush
            .flushInterval(5, TimeUnit.SECONDS) // 또는 5초마다
            .maxConcurrentRequests(2)   // 동시 2개 요청
            .listener(object : BulkListener<Any> {
                override fun beforeBulk(executionId: Long, request: BulkRequest, contexts: List<Any>) {
                    logger.info("Bulk #{}: {} operations", executionId, request.operations().size)
                }
                override fun afterBulk(executionId: Long, request: BulkRequest, contexts: List<Any>, response: BulkResponse) {
                    if (response.errors()) {
                        response.items().filter { it.error() != null }.forEach { item ->
                            logger.error("Bulk item error: index={}, id={}, error={}",
                                item.index(), item.id(), item.error()?.reason())
                        }
                    }
                }
                override fun afterBulk(executionId: Long, request: BulkRequest, contexts: List<Any>, failure: Throwable) {
                    logger.error("Bulk #{} failed", executionId, failure)
                }
            })
    }

    fun indexProduct(product: Product) {
        bulkIngester.add { op ->
            op.index { idx ->
                idx.index("products").id(product.id).document(product)
            }
        }
    }

    @PreDestroy
    fun close() = bulkIngester.close()
}
```

### Coroutine-Based Indexing Pipeline

```kotlin
// Channel 기반 비동기 인덱싱 파이프라인
class CoroutineBulkIndexer(
    private val client: ElasticsearchClient,
    private val batchSize: Int = 500,
    private val flushIntervalMs: Long = 5000
) {
    private val channel = Channel<BulkOperation>(capacity = 10_000)

    // producer: 문서 투입
    suspend fun add(operation: BulkOperation) {
        channel.send(operation)
    }

    // consumer: 배치 처리
    fun start(scope: CoroutineScope) = scope.launch(Dispatchers.IO) {
        val buffer = mutableListOf<BulkOperation>()
        var lastFlush = System.currentTimeMillis()

        for (op in channel) {
            buffer.add(op)
            val elapsed = System.currentTimeMillis() - lastFlush

            if (buffer.size >= batchSize || elapsed >= flushIntervalMs) {
                flush(buffer.toList())
                buffer.clear()
                lastFlush = System.currentTimeMillis()
            }
        }
        // 채널 종료 시 남은 버퍼 flush
        if (buffer.isNotEmpty()) flush(buffer)
    }

    private suspend fun flush(operations: List<BulkOperation>) {
        try {
            val response = client.bulk { b -> b.operations(operations) }
            if (response.errors()) {
                val failures = response.items().filter { it.error() != null }
                logger.error("Bulk indexing partial failure: {} / {} failed",
                    failures.size, operations.size)
                // 실패 건 재시도 또는 DLQ 저장
                handleFailures(failures, operations)
            }
        } catch (e: Exception) {
            logger.error("Bulk request failed entirely", e)
            // 전체 실패 시 재시도 큐로 전송
        }
    }
}
```

### Struct-to-Document Serialization

```kotlin
// Jackson 직렬화 설정
@JsonNaming(PropertyNamingStrategies.SnakeCaseStrategy::class)
data class ProductDocument(
    @JsonProperty("id") val id: String,
    @JsonProperty("title") val title: String,
    @JsonProperty("price") val price: Int,
    @JsonProperty("category") val category: String,
    @JsonProperty("tags") val tags: List<String>,
    @JsonProperty("created_at") val createdAt: Instant,
    @JsonIgnore val internalMemo: String? = null // ES에 인덱싱하지 않음
) {
    companion object {
        fun from(product: Product): ProductDocument = ProductDocument(
            id = product.id,
            title = product.title,
            price = product.price,
            category = product.category.code,
            tags = product.tags.map { it.name },
            createdAt = product.createdAt
        )
    }
}
```

## 4. Testing

### @SpringBootTest with Testcontainers

```kotlin
@SpringBootTest
@Testcontainers
class ProductSearchServiceTest {

    companion object {
        @Container
        @JvmStatic
        val elasticsearch = ElasticsearchContainer(
            DockerImageName.parse("docker.elastic.co/elasticsearch/elasticsearch:8.12.0")
        ).apply {
            withEnv("discovery.type", "single-node")
            withEnv("xpack.security.enabled", "false")
            withEnv("ES_JAVA_OPTS", "-Xms512m -Xmx512m")
        }

        @DynamicPropertySource
        @JvmStatic
        fun overrideProperties(registry: DynamicPropertyRegistry) {
            registry.add("elasticsearch.hosts") { listOf(elasticsearch.httpHostAddress) }
        }
    }

    @Autowired
    lateinit var searchService: ProductSearchService

    @Autowired
    lateinit var client: ElasticsearchClient

    @BeforeEach
    fun setup() {
        // 테스트 인덱스 생성 및 fixture 투입
        createTestIndex()
        indexTestDocuments()
        // 인덱싱 후 refresh 필수 (테스트에서는 즉시 검색 가능하도록)
        client.indices().refresh { r -> r.index("products") }
    }

    @Test
    fun `상품 검색 시 제목 매칭 결과 반환`() {
        val results = searchService.searchProducts("무선 이어폰", null, null)
        assertThat(results).isNotEmpty
        assertThat(results.first().title).contains("이어폰")
    }

    @AfterEach
    fun cleanup() {
        client.indices().delete { d -> d.index("products") }
    }
}
```

### MockK for Unit Tests

```kotlin
class SearchServiceUnitTest {

    private val client: ElasticsearchClient = mockk()
    private val service = SearchService(client)

    @Test
    fun `검색 결과가 없을 때 빈 리스트 반환`() {
        // Given
        val emptyResponse = mockk<SearchResponse<Product>> {
            every { hits() } returns mockk {
                every { hits() } returns emptyList()
                every { total() } returns mockk { every { value() } returns 0 }
            }
        }
        every { client.search(any<SearchRequest>(), Product::class.java) } returns emptyResponse

        // When
        val result = service.searchProducts("존재하지않는키워드")

        // Then
        assertThat(result).isEmpty()
        verify(exactly = 1) { client.search(any<SearchRequest>(), Product::class.java) }
    }
}
```

### Search Test Fixtures

```kotlin
object SearchTestFixtures {
    fun productDocuments(): List<Product> = listOf(
        Product(id = "1", title = "삼성 무선 이어폰 버즈3", price = 150000, category = "electronics"),
        Product(id = "2", title = "애플 에어팟 프로 2세대", price = 320000, category = "electronics"),
        Product(id = "3", title = "소니 노이즈캔슬링 헤드폰", price = 280000, category = "electronics"),
        Product(id = "4", title = "무선 충전기 고속", price = 25000, category = "accessories"),
    )

    // 매핑 JSON (테스트용 간소화 버전)
    val productMapping = """
    {
        "mappings": {
            "properties": {
                "title": { "type": "text", "analyzer": "standard" },
                "price": { "type": "integer" },
                "category": { "type": "keyword" }
            }
        }
    }
    """.trimIndent()
}
```

### Benchmark Pattern

```kotlin
// JMH를 활용한 검색 성능 벤치마크
@State(Scope.Benchmark)
@BenchmarkMode(Mode.AverageTime)
@OutputTimeUnit(TimeUnit.MILLISECONDS)
open class SearchBenchmark {
    private lateinit var client: ElasticsearchClient

    @Setup
    fun setup() { /* ES 연결 및 테스트 데이터 준비 */ }

    @Benchmark
    fun searchSingleMatch(bh: Blackhole) {
        val response = client.search({ s ->
            s.index("products").query { q -> q.match { m -> m.field("title").query("이어폰") } }
        }, Product::class.java)
        bh.consume(response)
    }

    @Benchmark
    fun searchBoolWithFilter(bh: Blackhole) {
        val response = client.search({ s ->
            s.index("products").query { q ->
                q.bool { b ->
                    b.must { m -> m.match { mt -> mt.field("title").query("이어폰") } }
                    b.filter { f -> f.term { t -> t.field("category").value("electronics") } }
                    b
                }
            }
        }, Product::class.java)
        bh.consume(response)
    }
}
```

## 5. Common Mistakes

| Mistake | 문제 | Fix | Severity |
|---------|------|-----|----------|
| Response 미닫기 | 커넥션 풀 고갈, 메모리 누수 | `use {}` 또는 `try-finally`로 close 보장 | **Critical** |
| `isError()` 무시 | 부분 실패 감지 못함 | bulk response에서 `errors()` 확인 | **High** |
| 문자열 연결로 쿼리 생성 | injection 위험, 유지보수 불가 | builder API 또는 parameterized query 사용 | **Critical** |
| timeout context 미설정 | 느린 쿼리가 스레드 점유 | `requestTimeout`, coroutine `withTimeout` 적용 | **High** |
| bulk flush 동기 대기 | 호출 스레드 블로킹 | coroutine 또는 비동기 listener 활용 | **Medium** |
| `_source` 필터링 미사용 | 불필요한 필드까지 전송 | `source(includes)` 로 필요 필드만 조회 | **Medium** |
| `from/size` 깊은 페이징 | 10,000건 이상 시 성능 급락 | `search_after` 사용 | **High** |
| 인덱싱 후 refresh 없이 검색 | 테스트에서 결과 누락 | `indices().refresh()` 호출 (테스트 시) | **Medium** |

```kotlin
// BAD: response 미닫기
val response = client.search(request, Product::class.java)
// 응답 처리 중 예외 시 리소스 누수

// GOOD: timeout과 함께 안전하게 처리
suspend fun safeSearch(request: SearchRequest): List<Product> =
    withContext(Dispatchers.IO) {
        withTimeout(10_000) { // 10초 타임아웃
            val response = client.search(request, Product::class.java)
            response.hits().hits().mapNotNull { it.source() }
        }
    }
```

## 6. Python Subsection (elasticsearch-py)

서브 기술 스택인 Python에서의 ES 클라이언트 패턴.

### AsyncElasticsearch Setup

```python
from elasticsearch import AsyncElasticsearch

es = AsyncElasticsearch(
    hosts=["http://es-host:9200"],
    basic_auth=("user", "password"),
    max_retries=3,
    retry_on_timeout=True,
    request_timeout=30,
)

async def search_products(keyword: str) -> list[dict]:
    response = await es.search(
        index="products",
        body={
            "query": {"match": {"title": keyword}},
            "size": 20,
            "_source": ["title", "price", "category"],
        },
    )
    return [hit["_source"] for hit in response["hits"]["hits"]]

# 애플리케이션 종료 시 반드시 close
async def shutdown():
    await es.close()
```

### helpers.bulk & scan

```python
from elasticsearch.helpers import async_bulk, async_scan

# Bulk 인덱싱
async def bulk_index(documents: list[dict]):
    actions = [
        {
            "_index": "products",
            "_id": doc["id"],
            "_source": doc,
        }
        for doc in documents
    ]
    success, errors = await async_bulk(es, actions, chunk_size=500, raise_on_error=False)
    if errors:
        logger.error(f"Bulk indexing errors: {len(errors)} failures")

# Scan (전체 문서 순회, scroll 대체)
async def export_all_products():
    async for doc in async_scan(
        es,
        index="products",
        query={"query": {"match_all": {}}},
        scroll="5m",
        size=1000,
    ):
        yield doc["_source"]
```

### Python 주의사항

| Mistake | Fix |
|---------|-----|
| 동기 `Elasticsearch` 클라이언트를 async 앱에서 사용 | `AsyncElasticsearch` 사용 |
| `helpers.bulk`에서 `raise_on_error=True` (기본값) | `False`로 변경 후 에러 별도 처리 |
| `scan` helper에서 `scroll` 시간 너무 길게 설정 | `"5m"` 이하, 처리 속도에 맞게 |
| `body` dict를 수동 구성 시 오타 | `elasticsearch-dsl` 라이브러리로 builder 패턴 |

---

**Remember**: ES 클라이언트는 thread-safe하지만, 요청당 리소스 관리는 필수입니다. 커넥션 풀 크기, timeout, retry 정책을 운영 환경에 맞게 반드시 튜닝하세요.
