---
name: search-data-pipeline
description: Use this skill when building or troubleshooting data ingestion pipelines that feed Elasticsearch. Covers Kafka consumer patterns for ES indexing, Apache Iceberg/Spark/Trino integration for batch reindexing, and cross-cutting pipeline monitoring from the search team's consumer perspective.
---

# Search Data Pipeline

Elasticsearch 인덱싱을 위한 데이터 파이프라인 가이드입니다. 검색팀은 DE 팀이 관리하는 파이프라인 인프라(Kafka, Iceberg, Spark, Trino, HDFS)의 **소비자** 입장에서, consumer 설정, 인덱싱 로직, 모니터링을 책임집니다.

## When to Activate

- Kafka consumer → ES bulk indexing 파이프라인 구축/트러블슈팅 시
- Spark 배치 인덱싱 작업 설정 시
- Iceberg 테이블 → ES 동기화 패턴 설계 시
- Trino로 검색 로그 분석 쿼리 작성 시
- 파이프라인 지연(lag) 모니터링 및 SLA 관리 시
- Schema Registry 스키마 변경 대응 시
- 전체 재인덱싱 vs 증분 인덱싱 결정 시

## 1. Kafka → ES Indexing Pipeline

### 1.1 Spring-Kafka Consumer Setup

```yaml
# application.yml
spring:
  kafka:
    bootstrap-servers: ${KAFKA_BOOTSTRAP_SERVERS:kafka-broker-1:9092,kafka-broker-2:9092,kafka-broker-3:9092}
    consumer:
      group-id: search-es-indexer
      auto-offset-reset: earliest
      max-poll-records: 500
      enable-auto-commit: false          # 반드시 false — ES 인덱싱 성공 후 수동 커밋
      properties:
        max.poll.interval.ms: 300000     # 5분 — bulk 인덱싱 처리 시간 고려
        session.timeout.ms: 45000        # 45초 — heartbeat 누락 감지
        heartbeat.interval.ms: 15000     # 15초 — session.timeout의 1/3
        fetch.min.bytes: 1024            # 1KB — 최소 fetch 크기
        fetch.max.wait.ms: 500           # 500ms — fetch 대기 최대 시간
      key-deserializer: org.apache.kafka.common.serialization.StringDeserializer
      value-deserializer: io.confluent.kafka.serializers.KafkaAvroDeserializer
      properties:
        schema.registry.url: ${SCHEMA_REGISTRY_URL:http://schema-registry:8081}
        specific.avro.reader: true
    listener:
      type: batch                        # 배치 리스너 필수
      ack-mode: manual                   # 수동 ACK 모드
      concurrency: 3                     # 파티션 수에 맞게 조절
```

```kotlin
@Configuration
class KafkaConsumerConfig {

    @Bean
    fun kafkaListenerContainerFactory(
        consumerFactory: ConsumerFactory<String, GenericRecord>
    ): ConcurrentKafkaListenerContainerFactory<String, GenericRecord> {
        return ConcurrentKafkaListenerContainerFactory<String, GenericRecord>().apply {
            this.consumerFactory = consumerFactory
            isBatchListener = true
            containerProperties.ackMode = ContainerProperties.AckMode.MANUAL
            containerProperties.idleBetweenPolls = 100
            // 셧다운 시 현재 배치 처리 완료 대기
            setContainerCustomizer { container ->
                container.containerProperties.isStopImmediate = false
            }
        }
    }
}
```

### 1.2 Batch Consumption → ES Bulk API Pattern

```kotlin
@Component
class KafkaElasticsearchIndexer(
    private val esClient: ElasticsearchClient,
    private val meterRegistry: MeterRegistry
) {
    private val logger = LoggerFactory.getLogger(javaClass)
    private val indexedCounter = Counter.builder("es.indexer.documents.indexed")
        .description("Total documents indexed to ES")
        .register(meterRegistry)
    private val failedCounter = Counter.builder("es.indexer.documents.failed")
        .description("Total documents failed to index")
        .register(meterRegistry)
    private val bulkTimer = Timer.builder("es.indexer.bulk.duration")
        .description("ES bulk request duration")
        .register(meterRegistry)

    @KafkaListener(
        topics = ["\${kafka.topics.product-update}"],
        groupId = "search-es-indexer",
        containerFactory = "kafkaListenerContainerFactory"
    )
    fun consumeAndIndex(
        records: List<ConsumerRecord<String, GenericRecord>>,
        acknowledgment: Acknowledgment
    ) {
        if (records.isEmpty()) return

        logger.info("Received batch: {} records from partitions {}",
            records.size,
            records.map { it.partition() }.distinct()
        )

        try {
            // 1. Kafka 레코드 → ES BulkOperation 변환
            val operations = records.mapNotNull { record ->
                try {
                    val doc = convertToDocument(record.value())
                    BulkOperation.of { op ->
                        op.index { idx ->
                            idx.index(resolveIndex(doc))
                                .id(record.key())      // Kafka key = ES _id (멱등성 보장)
                                .document(doc)
                        }
                    }
                } catch (e: Exception) {
                    logger.error("Failed to convert record: topic={}, partition={}, offset={}, key={}",
                        record.topic(), record.partition(), record.offset(), record.key(), e)
                    failedCounter.increment()
                    null
                }
            }

            if (operations.isEmpty()) {
                acknowledgment.acknowledge()
                return
            }

            // 2. ES Bulk API 호출
            val response = bulkTimer.recordCallable {
                esClient.bulk { b ->
                    b.operations(operations)
                        .timeout { t -> t.time("30s") }
                        .refresh(Refresh.False)     // bulk 중 refresh 방지
                }
            }!!

            // 3. 응답 검증
            if (response.errors()) {
                val failedItems = response.items().filter { it.error() != null }
                failedItems.forEach { item ->
                    logger.error("Bulk item error: index={}, id={}, status={}, reason={}",
                        item.index(), item.id(), item.status(), item.error()?.reason())
                }
                failedCounter.increment(failedItems.size.toDouble())

                // 재시도 가능한 에러(429, 503)만 있으면 전체 재시도
                val hasOnlyRetryable = failedItems.all { it.status() in listOf(429, 503) }
                if (hasOnlyRetryable) {
                    throw RetryableIndexingException(
                        "All ${failedItems.size} failures are retryable (429/503)"
                    )
                }
            }

            val successCount = response.items().count { it.error() == null }
            indexedCounter.increment(successCount.toDouble())
            logger.info("Bulk indexed: {}/{} succeeded", successCount, operations.size)

            // 4. ES 인덱싱 성공 확인 후 오프셋 커밋
            acknowledgment.acknowledge()

        } catch (e: RetryableIndexingException) {
            // DefaultErrorHandler가 재시도 처리
            throw e
        } catch (e: Exception) {
            logger.error("Unexpected error during bulk indexing", e)
            throw e
        }
    }

    private fun convertToDocument(record: GenericRecord): Map<String, Any?> {
        return mapOf(
            "title" to record.get("title")?.toString(),
            "description" to record.get("description")?.toString(),
            "price" to record.get("price"),
            "category" to record.get("category")?.toString(),
            "brand" to record.get("brand")?.toString(),
            "status" to record.get("status")?.toString(),
            "updated_at" to Instant.ofEpochMilli(record.get("updated_at") as Long)
        )
    }

    private fun resolveIndex(doc: Map<String, Any?>): String {
        // 시간 기반 인덱스 또는 alias 기반 라우팅
        return "products-v1"
    }
}

class RetryableIndexingException(message: String) : RuntimeException(message)
```

