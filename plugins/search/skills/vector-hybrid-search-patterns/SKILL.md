---
name: vector-hybrid-search-patterns
description: Use this skill when designing vector search (kNN), semantic search (ELSER/embeddings), or hybrid search (RRF) with Elasticsearch 8.x. Covers dense_vector mappings, HNSW tuning, embedding model selection for Korean, RRF fusion, and Kotlin client implementation patterns.
---

# Vector & Hybrid Search Patterns

벡터 검색(kNN), 시맨틱 검색, 하이브리드 검색(BM25 + kNN, RRF)을 다루는 종합 가이드입니다.

## When to Activate

- dense_vector 필드 매핑 설계 또는 변경 시
- kNN (approximate or exact) 검색 쿼리 작성 시
- 임베딩 모델 선택 또는 서빙 파이프라인 구축 시
- BM25 + kNN 하이브리드 검색 설계 시 (RRF)
- ELSER (sparse vector) 적용 검토 시
- 벡터 인덱스 성능 튜닝 (HNSW 파라미터, 양자화) 시
- 한국어 텍스트 임베딩 모델 평가 시

## 1. Dense Vector Field Configuration

### Similarity Metrics

| Metric | 값 범위 | 정규화 필요 | 적합 케이스 |
|--------|---------|-----------|------------|
| `cosine` | -1 ~ 1 | 불필요 (자동 정규화) | 대부분의 텍스트 임베딩 (기본 권장) |
| `dot_product` | -Inf ~ +Inf | **필수** (단위 벡터) | 사전 정규화된 벡터, 성능 최적 |
| `l2_norm` | 0 ~ +Inf (거리) | 불필요 | 이미지 임베딩, 좌표 기반 유사도 |
| `max_inner_product` | -Inf ~ +Inf | 불필요 | 비정규화 벡터의 내적 (magnitude 반영) |

**원칙**: 임베딩 모델이 정규화된 벡터를 출력하면 `dot_product` (cosine보다 연산 빠름), 그렇지 않으면 `cosine` 사용.

### Full Mapping Example

```json
PUT /products-vector
{
  "settings": {
    "number_of_shards": 3,
    "number_of_replicas": 1
  },
  "mappings": {
    "properties": {
      "title": {
        "type": "text",
        "analyzer": "nori_standard"
      },
      "title_vector": {
        "type": "dense_vector",
        "dims": 768,
        "index": true,
        "similarity": "cosine",
        "index_options": {
          "type": "hnsw",
          "m": 16,
          "ef_construction": 200
        }
      },
      "category": {
        "type": "keyword"
      },
      "price": {
        "type": "integer"
      }
    }
  }
}
```

### HNSW Parameter Tuning

| Parameter | 기본값 | 역할 | 튜닝 가이드 |
|-----------|-------|------|------------|
| `m` | 16 | 노드당 연결 수 | 높을수록 recall 증가, 메모리/인덱싱 비용 증가 |
| `ef_construction` | 100 | 인덱스 빌드 시 탐색 폭 | 높을수록 그래프 품질 향상, 인덱싱 속도 감소 |
| `ef` (검색 시) | k 이상 | 검색 시 탐색 폭 | `num_candidates`로 제어, 높을수록 recall 향상 |

| 시나리오 | m | ef_construction | 설명 |
|---------|---|----------------|------|
| 빠른 프로토타이핑 | 8 | 100 | 인덱싱 빠르지만 recall 낮음 |
| **프로덕션 균형** (권장) | **16** | **200** | recall과 성능의 최적 균형 |
| 높은 recall 요구 | 32 | 400 | recall 극대화, 메모리 2배 |
| 초대규모 (>100M docs) | 16 | 200 | m 유지하되 양자화 병행 |

### Quantization Strategies

| 타입 | 벡터당 메모리 (768d) | 메모리 절감 | Recall 영향 | 적합 시점 |
|------|---------------------|-----------|------------|----------|
| `float32` (기본) | 3,072 bytes | - | 기준 | < 5M docs |
| `int8_hnsw` | 768 bytes + 오버헤드 | ~75% 절감 | -0.5~1% | 5M ~ 50M docs |
| `int4_hnsw` | 384 bytes + 오버헤드 | ~87% 절감 | -1~3% | 50M ~ 200M docs |
| `bbq_hnsw` | ~96 bytes + 오버헤드 | ~97% 절감 | -2~5% | > 200M docs, 비용 민감 |

### int8_hnsw Mapping Example

```json
PUT /products-vector-quantized
{
  "mappings": {
    "properties": {
      "title_vector": {
        "type": "dense_vector",
        "dims": 768,
        "index": true,
        "similarity": "cosine",
        "index_options": {
          "type": "int8_hnsw",
          "m": 16,
          "ef_construction": 200,
          "confidence_interval": 0.99
        }
      }
    }
  }
}
```

**`confidence_interval`**: 양자화 시 원본 벡터로 재스코어링할 비율. `0.99`면 상위 99% 후보를 원본으로 재검증. 높을수록 recall 좋지만 느림.

### Memory Formula

```
벡터 메모리 (per doc) = dims * 4 bytes (float32) + m * 8 bytes (HNSW edges)

예시 (768d, m=16, 10M docs):
  벡터:  768 * 4 = 3,072 bytes
  HNSW:  16 * 8 = 128 bytes
  합계:  3,200 bytes/doc
  총:    3,200 * 10,000,000 = 32 GB

int8_hnsw 적용 시:
  벡터:  768 * 1 = 768 bytes
  HNSW:  16 * 8 = 128 bytes
  합계:  896 bytes/doc
  총:    896 * 10,000,000 = 8.96 GB (약 72% 절감)
```

## 2. kNN Query Patterns

### Approximate kNN Query

```json
GET /products-vector/_search
{
  "knn": {
    "field": "title_vector",
    "query_vector": [0.12, -0.34, 0.56, ...],
    "k": 10,
    "num_candidates": 100
  },
  "_source": ["title", "price", "category"]
}
```

### kNN with Pre-Filter

```json
GET /products-vector/_search
{
  "knn": {
    "field": "title_vector",
    "query_vector": [0.12, -0.34, 0.56, ...],
    "k": 10,
    "num_candidates": 100,
    "filter": {
      "bool": {
        "must": [
          { "term": { "category": "electronics" } },
          { "range": { "price": { "gte": 10000, "lte": 500000 } } }
        ]
      }
    }
  },
  "_source": ["title", "price", "category"]
}
```

**Pre-filter 동작**: 필터 조건에 맞는 문서만 대상으로 kNN 검색 수행. 필터가 너무 좁으면 후보 부족으로 recall 저하 가능.

### Exact kNN via script_score

```json
GET /products-vector/_search
{
  "query": {
    "script_score": {
      "query": {
        "bool": {
          "filter": [
            { "term": { "category": "electronics" } }
          ]
        }
      },
      "script": {
        "source": "cosineSimilarity(params.query_vector, 'title_vector') + 1.0",
        "params": {
          "query_vector": [0.12, -0.34, 0.56, ...]
        }
      }
    }
  },
  "size": 10
}
```

**주의**: `cosineSimilarity`는 -1~1 범위이므로 `+1.0`을 더해 양수 스코어로 변환 (ES는 음수 스코어 비허용).

### Approximate vs Exact kNN

| 기준 | Approximate kNN (HNSW) | Exact kNN (script_score) |
|------|----------------------|------------------------|
| 속도 | O(log N), 매우 빠름 | O(N), 문서 수 비례 |
| Recall | ~95-99% (파라미터 의존) | 100% (정확) |
| 인덱스 필요 | `index: true` 필수 | `index: false` 가능 |
| 필터 결합 | pre-filter 지원 | query context에서 filter 결합 |
| 적합 케이스 | 대규모 (>100K docs) 실시간 검색 | 소규모 (<10K) 또는 정밀도 최우선 |
| 메모리 | HNSW 그래프 메모리 추가 | 벡터 저장만 |

### Multi-Vector kNN

여러 벡터 필드를 동시에 검색하여 결합:

```json
GET /products-vector/_search
{
  "knn": [
    {
      "field": "title_vector",
      "query_vector": [0.12, -0.34, ...],
      "k": 10,
      "num_candidates": 100,
      "boost": 1.5
    },
    {
      "field": "description_vector",
      "query_vector": [0.22, -0.11, ...],
      "k": 10,
      "num_candidates": 100,
      "boost": 0.5
    }
  ],
  "_source": ["title", "price", "category"]
}
```

### num_candidates Rule of Thumb

| 시나리오 | num_candidates | k | 비율 | Recall 기대값 |
|---------|---------------|---|------|-------------|
| 빠른 응답 우선 | 50 | 10 | 5x | ~90% |
| **프로덕션 권장** | **100** | **10** | **10x** | **~95-97%** |
| 높은 recall | 200 | 10 | 20x | ~98-99% |
| 필터 적용 시 | 200-500 | 10 | 20-50x | 필터 selectivity에 따라 |

**원칙**: `num_candidates >= k * 10`. 필터가 있으면 필터 통과율에 반비례하여 증가. 예: 필터 통과율 10%이면 `num_candidates = k * 100`.