**Batch size 튜닝 원칙**:

| 파라미터 | 권장 값 | 설명 |
|---------|--------|------|
| `max.poll.records` | 500 | Kafka 단일 poll 최대 레코드 수 |
| ES bulk 요청 크기 | 5-15MB | `max.poll.records` × 평균 문서 크기 기준 |
| `max.poll.interval.ms` | 300000 (5분) | bulk 처리 + retry 시간 포함 |
| ES bulk timeout | 30s | 단일 bulk 요청 타임아웃 |
| `listener.concurrency` | 파티션 수 이하 | 파티션 3개면 concurrency 3 이하 |

### 1.3 Idempotent Indexing

```kotlin
// Kafka key를 ES _id로 사용 — 자연스러운 멱등성
// 동일 key의 메시지가 재처리되어도 동일 문서를 덮어쓰기
BulkOperation.of { op ->
    op.index { idx ->
        idx.index("products-v1")
            .id(kafkaRecord.key())   // Kafka key = product ID = ES _id
            .document(document)
    }
}
```

**index vs update 결정 테이블**:

| 전략 | 동작 | 장점 | 단점 | 사용 시점 |
|------|------|------|------|----------|
| `index` (전체 교체) | 문서 전체를 덮어쓰기 | 단순, 빠름, 멱등 | 부분 필드만 변경해도 전체 전송 | Kafka 메시지가 전체 문서를 포함할 때 |
| `update` (부분 갱신) | 지정 필드만 변경 | 네트워크 절약, 동시성 충돌 감소 | doc_as_upsert 설정 필요, scripted update 복잡 | 가격/재고 등 단일 필드만 변경될 때 |

```kotlin
// Optimistic Concurrency Control — 동시 업데이트 충돌 방지
BulkOperation.of { op ->
    op.update { upd ->
        upd.index("products-v1")
            .id(productId)
            .ifSeqNo(expectedSeqNo)           // 읽기 시점 seq_no
            .ifPrimaryTerm(expectedPrimaryTerm) // 읽기 시점 primary_term
            .action { a ->
                a.doc(partialDoc)
                    .docAsUpsert(true)
            }
    }
}
// 충돌 시 VersionConflictEngineException → 재읽기 후 재시도
```

### 1.4 Error Handling: DLQ and Retry

```kotlin
@Configuration
class KafkaErrorHandlingConfig {

    @Bean
    fun kafkaListenerContainerFactory(
        consumerFactory: ConsumerFactory<String, GenericRecord>,
        kafkaTemplate: KafkaTemplate<String, GenericRecord>,
        customErrorHandler: SearchIndexerErrorHandler
    ): ConcurrentKafkaListenerContainerFactory<String, GenericRecord> {
        return ConcurrentKafkaListenerContainerFactory<String, GenericRecord>().apply {
            this.consumerFactory = consumerFactory
            isBatchListener = true
            containerProperties.ackMode = ContainerProperties.AckMode.MANUAL

            // DLQ 설정
            val recoverer = DeadLetterPublishingRecoverer(kafkaTemplate) { record, ex ->
                TopicPartition("${record.topic()}.dlq", record.partition())
            }

            // Exponential backoff 재시도 (1초 → 2초 → 4초, 최대 3회)
            val backOff = ExponentialBackOffWithMaxRetries(3).apply {
                initialInterval = 1000L
                multiplier = 2.0
                maxInterval = 10000L
            }

            setCommonErrorHandler(
                DefaultErrorHandler(recoverer, backOff).apply {
                    // 재시도 불가 예외 분류
                    addNotRetryableExceptions(
                        SerializationException::class.java,
                        DeserializationException::class.java,
                        NonRetryableIndexingException::class.java
                    )
                    setRetryListeners(customErrorHandler)
                }
            )
        }
    }
}

@Component
class SearchIndexerErrorHandler(
    private val meterRegistry: MeterRegistry
) : RetryListener {

    private val logger = LoggerFactory.getLogger(javaClass)
    private val retryCounter = Counter.builder("es.indexer.retry.count")
        .register(meterRegistry)

    override fun failedDelivery(record: ConsumerRecord<*, *>, ex: Exception, deliveryAttempt: Int) {
        logger.warn("Retry attempt {} for record: topic={}, partition={}, offset={}, error={}",
            deliveryAttempt, record.topic(), record.partition(), record.offset(),
            ex.message
        )
        retryCounter.increment()
    }

    override fun recovered(record: ConsumerRecord<*, *>, ex: Exception) {
        // DLQ로 전송 완료
        logger.error("Record sent to DLQ after all retries exhausted: topic={}, partition={}, offset={}",
            record.topic(), record.partition(), record.offset(), ex)
    }

    override fun recoveryFailed(
        record: ConsumerRecord<*, *>, original: Exception, failure: Exception
    ) {
        logger.error("DLQ 전송도 실패. 수동 개입 필요: topic={}, partition={}, offset={}",
            record.topic(), record.partition(), record.offset(), failure)
    }
}

class NonRetryableIndexingException(message: String) : RuntimeException(message)
```