## 3. Embedding Models for Korean

### Model Comparison

| 모델 | dims | 한국어 품질 | 라이선스 | 비고 |
|------|------|-----------|---------|------|
| `multilingual-e5-large` | 1024 | 우수 | MIT | 다국어 최강, 프로덕션 권장 |
| `multilingual-e5-base` | 768 | 좋음 | MIT | 성능/비용 균형, 가장 많이 사용 |
| `multilingual-e5-small` | 384 | 양호 | MIT | 리소스 제한 환경 |
| `BGE-M3` | 1024 | 우수 | MIT | Dense + Sparse + ColBERT 동시 지원 |
| `KoSimCSE-roberta` | 768 | 매우 우수 | CC-BY-SA-4.0 | 한국어 특화, STS 성능 최고 수준 |
| `ko-sroberta-multitask` | 768 | 매우 우수 | Apache 2.0 | 한국어 특화, 다양한 태스크 학습 |
| `ELSER v2` | sparse | 보통 | Elastic License | 영어 최적화, 한국어 제한적 |

### Dimension Tradeoffs

| Dims | 메모리 (10M docs, float32) | 인덱싱 속도 | 검색 레이턴시 | Recall 수준 |
|------|---------------------------|-----------|-------------|-----------|
| 384 | ~15 GB | 빠름 | ~5ms | 기본 |
| 768 | ~30 GB | 중간 | ~10ms | 높음 |
| 1024 | ~40 GB | 느림 | ~15ms | 최고 |

**의사결정 트리**:

```
임베딩 모델 선택
├── 한국어만 사용?
│   ├── Yes → KoSimCSE-roberta 또는 ko-sroberta-multitask (768d)
│   │   └── STS 벤치마크에서 multilingual 모델 대비 2-5% 우위
│   └── No (다국어 혼합)
│       ├── 비용/메모리 여유 → multilingual-e5-large (1024d)
│       ├── 균형 → multilingual-e5-base (768d) ★ 가장 일반적
│       └── 리소스 제한 → multilingual-e5-small (384d)
├── Dense + Sparse 동시 필요?
│   └── Yes → BGE-M3 (dense 1024d + sparse)
└── Elastic 내장 사용?
    └── ELSER v2 (한국어 성능 제한 주의)
```

### Kotlin EmbeddingService

```kotlin
@Service
class EmbeddingService(
    @Value("\${embedding.server.url}") private val embeddingServerUrl: String,
    private val webClient: WebClient
) {
    private val logger = LoggerFactory.getLogger(EmbeddingService::class.java)

    data class EmbeddingRequest(
        val texts: List<String>,
        val model: String = "multilingual-e5-base"
    )

    data class EmbeddingResponse(
        val embeddings: List<List<Float>>
    )

    suspend fun embed(text: String): List<Float> {
        return embedBatch(listOf(text)).first()
    }

    suspend fun embedBatch(texts: List<String>): List<List<Float>> {
        return webClient.post()
            .uri("$embeddingServerUrl/embed")
            .bodyValue(EmbeddingRequest(texts = texts))
            .retrieve()
            .awaitBody<EmbeddingResponse>()
            .embeddings
    }
}
```

### Batch Embedding Pipeline with Coroutines

```kotlin
@Service
class BatchEmbeddingPipeline(
    private val embeddingService: EmbeddingService,
    private val meterRegistry: MeterRegistry
) {
    private val logger = LoggerFactory.getLogger(BatchEmbeddingPipeline::class.java)
    private val embeddingTimer = meterRegistry.timer("embedding.batch.duration")
    private val embeddingCounter = meterRegistry.counter("embedding.batch.total")

    suspend fun embedDocuments(
        documents: List<ProductDocument>,
        batchSize: Int = 32,
        maxConcurrency: Int = 4
    ): List<Pair<ProductDocument, List<Float>>> = coroutineScope {
        val semaphore = Semaphore(maxConcurrency)

        documents.chunked(batchSize).flatMap { chunk ->
            semaphore.withPermit {
                val texts = chunk.map { "query: ${it.title}" }

                val embeddings = embeddingTimer.recordSuspend {
                    embeddingService.embedBatch(texts)
                }
                embeddingCounter.increment(chunk.size.toDouble())

                chunk.zip(embeddings)
            }
        }
    }

    private suspend fun <T> Timer.recordSuspend(block: suspend () -> T): T {
        val start = System.nanoTime()
        try {
            return block()
        } finally {
            record(System.nanoTime() - start, TimeUnit.NANOSECONDS)
        }
    }
}
```

### Embedding Serving Options

| 방식 | 장점 | 단점 | 적합 시점 |
|------|------|------|----------|
| ES Inference API | ES 통합, 인덱싱 파이프라인 연동 | 모델 제한, GPU 미지원 | ELSER, 소규모 |
| Self-hosted ONNX | 빠른 추론, CPU 최적화 | ONNX 변환 필요 | 비GPU 환경, 768d 이하 |
| TorchServe/Triton | GPU 활용, 배치 최적화 | 인프라 복잡 | 대규모 (>1M docs/day) |
| External API (OpenAI 등) | 인프라 불필요 | 레이턴시, 비용, 데이터 외부 전송 | PoC, 소규모 |
| TEI (Text Embeddings Inference) | 최적화된 서빙, Docker 간편 | HuggingFace 모델만 | 프로덕션 권장 |

## 4. Hybrid Search & RRF

### RRF (Reciprocal Rank Fusion) Formula

```
RRF_score(d) = SUM( 1 / (k + rank_i(d)) )

- d: 문서
- k: 순위 스무딩 상수 (기본 60)
- rank_i(d): i번째 retriever에서 문서 d의 순위 (1-based)

예시: 문서가 BM25에서 3위, kNN에서 1위일 때 (k=60):
  RRF = 1/(60+3) + 1/(60+1) = 0.0159 + 0.0164 = 0.0323
```

### ES 8.x sub_searches + rank.rrf

```json
GET /products-vector/_search
{
  "sub_searches": [
    {
      "query": {
        "multi_match": {
          "query": "무선 블루투스 이어폰",
          "fields": ["title^3", "title.search^2", "description"],
          "type": "best_fields"
        }
      }
    },
    {
      "query": {
        "knn": {
          "field": "title_vector",
          "query_vector": [0.12, -0.34, 0.56, ...],
          "num_candidates": 100
        }
      }
    }
  ],
  "rank": {
    "rrf": {
      "rank_constant": 60,
      "rank_window_size": 100
    }
  },
  "size": 10,
  "_source": ["title", "price", "category"]
}
```

### Simple Hybrid (knn + query without explicit RRF)

```json
GET /products-vector/_search
{
  "query": {
    "multi_match": {
      "query": "무선 블루투스 이어폰",
      "fields": ["title^3", "description"],
      "type": "best_fields"
    }
  },
  "knn": {
    "field": "title_vector",
    "query_vector": [0.12, -0.34, 0.56, ...],
    "k": 10,
    "num_candidates": 100,
    "boost": 0.5
  },
  "size": 10,
  "_source": ["title", "price", "category"]
}
```

**동작**: `query` 결과와 `knn` 결과를 선형 결합 (스코어 합산). `knn.boost`로 벡터 검색 가중치 조절. RRF보다 단순하지만 스코어 스케일 차이로 한쪽에 치우칠 수 있음.

### Fusion Strategy Comparison

| 전략 | 원리 | 장점 | 단점 | 적합 시점 |
|------|------|------|------|----------|
| **RRF** | 순위 기반 융합 | 스코어 정규화 불필요, 안정적 | k 값 튜닝 필요, 세밀한 조절 어려움 | 프로덕션 기본 권장 |
| Linear Combination | 정규화 스코어 가중합 | 직관적, 가중치 세밀 조절 | 스코어 정규화 필수, 분포 의존적 | A/B 테스트로 가중치 튜닝 가능 시 |
| Learned Weights | ML 모델로 가중치 학습 | 최적 성능 가능 | 학습 데이터/인프라 필요 | 충분한 클릭 로그 보유 시 |

### RRF k Value Impact

| k 값 | 특성 | 효과 | 적합 시점 |
|------|------|------|----------|
| `k = 1` | 상위 순위 극단적 우대 | 1위 결과가 압도적 스코어, 하위 순위 급락 | 최상위 결과만 중요할 때 |
| `k = 60` (기본) | 균형 잡힌 순위 반영 | 상위-하위 간 스코어 차이 완만 | **대부분의 프로덕션 환경** |
| `k = 100+` | 순위 차이 최소화 | 거의 모든 결과가 비슷한 RRF 스코어 | 다양성 극대화, 순위 민감도 낮출 때 |

**원칙**: `k = 60`에서 시작하여 NDCG 측정 후 조정. k를 낮추면 상위 결과의 영향력 증가, 높이면 평탄화.

### Kotlin HybridSearchService