**DLQ 메시지 구조** (자동 추가되는 헤더):

| Header | 설명 | 예시 |
|--------|------|------|
| `kafka_dlt-exception-fqcn` | 예외 클래스 FQCN | `co.elastic...ElasticsearchException` |
| `kafka_dlt-exception-message` | 예외 메시지 | `[400] mapper_parsing_exception` |
| `kafka_dlt-exception-stacktrace` | 스택 트레이스 | (truncated) |
| `kafka_dlt-original-topic` | 원본 토픽 | `product-update-events` |
| `kafka_dlt-original-partition` | 원본 파티션 | `2` |
| `kafka_dlt-original-offset` | 원본 오프셋 | `1048576` |
| `kafka_dlt-original-timestamp` | 원본 타임스탬프 | `1711500000000` |

### 1.5 Consumer Lag Monitoring

```kotlin
@Configuration
class KafkaMetricsConfig {

    @Bean
    fun kafkaConsumerMetrics(): MicrometerConsumerListener<String, GenericRecord> {
        return MicrometerConsumerListener(meterRegistry)
    }
}
```

**핵심 메트릭 및 알림 기준**:

| 메트릭 | Healthy | Warning | Critical | 대응 |
|--------|---------|---------|----------|------|
| `kafka_consumer_records_lag_max` | < 1,000 | 1,000 - 10,000 | > 10,000 | consumer 인스턴스 증설 |
| `kafka_consumer_fetch_rate` | > 1/sec | < 1/sec | < 0.1/sec | fetch 설정 점검 |
| `kafka_consumer_commit_rate` | 안정적 | 불규칙 | 0 | 오프셋 커밋 로직 점검 |
| `es.indexer.bulk.duration` (P99) | < 5s | 5-15s | > 15s | ES 클러스터 상태 확인 |
| `es.indexer.documents.failed` | 0 | > 0 | 급증 | 스키마/매핑 불일치 확인 |

```kotlin
// Backpressure: ES 부하 시 consumer 일시 정지
@Component
class BackpressureManager(
    private val meterRegistry: MeterRegistry
) {
    private val logger = LoggerFactory.getLogger(javaClass)
    private val paused = AtomicBoolean(false)

    @Scheduled(fixedDelay = 10_000)
    fun checkEsBackpressure() {
        val bulkQueueSize = meterRegistry.find("es.bulk.queue.size")
            .gauge()?.value() ?: 0.0
        val bulkP99 = meterRegistry.find("es.indexer.bulk.duration")
            .timer()?.takeSnapshot()?.percentileValues()
            ?.find { it.percentile() == 0.99 }?.value(TimeUnit.SECONDS) ?: 0.0

        if (bulkQueueSize > 1000 || bulkP99 > 15.0) {
            if (!paused.getAndSet(true)) {
                logger.warn("ES backpressure detected. Pausing Kafka consumers. " +
                    "bulkQueueSize={}, bulkP99={}s", bulkQueueSize, bulkP99)
                // KafkaListenerEndpointRegistry를 통해 consumer 일시 정지
                kafkaListenerEndpointRegistry.getListenerContainer("es-indexer")?.pause()
            }
        } else if (paused.getAndSet(false)) {
            logger.info("ES backpressure resolved. Resuming Kafka consumers.")
            kafkaListenerEndpointRegistry.getListenerContainer("es-indexer")?.resume()
        }
    }
}
```

### 1.6 Schema Evolution

```yaml
# Schema Registry 클라이언트 설정
spring:
  kafka:
    consumer:
      properties:
        schema.registry.url: ${SCHEMA_REGISTRY_URL}
        basic.auth.credentials.source: USER_INFO
        basic.auth.user.info: ${SCHEMA_REGISTRY_USER}:${SCHEMA_REGISTRY_PASSWORD}
        specific.avro.reader: false    # GenericRecord 사용 시 false
```