```kotlin
@Service
class HybridSearchService(
    private val client: ElasticsearchClient,
    private val embeddingService: EmbeddingService,
    private val meterRegistry: MeterRegistry
) {
    private val logger = LoggerFactory.getLogger(HybridSearchService::class.java)
    private val searchTimer = meterRegistry.timer("hybrid.search.duration")
    private val searchCounter = meterRegistry.counter("hybrid.search.total")

    suspend fun hybridSearch(
        query: String,
        category: String? = null,
        priceRange: IntRange? = null,
        size: Int = 10
    ): HybridSearchResult = withContext(Dispatchers.IO) {
        searchCounter.increment()
        val start = System.nanoTime()

        try {
            // 1. 쿼리 텍스트를 벡터로 변환
            val queryVector = embeddingService.embed("query: $query")

            // 2. sub_searches + RRF 쿼리 구성
            val response = client.search({ s ->
                s.index("products-vector")
                    .size(size)
                    .source { src ->
                        src.filter { f -> f.includes("title", "price", "category", "thumbnail_url") }
                    }
                    .subSearches(
                        // BM25 retriever
                        SubSearchContainer.of { ss ->
                            ss.query { q ->
                                q.bool { b ->
                                    b.must { m ->
                                        m.multiMatch { mm ->
                                            mm.query(query)
                                                .fields("title^3", "title.search^2", "description")
                                                .type(TextQueryType.BestFields)
                                        }
                                    }
                                    applyFilters(b, category, priceRange)
                                    b
                                }
                            }
                        },
                        // kNN retriever
                        SubSearchContainer.of { ss ->
                            ss.query { q ->
                                q.knn { k ->
                                    k.field("title_vector")
                                        .queryVector(queryVector.map { it.toDouble() })
                                        .numCandidates(size * 10)
                                    category?.let { cat ->
                                        k.filter { f ->
                                            f.term { t -> t.field("category").value(cat) }
                                        }
                                    }
                                    k
                                }
                            }
                        }
                    )
                    .rank { r ->
                        r.rrf { rrf ->
                            rrf.rankConstant(60L)
                                .rankWindowSize(100)
                        }
                    }
            }, Product::class.java)

            val hits = response.hits().hits()
            HybridSearchResult(
                items = hits.mapNotNull { hit ->
                    hit.source()?.copy(score = hit.score())
                },
                total = response.hits().total()?.value() ?: 0,
                took = response.took()
            )
        } finally {
            searchTimer.record(System.nanoTime() - start, TimeUnit.NANOSECONDS)
        }
    }

    private fun applyFilters(
        b: BoolQuery.Builder,
        category: String?,
        priceRange: IntRange?
    ) {
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
    }
}

data class HybridSearchResult(
    val items: List<Product>,
    val total: Long,
    val took: Long
)
```

## 5. Semantic Search Patterns

### ELSER Sparse Vector Mapping & Query

```json
PUT /products-semantic
{
  "mappings": {
    "properties": {
      "title": {
        "type": "text",
        "analyzer": "nori_standard"
      },
      "title_tokens": {
        "type": "sparse_vector"
      }
    }
  }
}
```

**ELSER 인덱싱**: Ingest pipeline으로 자동 토큰 생성:

```json
PUT _ingest/pipeline/elser-pipeline
{
  "processors": [
    {
      "inference": {
        "model_id": ".elser_model_2",
        "input_output": [
          {
            "input_field": "title",
            "output_field": "title_tokens"
          }
        ]
      }
    }
  ]
}
```

**ELSER 검색 (text_expansion)**:

```json
GET /products-semantic/_search
{
  "query": {
    "text_expansion": {
      "title_tokens": {
        "model_id": ".elser_model_2",
        "model_text": "무선 블루투스 이어폰"
      }
    }
  },
  "size": 10
}
```

### Dense vs Sparse Vector Tradeoffs

| 기준 | Dense Vector (kNN) | Sparse Vector (ELSER) |
|------|-------------------|---------------------|
| 벡터 형태 | 고정 차원 실수 배열 (768d 등) | 가변 길이 토큰-가중치 쌍 |
| 유사도 측정 | cosine / dot_product | 희소 벡터 내적 |
| 한국어 성능 | 모델 의존 (multilingual 우수) | 영어 최적화, 한국어 제한적 |
| 인덱스 크기 | dims에 비례, 예측 가능 | 문서 길이/어휘에 따라 가변 |
| 해석 가능성 | 낮음 (블랙박스) | 높음 (토큰별 가중치 확인 가능) |
| Zero-shot 성능 | 좋음 (시맨틱 유사도) | 매우 좋음 (영어 도메인) |
| 인프라 복잡도 | 외부 임베딩 서버 필요 | ES 내장 (Elastic License) |
| 커스터마이징 | 모델 파인튜닝 가능 | 제한적 |

### Korean-Specific Semantic Search Challenges

| 도전 과제 | 원인 | 대응 전략 |
|----------|------|----------|
| 교착어 형태소 변화 | 조사/어미에 따라 동일 의미의 표면형 다양 ("이어폰을", "이어폰이", "이어폰의") | Nori 형태소 분석 후 임베딩, 또는 임베딩 모델에 원문 전달 |
| 복합명사 분리 | "무선이어폰" → "무선" + "이어폰" 분리 여부가 임베딩에 영향 | User dictionary 등록, 모델 입력 전 전처리 통일 |
| 한영 혼합 텍스트 | "AirPods 에어팟 프로" 같은 혼합 텍스트 임베딩 품질 저하 | Multilingual 모델 사용, 한영 정규화 전처리 |
| 짧은 쿼리 (1-2 단어) | 임베딩 정보량 부족, 시맨틱 유사도 부정확 | BM25 + kNN 하이브리드 필수, 짧은 쿼리는 BM25 가중치 상향 |
| 도메인 전문 용어 | 일반 모델이 전문 용어 임베딩을 제대로 표현 못함 | 도메인 파인튜닝 또는 동의어 확장 후 임베딩 |
| 신조어/은어 | 학습 데이터에 없는 새로운 표현 | 정기적 모델 업데이트, BM25 fallback |

## 6. Kotlin Implementation Patterns

### kNN Query Builder

```kotlin
fun buildKnnQuery(
    field: String,
    queryVector: List<Float>,
    k: Int = 10,
    numCandidates: Int = 100,
    filter: Query? = null
): SearchRequest {
    return SearchRequest.of { s ->
        s.index("products-vector")
            .knn { knn ->
                knn.field(field)
                    .queryVector(queryVector.map { it.toDouble() })
                    .k(k)
                    .numCandidates(numCandidates)
                filter?.let { knn.filter(it) }
                knn
            }
            .size(k)
    }
}

// 사용 예시
suspend fun searchSimilarProducts(productId: String): List<Product> =
    withContext(Dispatchers.IO) {
        // 기존 상품의 벡터 조회
        val sourceProduct = client.get({ g ->
            g.index("products-vector").id(productId)
        }, Product::class.java)

        val vector = sourceProduct.source()?.titleVector
            ?: throw IllegalArgumentException("Product $productId has no vector")

        val request = buildKnnQuery(
            field = "title_vector",
            queryVector = vector,
            k = 20,
            numCandidates = 200,
            filter = Query.of { q ->
                q.bool { b ->
                    b.mustNot { mn ->
                        mn.ids { ids -> ids.values(productId) }
                    }
                    b
                }
            }
        )

        client.search(request, Product::class.java)
            .hits().hits().mapNotNull { it.source() }
    }
```

### Vector Field Mapping Creation

```kotlin
suspend fun createVectorIndex(
    indexName: String,
    dims: Int = 768,
    similarity: String = "cosine",
    quantization: String = "hnsw",
    m: Int = 16,
    efConstruction: Int = 200
) = withContext(Dispatchers.IO) {
    client.indices().create { c ->
        c.index(indexName)
            .settings { s ->
                s.numberOfShards("3")
                    .numberOfReplicas("1")
            }
            .mappings { map ->
                map.properties("title") { p ->
                    p.text { t -> t.analyzer("nori_standard") }
                }
                .properties("title_vector") { p ->
                    p.denseVector { dv ->
                        dv.dims(dims)
                            .index(true)
                            .similarity(similarity)
                            .indexOptions { io ->
                                io.type(quantization)
                                    .m(m)
                                    .efConstruction(efConstruction)
                            }
                    }
                }
                .properties("category") { p -> p.keyword { k -> k } }
                .properties("price") { p -> p.integer { i -> i } }
            }
    }
    logger.info("Vector index '{}' created: dims={}, similarity={}, type={}",
        indexName, dims, similarity, quantization)
}
```

### Bulk Vector Indexing Pipeline