```kotlin
// Forward/Backward compatibility 핸들링
@Component
class SchemaEvolutionHandler {

    private val logger = LoggerFactory.getLogger(javaClass)

    /**
     * GenericRecord 기반으로 스키마 변경에 유연하게 대응.
     * - 새 필드 추가(forward compatible): 기존 consumer는 무시
     * - 필드 삭제(backward compatible): default 값으로 처리
     */
    fun convertWithSchemaEvolution(record: GenericRecord): Map<String, Any?> {
        val schema = record.schema
        val document = mutableMapOf<String, Any?>()

        // 알려진 필드는 명시적으로 매핑
        document["title"] = record.getOrDefault("title", null)?.toString()
        document["price"] = record.getOrDefault("price", 0)
        document["category"] = record.getOrDefault("category", null)?.toString()
        document["brand"] = record.getOrDefault("brand", null)?.toString()

        // 새로 추가된 필드 자동 감지 (forward compatibility)
        val knownFields = setOf("title", "price", "category", "brand", "status", "updated_at")
        schema.fields
            .filter { it.name() !in knownFields }
            .forEach { field ->
                val value = record.get(field.name())
                if (value != null) {
                    logger.debug("Unknown field detected from schema evolution: {}", field.name())
                    document[field.name()] = value.toString()
                }
            }

        return document
    }

    private fun GenericRecord.getOrDefault(field: String, default: Any?): Any? {
        return try {
            get(field)
        } catch (e: AvroRuntimeException) {
            default
        }
    }
}
```

**Avro GenericRecord vs SpecificRecord 선택 기준**:

| 기준 | GenericRecord | SpecificRecord |
|------|--------------|----------------|
| 스키마 변경 대응 | 유연 — 런타임 처리 | 재컴파일 필요 |
| 타입 안전성 | 낮음 — 필드명 문자열 | 높음 — 컴파일 타임 체크 |
| 성능 | 약간 느림 | 약간 빠름 |
| 코드 가독성 | 낮음 — get("field") 반복 | 높음 — record.title |
| **검색팀 권장** | **O — 스키마가 DE 관리이므로** | 스키마 안정적일 때만 |

### 1.7 Kafka Connect ES Sink vs Custom Consumer

| 기준 | Kafka Connect ES Sink | Custom Consumer (Spring-Kafka) |
|------|----------------------|-------------------------------|
| 셋업 복잡도 | 낮음 — 설정 파일만 | 높음 — 코드 작성 필요 |
| 데이터 변환 | SMT 한정 (제한적) | 자유로운 Kotlin 변환 로직 |
| 에러 처리 | DLQ 기본 제공, 커스텀 제한 | 완전한 제어 (retry, 부분 재시도) |
| Document ID 제어 | 제한적 (`key.ignore`, `id.strategy`) | 완전 제어 (`record.key()` 등) |
| 멀티 인덱스 라우팅 | `topic.index.map` 설정 | 레코드별 동적 라우팅 가능 |
| 모니터링 | Connect REST API, JMX | Micrometer 통합, 커스텀 메트릭 |
| 운영 주체 | **DE 팀** (Connect 클러스터) | **검색팀** (서비스 내 embedded) |
| **권장 시점** | 단순 1:1 매핑, 변환 불필요 시 | 복잡한 변환, 멀티 인덱스, 세밀한 에러 처리 |

> **참고**: Kafka Connect 클러스터는 DE 팀 소관입니다. 검색팀이 ES Sink Connector를 사용하려면 DE 팀에 connector 배포를 요청해야 합니다. 변환 로직이 복잡하면 Custom Consumer를 자체 운영하는 것이 더 민첩합니다.

### 1.8 Anti-Patterns

| Anti-Pattern | 문제 | Fix | Severity |
|-------------|------|-----|----------|
| `enable-auto-commit: true` 상태로 ES 인덱싱 | ES 실패 시 오프셋 이미 커밋 → 데이터 유실 | 반드시 `false` + `MANUAL` ack | **Critical** |
| 건별 ES index 요청 | N건 = N번 HTTP → 극심한 성능 저하 | `bulk` API로 배치 처리 | **Critical** |
| DLQ 미설정 | 처리 불가 메시지가 무한 재시도 → consumer 정지 | `DeadLetterPublishingRecoverer` 설정 | **High** |
| `BulkResponse.errors()` 미확인 | 부분 실패 감지 못함 → 데이터 불일치 | 항상 `errors()` 체크, 실패 건 로깅 | **High** |
| `max.poll.interval.ms` 너무 짧게 설정 | bulk 처리 시간 초과 → 리밸런싱 폭풍 | bulk 처리 최대 시간의 2배 이상 설정 | **High** |
| 고처리량 토픽에 단일 consumer 인스턴스 | lag 증가, 처리 지연 | `concurrency` 또는 인스턴스 증설 | **Medium** |
| Schema Registry URL 하드코딩 | 환경별 설정 변경 불가 | 환경 변수(`${SCHEMA_REGISTRY_URL}`) 사용 | **Medium** |

## 2. Apache Iceberg Integration

### 2.1 Iceberg as Source of Truth

Apache Iceberg 테이블은 DE 팀이 소유하고 관리합니다. 검색팀은 Iceberg를 데이터의 정합성 있는 소스(source of truth)로 활용하여 전체 재인덱싱, 증분 동기화, 데이터 검증을 수행합니다.

```
┌─────────────┐     ┌──────────────┐     ┌─────────────────┐
│  원천 시스템  │ ──→ │  Iceberg     │ ──→ │  Spark Job      │ ──→ ES
│  (DB/Events) │     │  (DE 관리)    │     │  (검색팀 실행)    │
└─────────────┘     └──────────────┘     └─────────────────┘
```

### 2.2 Full Reindexing from Iceberg via Spark SQL

```sql
-- Spark SQL: Iceberg 테이블에서 전체 데이터 읽기
SELECT
    product_id,
    title,
    description,
    price,
    category_code,
    brand_name,
    status,
    updated_at
FROM catalog.db.products
WHERE status = 'active'
  AND updated_at >= '2024-01-01'
```