```kotlin
@Service
class VectorIndexingPipeline(
    private val client: ElasticsearchClient,
    private val embeddingPipeline: BatchEmbeddingPipeline,
    private val meterRegistry: MeterRegistry
) {
    private val logger = LoggerFactory.getLogger(VectorIndexingPipeline::class.java)
    private val indexedCounter = meterRegistry.counter("vector.indexing.docs.total")
    private val indexingTimer = meterRegistry.timer("vector.indexing.batch.duration")
    private val errorCounter = meterRegistry.counter("vector.indexing.errors.total")

    suspend fun indexDocumentsWithVectors(
        documents: Flow<ProductDocument>,
        indexName: String = "products-vector",
        batchSize: Int = 100
    ) {
        documents
            .chunked(batchSize)
            .collect { batch ->
                val start = System.nanoTime()

                try {
                    // 1. 배치 임베딩 생성
                    val docsWithVectors = embeddingPipeline.embedDocuments(batch)

                    // 2. Bulk 인덱싱
                    val response = client.bulk { b ->
                        b.index(indexName)
                        docsWithVectors.forEach { (doc, vector) ->
                            b.operations { op ->
                                op.index { idx ->
                                    idx.id(doc.id)
                                        .document(doc.copy(titleVector = vector))
                                }
                            }
                        }
                        b
                    }

                    // 3. 결과 처리
                    if (response.errors()) {
                        val failures = response.items().filter { it.error() != null }
                        errorCounter.increment(failures.size.toDouble())
                        failures.forEach { item ->
                            logger.error("Indexing failed: id={}, error={}",
                                item.id(), item.error()?.reason())
                        }
                    }

                    val successCount = response.items().count { it.error() == null }
                    indexedCounter.increment(successCount.toDouble())
                    logger.info("Indexed {}/{} docs with vectors in {}ms",
                        successCount, batch.size, (System.nanoTime() - start) / 1_000_000)
                } finally {
                    indexingTimer.record(System.nanoTime() - start, TimeUnit.NANOSECONDS)
                }
            }
    }

    private fun <T> Flow<T>.chunked(size: Int): Flow<List<T>> = flow {
        val buffer = mutableListOf<T>()
        collect { item ->
            buffer.add(item)
            if (buffer.size >= size) {
                emit(buffer.toList())
                buffer.clear()
            }
        }
        if (buffer.isNotEmpty()) emit(buffer.toList())
    }
}
```

### Full HybridSearchService with Embedding at Query Time

```kotlin
@Service
class ProductHybridSearchService(
    private val client: ElasticsearchClient,
    private val embeddingService: EmbeddingService,
    private val meterRegistry: MeterRegistry
) {
    private val logger = LoggerFactory.getLogger(ProductHybridSearchService::class.java)

    data class SearchParams(
        val query: String,
        val category: String? = null,
        val priceRange: IntRange? = null,
        val size: Int = 10,
        val bm25Weight: Float = 1.0f,
        val knnWeight: Float = 1.0f,
        val useRrf: Boolean = true,
        val rrfRankConstant: Long = 60
    )

    data class SearchResult(
        val items: List<ProductHit>,
        val total: Long,
        val took: Long,
        val strategy: String
    )

    data class ProductHit(
        val id: String,
        val title: String,
        val price: Int,
        val category: String,
        val score: Double?
    )

    suspend fun search(params: SearchParams): SearchResult = withContext(Dispatchers.IO) {
        // 쿼리 임베딩 생성 (prefix 추가는 모델에 따라)
        val queryVector = embeddingService.embed("query: ${params.query}")

        val response = if (params.useRrf) {
            searchWithRrf(params, queryVector)
        } else {
            searchWithLinearCombination(params, queryVector)
        }

        val hits = response.hits().hits()
        SearchResult(
            items = hits.map { hit ->
                ProductHit(
                    id = hit.id(),
                    title = hit.source()?.title ?: "",
                    price = hit.source()?.price ?: 0,
                    category = hit.source()?.category ?: "",
                    score = hit.score()
                )
            },
            total = response.hits().total()?.value() ?: 0,
            took = response.took(),
            strategy = if (params.useRrf) "rrf" else "linear"
        )
    }

    private fun searchWithRrf(
        params: SearchParams,
        queryVector: List<Float>
    ): SearchResponse<Product> {
        return client.search({ s ->
            s.index("products-vector")
                .size(params.size)
                .source { src ->
                    src.filter { f ->
                        f.includes("title", "price", "category", "thumbnail_url")
                    }
                }
                .subSearches(
                    SubSearchContainer.of { ss ->
                        ss.query { q -> buildBm25Query(q, params) }
                    },
                    SubSearchContainer.of { ss ->
                        ss.query { q -> buildKnnQuery(q, queryVector, params) }
                    }
                )
                .rank { r ->
                    r.rrf { rrf ->
                        rrf.rankConstant(params.rrfRankConstant)
                            .rankWindowSize(params.size * 10)
                    }
                }
        }, Product::class.java)
    }

    private fun searchWithLinearCombination(
        params: SearchParams,
        queryVector: List<Float>
    ): SearchResponse<Product> {
        return client.search({ s ->
            s.index("products-vector")
                .size(params.size)
                .source { src ->
                    src.filter { f ->
                        f.includes("title", "price", "category", "thumbnail_url")
                    }
                }
                .query { q -> buildBm25Query(q, params) }
                .knn { knn ->
                    knn.field("title_vector")
                        .queryVector(queryVector.map { it.toDouble() })
                        .k(params.size)
                        .numCandidates(params.size * 10)
                        .boost(params.knnWeight)
                    params.category?.let { cat ->
                        knn.filter { f ->
                            f.term { t -> t.field("category").value(cat) }
                        }
                    }
                    knn
                }
        }, Product::class.java)
    }

    private fun buildBm25Query(q: Query.Builder, params: SearchParams): Query.Builder {
        return q.bool { b ->
            b.must { m ->
                m.multiMatch { mm ->
                    mm.query(params.query)
                        .fields("title^3", "title.search^2", "description")
                        .type(TextQueryType.BestFields)
                }
            }
            params.category?.let { cat ->
                b.filter { f -> f.term { t -> t.field("category").value(cat) } }
            }
            params.priceRange?.let { range ->
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

    private fun buildKnnQuery(
        q: Query.Builder,
        queryVector: List<Float>,
        params: SearchParams
    ): Query.Builder {
        return q.knn { knn ->
            knn.field("title_vector")
                .queryVector(queryVector.map { it.toDouble() })
                .numCandidates(params.size * 10)
            params.category?.let { cat ->
                knn.filter { f ->
                    f.term { t -> t.field("category").value(cat) }
                }
            }
            knn
        }
    }
}
```