```kotlin
// Spark + Kotlin: Iceberg → ES 전체 재인덱싱 Job
class FullReindexJob {

    fun run(spark: SparkSession, targetIndex: String) {
        val df = spark.sql("""
            SELECT
                product_id,
                title,
                description,
                price,
                category_code AS category,
                brand_name AS brand,
                status,
                updated_at
            FROM catalog.db.products
            WHERE status = 'active'
        """.trimIndent())

        df.write()
            .format("org.elasticsearch.spark.sql")
            .option("es.nodes", System.getenv("ES_NODES"))
            .option("es.port", "9200")
            .option("es.mapping.id", "product_id")
            .option("es.write.operation", "index")
            .option("es.batch.size.bytes", "5mb")
            .option("es.batch.size.entries", "1000")
            .option("es.batch.write.retry.count", "3")
            .option("es.batch.write.retry.wait", "30s")
            .option("es.nodes.wan.only", "true")
            .mode(SaveMode.Append)
            .save(targetIndex)

        logger.info("Full reindex completed: target={}, rows={}",
            targetIndex, df.count())
    }
}
```

### 2.3 Incremental Indexing via Snapshot Diff

```sql
-- Iceberg snapshot 간 변경분 조회 (증분 인덱싱의 핵심)
-- snapshot_id는 Iceberg 메타데이터에서 획득
SELECT *
FROM catalog.db.products.changes
BETWEEN snapshot_id_1 AND snapshot_id_2;
```

```kotlin
// Iceberg 증분 동기화 Job
class IncrementalSyncJob {

    fun run(spark: SparkSession, fromSnapshotId: Long, toSnapshotId: Long) {
        // 1. Snapshot diff 조회
        val changes = spark.sql("""
            SELECT
                product_id,
                title,
                description,
                price,
                category_code AS category,
                brand_name AS brand,
                status,
                updated_at,
                _change_type
            FROM catalog.db.products.changes
            BETWEEN $fromSnapshotId AND $toSnapshotId
        """.trimIndent())

        // 2. 변경 유형별 분리 처리
        val upserts = changes.filter("_change_type IN ('insert', 'update_after')")
        val deletes = changes.filter("_change_type = 'delete'")

        // 3. Upsert → ES index
        if (upserts.count() > 0) {
            upserts.drop("_change_type")
                .write()
                .format("org.elasticsearch.spark.sql")
                .option("es.mapping.id", "product_id")
                .option("es.write.operation", "upsert")
                .option("es.batch.size.bytes", "5mb")
                .mode(SaveMode.Append)
                .save("products-v1")
        }

        // 4. Delete → ES delete
        if (deletes.count() > 0) {
            val deleteIds = deletes.select("product_id")
                .collectAsList()
                .map { it.getString(0) }
            bulkDeleteFromEs(deleteIds)
        }

        // 5. 처리한 snapshot ID 저장 (다음 실행 시 시작점)
        saveCheckpoint(toSnapshotId)

        logger.info("Incremental sync: upserts={}, deletes={}, from={}, to={}",
            upserts.count(), deletes.count(), fromSnapshotId, toSnapshotId)
    }
}
```

### 2.4 Iceberg Metadata Queries

```sql
-- 현재 스냅샷 목록 조회
SELECT * FROM catalog.db.products.snapshots ORDER BY committed_at DESC LIMIT 10;

-- 스냅샷 히스토리 (시간순)
SELECT * FROM catalog.db.products.history;

-- 매니페스트 파일 목록 (파티션 정보 포함)
SELECT * FROM catalog.db.products.manifests;

-- Time travel: 특정 시점 데이터 조회 (데이터 검증용)
SELECT COUNT(*) as total, MAX(updated_at) as latest
FROM catalog.db.products
TIMESTAMP AS OF '2024-03-01 00:00:00';

-- 특정 스냅샷 기준 데이터 조회
SELECT COUNT(*) FROM catalog.db.products VERSION AS OF 1234567890;
```

## 3. Spark for Batch Indexing

### 3.1 elasticsearch-spark Connector 설정

```kotlin
// SparkSession 설정 (검색팀 배치 Job)
val spark = SparkSession.builder()
    .appName("search-batch-indexer")
    .config("spark.es.nodes", System.getenv("ES_NODES"))
    .config("spark.es.port", "9200")
    .config("spark.es.net.http.auth.user", System.getenv("ES_USER"))
    .config("spark.es.net.http.auth.pass", System.getenv("ES_PASSWORD"))
    .config("spark.es.nodes.wan.only", "true")
    .config("spark.es.batch.size.bytes", "5mb")
    .config("spark.es.batch.size.entries", "1000")
    .config("spark.es.batch.write.retry.count", "3")
    .config("spark.es.batch.write.retry.wait", "30s")
    .config("spark.es.scroll.size", "5000")
    .config("spark.sql.catalog.catalog", "org.apache.iceberg.spark.SparkCatalog")
    .config("spark.sql.catalog.catalog.type", "hive")
    .getOrCreate()
```

**elasticsearch-spark 주요 설정 옵션**:

| 옵션 | 설명 | 권장 값 |
|------|------|---------|
| `es.mapping.id` | ES 문서 `_id`로 사용할 DataFrame 컬럼 | `product_id` |
| `es.write.operation` | 쓰기 모드 (`index`, `create`, `update`, `upsert`) | `index` (전체), `upsert` (증분) |
| `es.batch.size.bytes` | bulk 요청 최대 바이트 | `5mb` |
| `es.batch.size.entries` | bulk 요청 최대 건수 | `1000` |
| `es.batch.write.retry.count` | bulk 실패 시 재시도 횟수 | `3` |
| `es.batch.write.retry.wait` | 재시도 간 대기 시간 | `30s` |
| `es.nodes.wan.only` | WAN 환경 (load balancer 경유) | `true` |
| `es.scroll.size` | ES → Spark 읽기 시 scroll 크기 | `5000` |

### 3.2 DataFrame → ES Document 매핑

```kotlin
// Iceberg 테이블의 컬럼명 → ES 매핑 필드명 변환
val transformed = spark.sql("SELECT * FROM catalog.db.products WHERE status = 'active'")
    .withColumnRenamed("product_id", "id")
    .withColumnRenamed("category_code", "category")
    .withColumnRenamed("brand_name", "brand")
    .withColumn("indexed_at", current_timestamp())
    .withColumn("search_keywords",
        concat_ws(" ", col("title"), col("description"), col("brand")))
    .drop("internal_memo", "raw_data")

transformed.write()
    .format("org.elasticsearch.spark.sql")
    .option("es.mapping.id", "id")
    .option("es.write.operation", "index")
    .mode(SaveMode.Append)
    .save("products-v1")
```

### 3.3 Resource Estimation

| 데이터 볼륨 | Executor 수 | Executor 메모리 | 예상 소요 시간 | 비고 |
|------------|------------|----------------|-------------|------|
| ~1M docs (< 1GB) | 2 | 2GB | 5-10분 | 소규모 인덱스 |
| ~10M docs (5-10GB) | 4-6 | 4GB | 20-40분 | 중규모, 일반적 |
| ~50M docs (20-50GB) | 8-12 | 4GB | 1-2시간 | 대규모, ES shard 수 고려 |
| ~100M+ docs (50GB+) | 16-20 | 8GB | 2-4시간 | throttling 설정 필수 |

> **참고**: Spark 클러스터 리소스는 DE 팀에 요청합니다. 리소스 요청 시 위 테이블을 기준으로 산정하세요.

### 3.4 Streaming vs Batch 결정 기준

| 기준 | Real-time (Kafka Consumer) | Batch (Spark) |
|------|---------------------------|---------------|
| 데이터 신선도 | < 1분 | 수 시간 ~ 일 단위 |
| 사용 사례 | 실시간 검색 반영 (가격, 재고) | 전체 재인덱싱, 데이터 보정 |
| 복잡도 | 중간 — consumer 코드 관리 | 낮음 — SQL 기반 |
| 리소스 모델 | 상시 가동 (pod) | 실행 시에만 (job) |
| 장애 영향 | consumer 장애 → lag 누적 | job 실패 → 재실행 |
| 데이터 정합성 | eventual consistency | 스냅샷 기반 strong consistency |

### 3.5 Spark Job 모니터링

```kotlin
// Spark Listener로 Job 상태 추적
class IndexingJobListener : SparkListener() {
    override fun onJobEnd(jobEnd: SparkListenerJobEnd) {
        when (jobEnd.jobResult) {
            is JobSucceeded -> {
                logger.info("Spark job {} succeeded", jobEnd.jobId)
                metrics.counter("spark.job.success").increment()
            }
            is JobFailed -> {
                val failure = jobEnd.jobResult as JobFailed
                logger.error("Spark job {} failed: {}", jobEnd.jobId, failure.exception.message)
                metrics.counter("spark.job.failure").increment()
                // 알림 전송
                alertService.sendSlack(
                    channel = "#search-alert",
                    message = "Batch indexing job failed: ${failure.exception.message}"
                )
            }
        }
    }
}

spark.sparkContext.addSparkListener(IndexingJobListener())
```

## 4. Trino for Search Analytics

### 4.1 Trino ES Connector와 제한사항

Trino의 Elasticsearch connector는 **읽기 전용**이며 검색 로그 분석에 활용합니다.

| 기능 | 지원 여부 | 비고 |
|------|----------|------|
| SELECT (기본 쿼리) | O | |
| WHERE (필터) | O | pushdown 지원 |
| GROUP BY / 집계 | O | ES aggregation으로 pushdown |
| JOIN | 제한적 | ES 간 join 불가, Iceberg와 cross-catalog join 가능 |
| 서브쿼리 | O | |
| WRITE / UPDATE | X | 읽기 전용 |
| Full-text search | 제한적 | `match` 쿼리 미지원, keyword 필터만 |

### 4.2 검색 로그 분석 쿼리

```sql
-- Top 검색 키워드 (일별)
SELECT
    search_keyword,
    COUNT(*) AS search_count,
    COUNT(DISTINCT user_id) AS unique_users,
    AVG(result_count) AS avg_results
FROM es.search_logs.query_log
WHERE log_date = CURRENT_DATE - INTERVAL '1' DAY
GROUP BY search_keyword
ORDER BY search_count DESC
LIMIT 100;
```

```sql
-- Zero-result 검색어 분석 (검색 품질 핵심 지표)
SELECT
    search_keyword,
    COUNT(*) AS zero_result_count,
    COUNT(DISTINCT user_id) AS affected_users
FROM es.search_logs.query_log
WHERE result_count = 0
  AND log_date >= CURRENT_DATE - INTERVAL '7' DAY
GROUP BY search_keyword
HAVING COUNT(*) >= 10
ORDER BY zero_result_count DESC
LIMIT 50;
```

```sql
-- Slow query 분석 (P95 응답 시간 초과)
SELECT
    search_keyword,
    COUNT(*) AS query_count,
    AVG(response_time_ms) AS avg_response_ms,
    APPROX_PERCENTILE(response_time_ms, 0.95) AS p95_response_ms,
    APPROX_PERCENTILE(response_time_ms, 0.99) AS p99_response_ms,
    MAX(response_time_ms) AS max_response_ms
FROM es.search_logs.query_log
WHERE log_date >= CURRENT_DATE - INTERVAL '1' DAY
GROUP BY search_keyword
HAVING APPROX_PERCENTILE(response_time_ms, 0.95) > 500
ORDER BY p95_response_ms DESC
LIMIT 30;
```