## 7. Anti-Patterns

| Anti-Pattern | 문제 | Fix | Severity |
|-------------|------|-----|----------|
| `dot_product` without normalization | 정규화되지 않은 벡터로 내적 시 magnitude가 결과 왜곡 | `cosine` 사용 또는 임베딩 후 L2 정규화 적용 | **Critical** |
| `dims: 1024` without justification | 768d 대비 메모리 33% 증가, 레이턴시 증가, recall 개선 미미할 수 있음 | 768d에서 시작, 벤치마크로 1024d 필요성 입증 후 전환 | **High** |
| `index: false` on dense_vector | kNN 검색 불가, script_score만 가능 (O(N) 스캔) | `index: true` 설정 필수 | **Critical** |
| `num_candidates == k` | HNSW 탐색 폭이 결과 수와 동일하여 recall 극도로 낮음 | `num_candidates >= k * 10` 설정 | **High** |
| English-only model for Korean | "sentence-transformers/all-MiniLM-L6-v2" 등으로 한국어 임베딩 시 품질 매우 낮음 | multilingual-e5-base 이상 또는 KoSimCSE 계열 사용 | **Critical** |
| No quantization on >10M docs | float32로 10M docs * 768d = 30GB+ 메모리 소비 | int8_hnsw 적용으로 75% 메모리 절감 | **High** |
| Synchronous single-doc embedding | 문서 1건씩 동기 임베딩 호출로 인덱싱 병목 | 배치 임베딩 (32-64건), coroutine async 처리 | **High** |
| RRF with single retriever | RRF는 다중 retriever 순위 융합인데 단일 retriever로 사용하면 무의미 | 최소 2개 retriever (BM25 + kNN) 조합 | **Medium** |
| Missing filter on kNN | 전체 인덱스 대상 kNN 검색으로 불필요한 카테고리 결과 포함 | kNN `filter`로 대상 문서 제한 | **High** |
| Embedding model version mismatch | 인덱싱과 검색 시 다른 모델 버전 사용으로 벡터 공간 불일치 | 모델 버전을 인덱스 메타데이터에 기록, 변경 시 전체 reindex | **Critical** |
| ELSER as primary for Korean | ELSER v2는 영어 최적화, 한국어 재현율 현저히 낮음 | 한국어는 dense vector (multilingual 모델) 중심으로 설계 | **High** |
| No evaluation before combining | BM25-only, kNN-only 각각의 baseline NDCG 없이 하이브리드 구성 | 각 retriever 단독 NDCG 측정 후 하이브리드 효과 검증 | **Medium** |
| `ef_construction` too low (<100) | HNSW 그래프 품질 저하, recall 감소 | 프로덕션은 최소 200 이상 설정 | **High** |
| Triple storage (text + dense + sparse) | 동일 필드를 text + dense_vector + sparse_vector로 저장 시 인덱스 크기 3배+ | 실제 필요한 조합만 유지, 대부분 text + dense 충분 | **Medium** |

---

**Remember**: 벡터 검색은 BM25를 대체하는 것이 아니라 보완하는 것입니다. 항상 BM25-only, kNN-only, hybrid 각각의 NDCG를 측정하고, 하이브리드가 실제로 개선을 가져오는지 확인한 후 프로덕션에 배포하세요.