### 4.3 CTR / Conversion 분석

```sql
-- 검색 키워드별 CTR (Click-Through Rate)
SELECT
    q.search_keyword,
    COUNT(DISTINCT q.search_session_id) AS total_searches,
    COUNT(DISTINCT c.search_session_id) AS searches_with_click,
    ROUND(
        CAST(COUNT(DISTINCT c.search_session_id) AS DOUBLE)
        / NULLIF(COUNT(DISTINCT q.search_session_id), 0) * 100,
        2
    ) AS ctr_percent,
    AVG(c.click_position) AS avg_click_position
FROM es.search_logs.query_log q
LEFT JOIN iceberg.analytics.search_clicks c
    ON q.search_session_id = c.search_session_id
WHERE q.log_date >= CURRENT_DATE - INTERVAL '7' DAY
GROUP BY q.search_keyword
HAVING COUNT(DISTINCT q.search_session_id) >= 100
ORDER BY ctr_percent ASC
LIMIT 50;
```

```sql
-- 검색 → 구매 전환율 분석
SELECT
    q.search_keyword,
    COUNT(DISTINCT q.search_session_id) AS searches,
    COUNT(DISTINCT o.order_id) AS conversions,
    ROUND(
        CAST(COUNT(DISTINCT o.order_id) AS DOUBLE)
        / NULLIF(COUNT(DISTINCT q.search_session_id), 0) * 100,
        2
    ) AS conversion_rate_percent,
    SUM(o.order_amount) AS total_revenue
FROM es.search_logs.query_log q
LEFT JOIN iceberg.analytics.search_clicks c
    ON q.search_session_id = c.search_session_id
LEFT JOIN iceberg.commerce.orders o
    ON c.product_id = o.product_id
    AND o.order_date BETWEEN q.log_date AND q.log_date + INTERVAL '7' DAY
WHERE q.log_date >= CURRENT_DATE - INTERVAL '30' DAY
GROUP BY q.search_keyword
HAVING COUNT(DISTINCT q.search_session_id) >= 50
ORDER BY conversion_rate_percent DESC
LIMIT 30;
```

### 4.4 A/B Test 결과 분석

```sql
-- A/B 테스트: 검색 알고리즘 비교 분석
WITH test_metrics AS (
    SELECT
        experiment_group,
        COUNT(DISTINCT search_session_id) AS sessions,
        AVG(result_count) AS avg_results,
        AVG(response_time_ms) AS avg_response_ms,
        SUM(CASE WHEN click_count > 0 THEN 1 ELSE 0 END) AS sessions_with_click,
        AVG(CASE WHEN click_count > 0 THEN first_click_position END) AS avg_first_click_pos
    FROM es.search_logs.query_log
    WHERE experiment_id = 'search-algo-v2-test'
      AND log_date >= CURRENT_DATE - INTERVAL '14' DAY
    GROUP BY experiment_group
)
SELECT
    experiment_group,
    sessions,
    avg_results,
    ROUND(avg_response_ms, 1) AS avg_response_ms,
    ROUND(
        CAST(sessions_with_click AS DOUBLE) / sessions * 100, 2
    ) AS ctr_percent,
    ROUND(avg_first_click_pos, 2) AS avg_first_click_pos
FROM test_metrics
ORDER BY experiment_group;
```

## 5. Cross-Cutting Concerns

### 5.1 Data Freshness SLA

| 등급 | SLA | 소스 | 파이프라인 | 사용 사례 |
|------|-----|------|----------|----------|
| Real-time | < 1분 | Kafka topic | Spring-Kafka consumer | 가격 변경, 재고 변동, 상품 상태 |
| Near-real-time | < 15분 | Kafka topic (배치) | Kafka consumer (aggregation) | 리뷰 수, 평점 집계 |
| Batch | < 24시간 | Iceberg table | Spark job (스케줄) | 전체 재인덱싱, 데이터 보정, 신규 필드 추가 |

### 5.2 Schema Consistency Checklist

파이프라인 소스 스키마와 ES 매핑 간 불일치는 인덱싱 실패의 가장 흔한 원인입니다.

| 체크 항목 | 검증 방법 | 자동화 |
|----------|----------|--------|
| Avro 스키마 필드 ↔ ES mapping 필드명 일치 | Schema Registry REST API + ES Mapping API 비교 | CI pipeline |
| 타입 호환성 (Avro `long` → ES `long`) | 타입 매핑 테이블 참조 | unit test |
| nullable 필드의 ES 기본값 | Avro default + ES null_value 확인 | 코드 리뷰 |
| 신규 필드 추가 시 ES dynamic mapping 방지 | `"dynamic": "strict"` 설정 확인 | index template |
| deprecated 필드 제거 시점 동기화 | Avro 스키마 changelog + ES alias 전환 | 수동 (체크리스트) |

### 5.3 Full Reindex vs Incremental 결정 기준

| 트리거 | 전략 | 방법 | 예상 소요 |
|--------|------|------|----------|
| ES 매핑 변경 (analyzer, type) | **Full reindex** | Spark job → new index → alias switch | 1-4시간 |
| 신규 필드 추가 (기존 호환) | **Full reindex** | 기존 문서에 값이 없으므로 전체 갱신 | 1-4시간 |
| 일반 데이터 업데이트 | **Incremental** | Kafka consumer (실시간) | < 1분 |
| 데이터 보정 / 정합성 복구 | **Incremental** (Iceberg diff) | Spark job (snapshot diff) | 10-30분 |
| 인덱스 shard 수 변경 | **Full reindex** | 새 인덱스 생성 → reindex → alias | 1-4시간 |
| ES 버전 업그레이드 | **Full reindex** | Rolling 또는 blue-green | 사전 계획 |

### 5.4 Pipeline Failure Recovery

```kotlin
// 파이프라인 실패 복구 패턴
@Component
class PipelineRecoveryService(
    private val esClient: ElasticsearchClient,
    private val kafkaAdmin: AdminClient
) {
    private val logger = LoggerFactory.getLogger(javaClass)

    /**
     * Consumer lag가 SLA 초과 시 복구 전략 결정
     */
    fun assessAndRecover(topicPartition: TopicPartition, currentLag: Long) {
        when {
            // Case 1: 소규모 lag — consumer 자체 catch-up 대기
            currentLag < 10_000 -> {
                logger.info("Minor lag detected ({}). Consumer will catch up.", currentLag)
            }
            // Case 2: 중규모 lag — consumer 인스턴스 일시 증설
            currentLag in 10_000..100_000 -> {
                logger.warn("Moderate lag detected ({}). Consider scaling consumers.", currentLag)
                alertService.notify("Consumer lag warning: $currentLag on $topicPartition")
            }
            // Case 3: 대규모 lag — Spark 배치로 gap 채우기
            currentLag > 100_000 -> {
                logger.error("Severe lag detected ({}). Triggering batch recovery.", currentLag)
                alertService.notify("CRITICAL: Consumer lag $currentLag on $topicPartition")
                // Iceberg snapshot diff로 누락분 배치 인덱싱
                triggerBatchRecovery(topicPartition)
            }
        }
    }

    /**
     * DLQ 메시지 재처리
     */
    fun reprocessDlq(dlqTopic: String, maxRecords: Int = 1000) {
        logger.info("Starting DLQ reprocessing: topic={}, maxRecords={}", dlqTopic, maxRecords)

        val consumer = createDlqConsumer(dlqTopic)
        var processed = 0

        try {
            while (processed < maxRecords) {
                val records = consumer.poll(Duration.ofSeconds(5))
                if (records.isEmpty) break

                records.forEach { record ->
                    try {
                        reindexSingleRecord(record)
                        processed++
                    } catch (e: Exception) {
                        logger.error("DLQ reprocess failed for offset {}: {}",
                            record.offset(), e.message)
                    }
                }
                consumer.commitSync()
            }
        } finally {
            consumer.close()
            logger.info("DLQ reprocessing completed: {}/{} records", processed, maxRecords)
        }
    }
}
```

### 5.5 Monitoring: 검색팀 vs DE팀 책임 경계

| 모니터링 대상 | 검색팀 책임 | DE팀 에스컬레이션 |
|-------------|-----------|----------------|
| **Kafka consumer lag** | O — 직접 모니터링 및 대응 | lag 원인이 broker 문제일 때 |
| **ES indexing throughput/error** | O — bulk 성능, 실패율 | |
| **Kafka broker health** | | O — broker 장애, ISR 부족 |
| **Kafka topic partition 수 변경** | 요청만 | O — 파티션 증설 실행 |
| **Schema Registry** | 스키마 호환성 체크 | O — Registry 서비스 운영 |
| **Spark cluster resource** | Job 리소스 요청 | O — 클러스터 용량 관리 |
| **Spark job 성공/실패** | O — job 실행 및 모니터링 | 클러스터 문제 시 |
| **Trino query performance** | O — 쿼리 최적화 | O — 클러스터 성능 이슈 |
| **Iceberg table schema change** | 영향도 분석, consumer 대응 | O — 스키마 변경 사전 공지 |
| **데이터 정합성 (ES vs Iceberg)** | O — 검증 및 복구 | 원천 데이터 이슈 시 |

```yaml
# Grafana alert rules (검색팀 관리 대시보드)
groups:
  - name: search-pipeline-alerts
    rules:
      - alert: KafkaConsumerLagHigh
        expr: kafka_consumer_records_lag_max{group="search-es-indexer"} > 10000
        for: 5m
        labels:
          severity: warning
          team: search
        annotations:
          summary: "Kafka consumer lag > 10K for 5 minutes"
          runbook: "1) consumer 인스턴스 상태 확인 2) ES bulk 응답 시간 확인 3) consumer 증설 검토"

      - alert: KafkaConsumerLagCritical
        expr: kafka_consumer_records_lag_max{group="search-es-indexer"} > 100000
        for: 3m
        labels:
          severity: critical
          team: search
        annotations:
          summary: "Kafka consumer lag > 100K — batch recovery 필요"
          runbook: "1) Spark batch recovery 트리거 2) DE팀 공유 3) 원인 분석"

      - alert: EsBulkIndexingFailureRate
        expr: rate(es_indexer_documents_failed_total[5m]) > 10
        for: 3m
        labels:
          severity: warning
          team: search
        annotations:
          summary: "ES bulk indexing failure rate > 10/s"
          runbook: "1) DLQ 확인 2) ES 매핑 불일치 확인 3) ES 클러스터 상태 확인"

      - alert: EsBulkLatencyHigh
        expr: histogram_quantile(0.99, rate(es_indexer_bulk_duration_seconds_bucket[5m])) > 15
        for: 5m
        labels:
          severity: warning
          team: search
        annotations:
          summary: "ES bulk P99 latency > 15s"
          runbook: "1) ES thread_pool.write 큐 확인 2) bulk 크기 축소 검토 3) backpressure 작동 확인"
```

---

**Remember**: 검색팀은 파이프라인 인프라의 '소비자'입니다. Kafka broker, Spark cluster, Trino cluster 설정은 DE팀 소관이지만, consumer 설정, 인덱싱 로직, 모니터링은 검색팀의 책임입니다. 오프셋 커밋은 반드시 ES 인덱싱 성공 후에, bulk API는 항상 배치로, DLQ는 반드시 설정하세요.
