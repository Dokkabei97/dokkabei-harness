---
name: search-pipeline-reranking
description: Use this skill when designing multi-stage retrieval, configuring ES search pipelines, implementing reranking (rescore/LTR/cross-encoder), query understanding, result diversification, or personalization. Covers ES 8.x search pipelines, Learning to Rank, and Kotlin service patterns for production search systems.
---

# Search Pipeline & Reranking

검색 파이프라인, 재순위화(reranking), 쿼리 이해(query understanding), 결과 다양성, 개인화를 포괄하는 고급 검색 아키텍처 가이드입니다.

## When to Activate

- ES 8.x search pipeline 설정 또는 커스텀 프로세서 개발 시
- 재순위화(rescore, LTR, cross-encoder) 전략 설계 시
- 다단계 검색(multi-stage retrieval) 아키텍처 설계 시
- 쿼리 분류, 확장, 스펠 체크 등 query understanding 구현 시
- field_collapse, pinned queries 등 결과 다양성/머천다이징 시
- 사용자 프로필 기반 개인화 검색 설계 시
- Retriever abstraction (ES 8.14+) 활용 시

## 1. Elasticsearch Search Pipelines (ES 8.x)

### Search Pipeline vs Ingest Pipeline

| 구분 | Ingest Pipeline | Search Pipeline |
|------|----------------|-----------------|
| **실행 시점** | 문서 인덱싱 시 | 검색 요청 시 |
| **대상** | 문서 필드 변환/보강 | 검색 요청/응답 변환 |
| **프로세서 유형** | set, rename, grok, script 등 | filter_query, script, rename_field 등 |
| **용도** | ETL, 데이터 정제 | 멀티테넌트 필터, 결과 후처리 |
| **API** | `PUT _ingest/pipeline` | `PUT _search/pipeline` |

### Built-in Request Processors

| Processor | 역할 | 활용 시나리오 |
|-----------|------|-------------|
| `filter_query` | 검색 요청에 필터 쿼리 자동 주입 | 멀티테넌트 격리, 삭제 문서 제외 |
| `script` | Painless 스크립트로 요청/응답 변환 | 동적 boost 조정, 필드 추가/변환 |
| `rename_field` | 응답 필드명 변경 | API 호환성 유지, 내부 필드명 숨김 |

### Search Pipeline 생성

```json
// 멀티테넌트 필터 자동 주입 파이프라인
PUT _search/pipeline/tenant_filter_pipeline
{
  "description": "Automatically inject tenant filter for multi-tenant isolation",
  "request_processors": [
    {
      "filter_query": {
        "tag": "tenant_isolation",
        "description": "Filter by tenant_id from request context",
        "query": {
          "term": {
            "tenant_id": "{{_request.tenant_id}}"
          }
        }
      }
    }
  ],
  "response_processors": [
    {
      "rename_field": {
        "field": "internal_score",
        "target_field": "relevance_score"
      }
    }
  ]
}
```

### 인덱스에 기본 파이프라인 설정

```json
// 인덱스 레벨 기본 search pipeline 설정
PUT /products/_settings
{
  "index.search.default_pipeline": "tenant_filter_pipeline"
}

// 검색 시 자동 적용 (명시적 지정도 가능)
GET /products/_search?search_pipeline=tenant_filter_pipeline
{
  "query": { "match": { "title": "무선 이어폰" } }
}
```

### 멀티테넌트 필터 주입 Use Case

```json
// 삭제 플래그 + 테넌트 격리를 동시에 처리하는 파이프라인
PUT _search/pipeline/secure_search_pipeline
{
  "request_processors": [
    {
      "filter_query": {
        "tag": "exclude_deleted",
        "query": {
          "term": { "is_deleted": false }
        }
      }
    },
    {
      "filter_query": {
        "tag": "tenant_filter",
        "query": {
          "term": { "tenant_id": "{{_request.tenant_id}}" }
        }
      }
    },
    {
      "script": {
        "lang": "painless",
        "source": """
          if (ctx._source['boost_new_arrivals'] == true) {
            // 최근 7일 상품에 가산점
            ctx._request['rescore'] = [
              'window_size': 100,
              'query': [
                'rescore_query': [
                  'range': ['created_at': ['gte': 'now-7d']]
                ],
                'query_weight': 1.0,
                'rescore_query_weight': 1.5
              ]
            ];
          }
        """
      }
    }
  ]
}
```

### Kotlin: Search Pipeline 지정

```kotlin
@Service
class PipelineSearchService(
    private val client: ElasticsearchClient
) {
    fun searchWithPipeline(
        keyword: String,
        tenantId: String,
        pipeline: String = "tenant_filter_pipeline"
    ): List<Product> {
        // search_pipeline 파라미터는 elasticsearch-java에서 직접 지원
        val response = client.search({ s ->
            s.index("products")
                .searchPipeline(pipeline)
                .query { q ->
                    q.match { m -> m.field("title").query(keyword) }
                }
                .size(20)
        }, Product::class.java)

        return response.hits().hits().mapNotNull { it.source() }
    }
}
```

## 2. Rescore Query (Built-in Reranking)

### Rescore 동작 원리

Rescore는 first-pass 검색 결과의 상위 N개 문서에 대해 추가 스코어링을 적용합니다. 전체 문서에 대해 무거운 쿼리를 실행하는 것보다 훨씬 효율적입니다.

```
[전체 문서] → first-pass (BM25) → [상위 window_size개] → rescore query → [최종 순위]
```

### Rescore 파라미터

| Parameter | 설명 | 기본값 | 권장값 |
|-----------|------|--------|--------|
| `window_size` | rescore 대상 문서 수 | 10 | 50~200 |
| `query_weight` | first-pass 스코어 가중치 | 1.0 | 0.7~1.0 |
| `rescore_query_weight` | rescore 스코어 가중치 | 1.0 | 1.0~2.0 |
| `score_mode` | 스코어 결합 방식 | `total` | `total` / `multiply` |

**score_mode 옵션**:

| Mode | 계산 | 사용 시나리오 |
|------|------|-------------|
| `total` | `query_weight * first_pass + rescore_query_weight * rescore` | 기본, 대부분의 케이스 |
| `multiply` | `first_pass * rescore` | rescore가 0~1 범위 factor일 때 |
| `avg` | `(first_pass + rescore) / 2` | 두 스코어를 동등하게 |
| `max` | `max(first_pass, rescore)` | 더 높은 스코어 채택 |
| `min` | `min(first_pass, rescore)` | 보수적 스코어링 |

### Phrase Proximity Rescore

```json
// first-pass: 일반 매칭 → rescore: 구문 근접도로 재순위화
POST /products/_search
{
  "query": {
    "match": {
      "title": {
        "query": "삼성 무선 이어폰",
        "operator": "or"
      }
    }
  },
  "rescore": {
    "window_size": 100,
    "query": {
      "rescore_query": {
        "match_phrase": {
          "title": {
            "query": "삼성 무선 이어폰",
            "slop": 2
          }
        }
      },
      "query_weight": 0.7,
      "rescore_query_weight": 1.5,
      "score_mode": "total"
    }
  }
}
```

### Chained Rescore (Phrase + Recency Decay)

```json
// 다단계 rescore: 1단계 구문 근접도 → 2단계 최신성 가산
POST /products/_search
{
  "query": {
    "multi_match": {
      "query": "노트북 가방",
      "fields": ["title^3", "description"],
      "type": "best_fields"
    }
  },
  "rescore": [
    {
      "window_size": 200,
      "query": {
        "rescore_query": {
          "match_phrase": {
            "title": {
              "query": "노트북 가방",
              "slop": 1
            }
          }
        },
        "query_weight": 0.7,
        "rescore_query_weight": 2.0,
        "score_mode": "total"
      }
    },
    {
      "window_size": 100,
      "query": {
        "rescore_query": {
          "function_score": {
            "query": { "match_all": {} },
            "functions": [
              {
                "gauss": {
                  "created_at": {
                    "origin": "now",
                    "scale": "14d",
                    "offset": "3d",
                    "decay": 0.5
                  }
                }
              }
            ],
            "boost_mode": "replace"
          }
        },
        "query_weight": 1.0,
        "rescore_query_weight": 0.5,
        "score_mode": "total"
      }
    }
  ]
}
```

### Kotlin Rescore 구현 패턴

```kotlin
@Service
class RescoreSearchService(
    private val client: ElasticsearchClient
) {
    fun searchWithRescore(
        keyword: String,
        category: String? = null,
        windowSize: Int = 100
    ): SearchResult {
        val response = client.search({ s ->
            s.index("products")
                .query { q ->
                    q.bool { b ->
                        b.must { m ->
                            m.multiMatch { mm ->
                                mm.query(keyword)
                                    .fields("title^3", "title.search^2", "description")
                                    .type(TextQueryType.BestFields)
                            }
                        }
                        category?.let { cat ->
                            b.filter { f ->
                                f.term { t -> t.field("category").value(cat) }
                            }
                        }
                        b
                    }
                }
                // Phrase proximity rescore
                .rescore { r ->
                    r.windowSize(windowSize)
                        .query { rq ->
                            rq.rescoreQuery { q ->
                                q.matchPhrase { mp ->
                                    mp.field("title").query(keyword).slop(2)
                                }
                            }
                            .queryWeight(0.7)
                            .rescoreQueryWeight(1.5)
                            .scoreMode(ScoreMode.Total)
                        }
                }
                .size(20)
        }, Product::class.java)

        return SearchResult(
            items = response.hits().hits().mapNotNull { it.source() },
            total = response.hits().total()?.value() ?: 0,
            maxScore = response.hits().maxScore()
        )
    }
}
```

### window_size vs Latency 트레이드오프

| window_size | 레이턴시 영향 | 적합 시나리오 | 주의사항 |
|-------------|-------------|-------------|---------|
| 50~100 | **Minimal** (+1~3ms) | 대부분의 검색, 기본 권장값 | 상위 결과 품질 개선에 충분 |
| 100~200 | **Low** (+3~8ms) | 정밀 구문 매칭 필요 시 | 첫 페이지 결과에 영향 |
| 200~500 | **Moderate** (+8~25ms) | LTR 모델 적용, 복잡한 rescore | 페이징 시 일관성 주의 |
| >500 | **High** (+25ms~) | 전체 결과 재정렬 필요 시 | 반드시 벤치마크로 검증 |

**핵심 원칙**: `window_size`는 반환할 결과 수(size)보다 크거나 같아야 합니다. 일반적으로 `size * 5 ~ size * 10` 범위가 적절합니다.

## 3. ES 8.x Retriever Abstraction

ES 8.14+에서 도입된 Retriever는 다단계 검색을 선언적으로 구성하는 추상화 계층입니다.

### Retriever 유형

| Retriever | 설명 | 최소 ES 버전 | 용도 |
|-----------|------|-------------|------|
| `standard` | 일반 query DSL 래핑 | 8.14.0 | 기존 쿼리를 retriever로 표현 |
| `knn` | k-nearest neighbors 검색 | 8.14.0 | 벡터 유사도 검색 |
| `rrf` | Reciprocal Rank Fusion | 8.14.0 | 여러 retriever 결과 융합 |
| `text_similarity_reranker` | Inference API 기반 시맨틱 재순위화 | 8.15.0 | cross-encoder, LLM reranking |
| `rule` | query rules 기반 결과 조작 | 8.16.0 | 머천다이징, pinned results |

### Hybrid RRF: Standard + kNN Retriever

```json
// BM25 텍스트 검색과 벡터 검색을 RRF로 융합
POST /products/_search
{
  "retriever": {
    "rrf": {
      "retrievers": [
        {
          "standard": {
            "query": {
              "multi_match": {
                "query": "무선 블루투스 이어폰",
                "fields": ["title^3", "description"],
                "type": "best_fields"
              }
            }
          }
        },
        {
          "knn": {
            "field": "title_embedding",
            "query_vector_builder": {
              "text_embedding": {
                "model_id": "my-text-embedding-model",
                "model_text": "무선 블루투스 이어폰"
              }
            },
            "k": 100,
            "num_candidates": 200
          }
        }
      ],
      "rank_window_size": 200,
      "rank_constant": 60
    }
  },
  "_source": ["title", "price", "category", "brand"],
  "size": 20
}
```

**RRF 스코어 계산**: `RRF(d) = Σ 1 / (rank_constant + rank_i(d))`
- `rank_constant`가 클수록 하위 순위 문서의 기여도 감소
- 기본값 60은 대부분의 시나리오에서 적절

### Semantic Reranking via text_similarity_reranker

```json
// 1단계: BM25로 후보 추출 → 2단계: cross-encoder로 시맨틱 재순위화
POST /products/_search
{
  "retriever": {
    "text_similarity_reranker": {
      "retriever": {
        "standard": {
          "query": {
            "match": {
              "title": "소음 차단되는 이어폰"
            }
          }
        }
      },
      "field": "title",
      "inference_id": "my-cross-encoder-model",
      "inference_text": "소음 차단되는 이어폰",
      "rank_window_size": 100,
      "min_score": 0.5
    }
  },
  "size": 20
}
```

**Inference API 사전 설정 필요**:

```json
PUT _inference/rerank/my-cross-encoder-model
{
  "service": "cohere",
  "service_settings": {
    "model_id": "rerank-multilingual-v3.0",
    "api_key": "{{COHERE_API_KEY}}"
  }
}
```

### Retriever 최소 버전 요구사항

| 기능 | 최소 버전 | 비고 |
|------|----------|------|
| `standard`, `knn`, `rrf` retriever | 8.14.0 | GA |
| `text_similarity_reranker` | 8.15.0 | Inference API 필요 |
| `rule` retriever | 8.16.0 | Query rules 사전 정의 필요 |
| Retriever 내 aggregations 지원 | 8.16.0 | compound retriever에서 aggs 가능 |
| Nested retriever composition | 8.14.0 | retriever 내부에 retriever 중첩 |

## 4. Learning to Rank (LTR)

### LTR 개요

Learning to Rank는 머신러닝 모델을 사용하여 검색 결과의 순위를 최적화하는 방법입니다. ES LTR 플러그인(`elasticsearch-ltr`)을 통해 학습된 모델을 rescore 단계에서 적용합니다.

```
[검색 로그] → feature 추출 → 학습 데이터 → 오프라인 학습 → 모델 배포 → rescore 적용
```

### Feature 유형

| Feature Type | 설명 | 예시 | 특성 |
|-------------|------|------|------|
| **BM25 score** | 텍스트 매칭 스코어 | `match` query on title | 텍스트 관련성 |
| **Recency** | 문서 최신성 | `function_score.gauss` on created_at | 시간 감쇠 |
| **Popularity** | 인기도 지표 | `field_value_factor` on sales_count | 클릭/구매 수 |
| **Field length** | 필드 길이 | `script_score` on title length | 간결성 선호 |
| **Category match** | 카테고리 일치도 | `term` query on category | 의도 매칭 |
| **CTR** | Click-Through Rate | 문서별 사전 계산된 CTR | 과거 사용자 행동 |
| **Price ratio** | 가격 대비 경쟁력 | script로 카테고리 평균 대비 계산 | 가격 경쟁력 |
| **Review score** | 리뷰 평점 | `field_value_factor` on avg_rating | 품질 지표 |

### Feature Set 정의

```json
// LTR 플러그인에 feature set 등록
POST _ltr/_featureset/product_features
{
  "featureset": {
    "name": "product_features",
    "features": [
      {
        "name": "title_bm25",
        "params": ["keywords"],
        "template_language": "mustache",
        "template": {
          "match": {
            "title": "{{keywords}}"
          }
        }
      },
      {
        "name": "description_bm25",
        "params": ["keywords"],
        "template_language": "mustache",
        "template": {
          "match": {
            "description": "{{keywords}}"
          }
        }
      },
      {
        "name": "recency_score",
        "params": [],
        "template_language": "mustache",
        "template": {
          "function_score": {
            "query": { "match_all": {} },
            "functions": [
              {
                "gauss": {
                  "created_at": {
                    "origin": "now",
                    "scale": "30d",
                    "decay": 0.5
                  }
                }
              }
            ],
            "boost_mode": "replace"
          }
        }
      },
      {
        "name": "popularity_score",
        "params": [],
        "template_language": "mustache",
        "template": {
          "function_score": {
            "query": { "match_all": {} },
            "functions": [
              {
                "field_value_factor": {
                  "field": "sales_count",
                  "modifier": "log1p",
                  "missing": 0
                }
              }
            ],
            "boost_mode": "replace"
          }
        }
      },
      {
        "name": "category_match",
        "params": ["category"],
        "template_language": "mustache",
        "template": {
          "term": {
            "category": "{{category}}"
          }
        }
      },
      {
        "name": "title_phrase_match",
        "params": ["keywords"],
        "template_language": "mustache",
        "template": {
          "match_phrase": {
            "title": {
              "query": "{{keywords}}",
              "slop": 2
            }
          }
        }
      }
    ]
  }
}
```

### Feature Logging

```json
// 기존 검색 결과에 대해 feature 값 로깅
POST /products/_search
{
  "query": {
    "bool": {
      "must": [
        {
          "match": {
            "title": "무선 이어폰"
          }
        }
      ],
      "should": [
        {
          "sltr": {
            "_name": "logged_features",
            "featureset": "product_features",
            "params": {
              "keywords": "무선 이어폰",
              "category": "electronics"
            }
          }
        }
      ]
    }
  },
  "ext": {
    "ltr_log": {
      "log_specs": {
        "name": "log_entry",
        "named_query": "logged_features"
      }
    }
  },
  "size": 100
}
```

**로깅 응답 예시**:
```json
{
  "hits": {
    "hits": [
      {
        "_id": "product_001",
        "_score": 12.5,
        "fields": {
          "_ltrlog": [
            {
              "log_entry": [
                { "name": "title_bm25", "value": 8.2 },
                { "name": "description_bm25", "value": 3.1 },
                { "name": "recency_score", "value": 0.85 },
                { "name": "popularity_score", "value": 6.7 },
                { "name": "category_match", "value": 1.0 },
                { "name": "title_phrase_match", "value": 5.3 }
              ]
            }
          ]
        }
      }
    ]
  }
}
```

### Named Queries로 절 매칭 디버깅·관측 (LTR feature logging과 용도 구분)

위 Feature Logging의 `named_query`는 **`sltr` feature set 로깅 대상을 지정하는 LTR 학습 파이프라인 전용** 메커니즘이다. 이와 별개로, 일반 `bool` 절에 `_name`을 부착해 응답 `hit.matched_queries`로 **어떤 절이 매칭을 일으켰는지** 관측하는 디버깅·운영 용도가 있다. 둘은 이름이 비슷하나 목적이 다르다 — 전자는 모델 학습용 feature 값 추출, 후자는 매칭 경로 진단·ROI 데이터화.

**절별 `_name` 부착으로 매칭 경로 집계**:
```json
POST /products/_search
{
  "query": {
    "bool": {
      "should": [
        { "match":        { "title.exact":   { "query": "무선 이어폰", "_name": "exact" } } },
        { "match":        { "title.synonym": { "query": "무선 이어폰", "_name": "synonym" } } },
        { "fuzzy":        { "title":         { "value": "이어폰", "fuzziness": "AUTO", "_name": "typo" } } },
        { "match_phrase": { "title":         { "query": "무선 이어폰", "boost": 2, "_name": "boost" } } }
      ]
    }
  },
  "include_named_queries_score": true
}
```

**응답** (ES 8.8.0+에서 `include_named_queries_score:true`이면 `matched_queries`가 List → `{name: score}` Map으로 변경):
```json
{
  "hits": {
    "hits": [
      {
        "_id": "product_001",
        "_score": 18.4,
        "matched_queries": { "exact": 12.1, "synonym": 0.0, "boost": 6.3 }
      }
    ]
  }
}
```
- 절별 매칭 빈도를 집계하면 동의어/오타 절이 실제로 얼마나 매칭에 기여하는지 **ROI 데이터화**(예: `synonym` 절이 거의 매칭 안 되면 동의어 사전 점검).
- ES 8.8.0 미만에서는 `matched_queries`가 매칭된 이름의 List(점수 없음)만 반환 — 절 기여 점수 관측은 8.8.0+ 필요.

**함정**:
- `matched_queries`는 **hit마다 절 재실행 오버헤드**가 있다 → 프로덕션 상시 사용 금지, `size` 제한·표본 추출로만.
- `filter`/`must_not`/`constant_score`/`function_score` 내부의 `_name`은 **score에 비기여**(점수 0 또는 final score와 불일치) → "matched인데 점수 0"을 버그로 오해하지 말 것.
- `nested` 쿼리 안의 named query는 루트 `matched_queries`가 아니라 **`inner_hits.matched_queries`로 봐야** 정확하다(issue#46231).

> 절 매칭 디버깅 증상 진입은 search-diagnostics 스킬 참조.

### 모델 배포

```json
// 오프라인 학습된 XGBoost 모델을 ES에 업로드
POST _ltr/_featureset/product_features/_createmodel
{
  "model": {
    "name": "product_ranking_v1",
    "model": {
      "type": "model/xgboost+json",
      "definition": "{\"learner\":{\"feature_names\":[\"title_bm25\",\"description_bm25\",\"recency_score\",\"popularity_score\",\"category_match\",\"title_phrase_match\"],\"feature_types\":[\"float\",\"float\",\"float\",\"float\",\"float\",\"float\"],\"gradient_booster\":{\"name\":\"gbtree\",\"model\":{\"trees\":[{\"tree_param\":{\"num_nodes\":\"7\"},\"id\":0,\"tree_weights\":[1.0]}]}},\"learner_model_param\":{\"base_score\":\"0.5\",\"num_class\":\"0\",\"num_feature\":\"6\"},\"objective\":{\"name\":\"rank:ndcg\",\"rank_objective\":{\"delta_ndcg\":\"true\"}}}}"
    }
  }
}
```

### LTR Rescore 적용

```json
// 학습된 모델을 rescore 단계에서 적용
POST /products/_search
{
  "query": {
    "multi_match": {
      "query": "무선 이어폰",
      "fields": ["title^3", "description"],
      "type": "best_fields"
    }
  },
  "rescore": {
    "window_size": 200,
    "query": {
      "rescore_query": {
        "sltr": {
          "params": {
            "keywords": "무선 이어폰",
            "category": "electronics"
          },
          "model": "product_ranking_v1"
        }
      },
      "query_weight": 0,
      "rescore_query_weight": 1,
      "score_mode": "total"
    }
  }
}
```

### LTR Training Workflow

```
┌─────────────────────────────────────────────────────────────────┐
│                    LTR Training Pipeline                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Step 1. Feature Set 생성                                       │
│  POST _ltr/_featureset/product_features                         │
│  → feature 템플릿 정의 (BM25, recency, popularity 등)            │
│                                                                 │
│  Step 2. Feature Logging                                        │
│  POST /products/_search (with sltr + ltr_log)                   │
│  → 검색 결과별 feature 값 수집                                    │
│                                                                 │
│  Step 3. 학습 데이터 Export                                      │
│  feature 로그 + relevance judgment → LibSVM/CSV 형식 변환        │
│  → qid:1 1:8.2 2:3.1 3:0.85 4:6.7 5:1.0 6:5.3 # label=4      │
│                                                                 │
│  Step 4. 오프라인 학습                                           │
│  XGBoost/LambdaMART rank:ndcg 목적함수로 학습                    │
│  → 교차 검증, NDCG@10 평가, 하이퍼파라미터 튜닝                    │
│                                                                 │
│  Step 5. 모델 업로드                                             │
│  POST _ltr/_featureset/_createmodel                              │
│  → xgboost+json 형식으로 ES에 배포                               │
│                                                                 │
│  Step 6. Rescore로 배포                                          │
│  rescore.query.rescore_query.sltr = 학습된 모델                  │
│  → A/B 테스트로 기존 대비 NDCG 개선 확인                          │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Kotlin LtrSearchService

```kotlin
@Service
class LtrSearchService(
    private val client: ElasticsearchClient
) {
    /**
     * LTR 모델을 rescore에 적용한 검색.
     * elasticsearch-java에서 sltr 쿼리를 직접 지원하지 않으므로
     * withJson escape hatch를 사용합니다.
     */
    fun searchWithLtr(
        keyword: String,
        category: String? = null,
        modelName: String = "product_ranking_v1",
        windowSize: Int = 200
    ): SearchResult {
        val ltrParams = buildMap<String, Any> {
            put("keywords", keyword)
            category?.let { put("category", it) }
        }

        val rescoreJson = """
        {
          "window_size": $windowSize,
          "query": {
            "rescore_query": {
              "sltr": {
                "params": ${objectMapper.writeValueAsString(ltrParams)},
                "model": "$modelName"
              }
            },
            "query_weight": 0,
            "rescore_query_weight": 1,
            "score_mode": "total"
          }
        }
        """.trimIndent()

        // first-pass 쿼리 + LTR rescore (withJson으로 rescore 부분 주입)
        val queryJson = """
        {
          "query": {
            "bool": {
              "must": [
                {
                  "multi_match": {
                    "query": ${objectMapper.writeValueAsString(keyword)},
                    "fields": ["title^3", "title.search^2", "description"],
                    "type": "best_fields"
                  }
                }
              ]
              ${category?.let {
                """, "filter": [{"term": {"category": ${objectMapper.writeValueAsString(it)}}}]"""
              } ?: ""}
            }
          },
          "rescore": $rescoreJson,
          "size": 20
        }
        """.trimIndent()

        val request = SearchRequest.of { s ->
            s.index("products").withJson(StringReader(queryJson))
        }

        val response = client.search(request, Product::class.java)

        return SearchResult(
            items = response.hits().hits().mapNotNull { it.source() },
            total = response.hits().total()?.value() ?: 0,
            maxScore = response.hits().maxScore()
        )
    }

    companion object {
        private val objectMapper = ObjectMapper()
    }
}
```

## 5. Query Understanding

### Query Classification

| Query Type | 특성 | 예시 | Routing 전략 |
|-----------|------|------|-------------|
| **Navigational** | 특정 상품/브랜드 탐색 | "갤럭시 버즈3", "애플 에어팟" | exact match boost + brand filter |
| **Informational** | 정보 탐색, 비교 | "무선 이어폰 추천", "노트북 비교" | broad match + aggregation + 리뷰 |
| **Transactional** | 구매 의도 명확 | "이어폰 최저가", "무선 이어폰 할인" | price sort + deal filter + availability |
| **Category** | 카테고리 브라우징 | "이어폰", "신발" | category landing + facets |
| **Long-tail** | 구체적 속성 조합 | "삼성 무선 이어폰 노이즈캔슬링 화이트" | 모든 조건 필터 + relaxation 대비 |

### Query Expansion via significant_terms

```json
// "이어폰" 검색 사용자가 자주 함께 사용하는 용어 추출
POST /search_logs/_search
{
  "query": {
    "match": {
      "query_text": "이어폰"
    }
  },
  "aggregations": {
    "significant_related_terms": {
      "significant_terms": {
        "field": "clicked_product_tags",
        "size": 10,
        "min_doc_count": 5,
        "mutual_information": {
          "include_negatives": false,
          "background_is_superset": true
        }
      }
    }
  },
  "size": 0
}
// 결과: ["블루투스", "노이즈캔슬링", "무선", "갤럭시버즈", "에어팟"]
// → 쿼리 확장 또는 관련 검색어 추천에 활용
```

### Spell Correction (Phrase Suggester)

```json
// 한국어 오타 교정: phrase suggester
POST /products/_search
{
  "suggest": {
    "spell_check": {
      "text": "삼섯 무선 이어폰",
      "phrase": {
        "field": "title.trigram",
        "size": 3,
        "gram_size": 3,
        "confidence": 1.0,
        "direct_generator": [
          {
            "field": "title.trigram",
            "suggest_mode": "always",
            "min_word_length": 2
          }
        ],
        "collate": {
          "query": {
            "source": {
              "match": {
                "title": "{{suggestion}}"
              }
            }
          },
          "prune": true
        },
        "highlight": {
          "pre_tag": "<em>",
          "post_tag": "</em>"
        }
      }
    }
  }
}
```

**Trigram 분석기 설정** (spell correction 전제 조건):

```json
PUT /products
{
  "settings": {
    "analysis": {
      "filter": {
        "trigram_filter": {
          "type": "ngram",
          "min_gram": 3,
          "max_gram": 3
        }
      },
      "analyzer": {
        "trigram_analyzer": {
          "type": "custom",
          "tokenizer": "standard",
          "filter": ["lowercase", "trigram_filter"]
        }
      }
    }
  },
  "mappings": {
    "properties": {
      "title": {
        "type": "text",
        "fields": {
          "trigram": {
            "type": "text",
            "analyzer": "trigram_analyzer"
          }
        }
      }
    }
  }
}
```

### Query Relaxation Cascade (Kotlin)

```kotlin
@Service
class QueryRelaxationService(
    private val client: ElasticsearchClient
) {
    /**
     * 쿼리 완화 캐스케이드: 결과가 부족하면 점진적으로 필터를 완화합니다.
     *
     * Level 0: 전체 필터 적용 (brand + category + attributes)
     * Level 1: attribute 필터 제거
     * Level 2: brand 필터 제거
     * Level 3: category 필터 제거
     * Level 4: fuzzy 매칭으로 전환
     */
    suspend fun searchWithRelaxation(
        keyword: String,
        brand: String? = null,
        category: String? = null,
        attributes: Map<String, String> = emptyMap(),
        minResults: Int = 5
    ): RelaxedSearchResult = withContext(Dispatchers.IO) {

        // Level 0: 전체 필터
        val level0 = executeSearch(keyword, brand, category, attributes, fuzzy = false)
        if (level0.totalHits >= minResults) {
            return@withContext RelaxedSearchResult(level0.items, relaxationLevel = 0)
        }

        // Level 1: attribute 필터 제거
        val level1 = executeSearch(keyword, brand, category, emptyMap(), fuzzy = false)
        if (level1.totalHits >= minResults) {
            return@withContext RelaxedSearchResult(level1.items, relaxationLevel = 1)
        }

        // Level 2: brand 필터 제거
        val level2 = executeSearch(keyword, null, category, emptyMap(), fuzzy = false)
        if (level2.totalHits >= minResults) {
            return@withContext RelaxedSearchResult(level2.items, relaxationLevel = 2)
        }

        // Level 3: category 필터 제거
        val level3 = executeSearch(keyword, null, null, emptyMap(), fuzzy = false)
        if (level3.totalHits >= minResults) {
            return@withContext RelaxedSearchResult(level3.items, relaxationLevel = 3)
        }

        // Level 4: fuzzy 매칭
        val level4 = executeSearch(keyword, null, null, emptyMap(), fuzzy = true)
        return@withContext RelaxedSearchResult(level4.items, relaxationLevel = 4)
    }

    private fun executeSearch(
        keyword: String,
        brand: String?,
        category: String?,
        attributes: Map<String, String>,
        fuzzy: Boolean
    ): RawSearchResult {
        val response = client.search({ s ->
            s.index("products")
                .query { q ->
                    q.bool { b ->
                        // 텍스트 매칭
                        b.must { m ->
                            if (fuzzy) {
                                m.match { mt ->
                                    mt.field("title").query(keyword).fuzziness("AUTO")
                                }
                            } else {
                                m.multiMatch { mm ->
                                    mm.query(keyword)
                                        .fields("title^3", "description")
                                        .type(TextQueryType.BestFields)
                                }
                            }
                        }
                        // 조건부 필터
                        brand?.let { b0 ->
                            b.filter { f -> f.term { t -> t.field("brand").value(b0) } }
                        }
                        category?.let { c ->
                            b.filter { f -> f.term { t -> t.field("category").value(c) } }
                        }
                        attributes.forEach { (key, value) ->
                            b.filter { f ->
                                f.term { t -> t.field("attributes.$key").value(value) }
                            }
                        }
                        b
                    }
                }
                .size(20)
        }, Product::class.java)

        val hits = response.hits().hits()
        return RawSearchResult(
            items = hits.mapNotNull { it.source() },
            totalHits = response.hits().total()?.value() ?: 0
        )
    }
}

data class RelaxedSearchResult(
    val items: List<Product>,
    val relaxationLevel: Int  // 0=exact, 1=no-attr, 2=no-brand, 3=no-category, 4=fuzzy
)

private data class RawSearchResult(
    val items: List<Product>,
    val totalHits: Long
)
```

### Intent Detection Routing

```kotlin
@Component
class QueryIntentDetector {

    private val navigationalPatterns = listOf(
        Regex("^(삼성|애플|소니|LG|나이키|아디다스)\\s+.+"),  // 브랜드 + 상품
        Regex(".+\\s+(공식|정품|오리지널)$"),                  // 공식/정품 의도
        Regex("^[A-Za-z0-9\\-]+$"),                          // 모델명 (영문숫자)
    )

    private val transactionalPatterns = listOf(
        Regex(".+(최저가|할인|세일|쿠폰|특가)$"),
        Regex("^(싸게|저렴하게)\\s+.+"),
        Regex(".+\\s+(구매|주문|배송)$"),
    )

    private val informationalPatterns = listOf(
        Regex(".+(추천|비교|리뷰|후기|차이)$"),
        Regex("^(어떤|무슨|뭐가|뭘)\\s+.+"),
        Regex(".+(좋은지|나은지|어때)$"),
    )

    fun detectIntent(query: String): QueryIntent {
        val trimmed = query.trim()

        return when {
            navigationalPatterns.any { it.matches(trimmed) } -> QueryIntent.NAVIGATIONAL
            transactionalPatterns.any { it.matches(trimmed) } -> QueryIntent.TRANSACTIONAL
            informationalPatterns.any { it.matches(trimmed) } -> QueryIntent.INFORMATIONAL
            trimmed.split("\\s+".toRegex()).size <= 1 -> QueryIntent.CATEGORY
            else -> QueryIntent.INFORMATIONAL
        }
    }

    fun routeSearch(query: String): SearchStrategy {
        return when (detectIntent(query)) {
            QueryIntent.NAVIGATIONAL -> SearchStrategy(
                boostExactMatch = true,
                enableBrandFilter = true,
                sortBy = SortBy.RELEVANCE,
                rescoreWindow = 50
            )
            QueryIntent.TRANSACTIONAL -> SearchStrategy(
                boostExactMatch = false,
                enableBrandFilter = false,
                sortBy = SortBy.PRICE_ASC,
                rescoreWindow = 0,  // rescore 불필요
                filterAvailable = true
            )
            QueryIntent.INFORMATIONAL -> SearchStrategy(
                boostExactMatch = false,
                enableBrandFilter = false,
                sortBy = SortBy.RELEVANCE,
                rescoreWindow = 100,
                includeAggregations = true
            )
            QueryIntent.CATEGORY -> SearchStrategy(
                boostExactMatch = false,
                enableBrandFilter = false,
                sortBy = SortBy.POPULARITY,
                rescoreWindow = 200,
                includeFacets = true
            )
        }
    }
}

enum class QueryIntent { NAVIGATIONAL, TRANSACTIONAL, INFORMATIONAL, CATEGORY }

data class SearchStrategy(
    val boostExactMatch: Boolean = false,
    val enableBrandFilter: Boolean = false,
    val sortBy: SortBy = SortBy.RELEVANCE,
    val rescoreWindow: Int = 100,
    val filterAvailable: Boolean = false,
    val includeAggregations: Boolean = false,
    val includeFacets: Boolean = false
)

enum class SortBy { RELEVANCE, PRICE_ASC, PRICE_DESC, POPULARITY, RECENCY }
```

## 6. Result Diversification

### field_collapse로 브랜드 다양성 확보

```json
// 브랜드당 1개만 메인 노출, 나머지는 inner_hits로 접근
POST /products/_search
{
  "query": {
    "match": { "title": "무선 이어폰" }
  },
  "collapse": {
    "field": "brand",
    "inner_hits": {
      "name": "brand_variants",
      "size": 3,
      "sort": [{ "_score": "desc" }],
      "_source": ["title", "price", "brand"]
    },
    "max_concurrent_group_searches": 4
  },
  "sort": [{ "_score": "desc" }],
  "size": 10
}
```

**응답 구조**:
```json
{
  "hits": {
    "hits": [
      {
        "_source": { "title": "삼성 갤럭시 버즈3", "brand": "삼성" },
        "inner_hits": {
          "brand_variants": {
            "hits": {
              "hits": [
                { "_source": { "title": "삼성 갤럭시 버즈3 프로", "brand": "삼성" } },
                { "_source": { "title": "삼성 갤럭시 버즈FE", "brand": "삼성" } }
              ]
            }
          }
        }
      },
      {
        "_source": { "title": "애플 에어팟 프로 2", "brand": "애플" }
      }
    ]
  }
}
```

### Pinned Queries로 머천다이징

```json
// 특정 상품을 최상위에 고정 (프로모션, 광고, 큐레이션)
POST /products/_search
{
  "query": {
    "pinned": {
      "ids": ["promo_001", "promo_002", "promo_003"],
      "organic": {
        "multi_match": {
          "query": "무선 이어폰",
          "fields": ["title^3", "description"]
        }
      }
    }
  },
  "size": 20
}
```

**pinned query 동작**:
- `ids`에 지정된 문서가 항상 최상위에 위치
- 나머지는 `organic` 쿼리 결과 순서대로 배치
- 지정된 ID의 문서가 존재하지 않으면 무시됨
- 최대 100개까지 pinning 가능 (성능 고려)

### MMR (Maximal Marginal Relevance) Post-Processing

ES에서 직접 MMR을 지원하지 않으므로 애플리케이션 레벨에서 구현합니다.

```kotlin
/**
 * MMR (Maximal Marginal Relevance) 기반 결과 다양화.
 * MMR = λ * Sim(d, q) - (1-λ) * max(Sim(d, d_selected))
 *
 * @param lambda 관련성 vs 다양성 가중치 (1.0 = 관련성만, 0.0 = 다양성만)
 */
class MmrDiversifier(
    private val lambda: Double = 0.7
) {
    fun diversify(
        candidates: List<ScoredDocument>,
        topK: Int = 20
    ): List<ScoredDocument> {
        if (candidates.size <= topK) return candidates

        val selected = mutableListOf<ScoredDocument>()
        val remaining = candidates.toMutableList()

        // 첫 번째는 최고 스코어 문서
        val first = remaining.maxByOrNull { it.score } ?: return emptyList()
        selected.add(first)
        remaining.remove(first)

        // 나머지는 MMR 기준으로 선택
        while (selected.size < topK && remaining.isNotEmpty()) {
            val best = remaining.maxByOrNull { candidate ->
                val relevance = candidate.score / (candidates.maxOf { it.score })
                val maxSimilarity = selected.maxOf { sel ->
                    computeSimilarity(candidate, sel)
                }
                lambda * relevance - (1 - lambda) * maxSimilarity
            } ?: break

            selected.add(best)
            remaining.remove(best)
        }

        return selected
    }

    /**
     * 카테고리 + 브랜드 기반 유사도 계산 (0.0 ~ 1.0).
     * 벡터 기반 유사도가 필요하면 코사인 유사도로 교체.
     */
    private fun computeSimilarity(a: ScoredDocument, b: ScoredDocument): Double {
        var similarity = 0.0
        if (a.category == b.category) similarity += 0.5
        if (a.brand == b.brand) similarity += 0.3
        if (a.priceRange == b.priceRange) similarity += 0.2
        return similarity
    }
}

data class ScoredDocument(
    val id: String,
    val score: Double,
    val category: String,
    val brand: String,
    val priceRange: String  // "low", "mid", "high"
)
```

## 7. Personalization in Search

### function_score with User Profile Boosting

```json
// 사용자 선호 기반 개인화 점수 가산
POST /products/_search
{
  "query": {
    "function_score": {
      "query": {
        "multi_match": {
          "query": "이어폰",
          "fields": ["title^3", "description"]
        }
      },
      "functions": [
        {
          "filter": {
            "term": { "category": "electronics" }
          },
          "weight": 1.5,
          "_comment": "사용자가 선호하는 카테고리 boost"
        },
        {
          "filter": {
            "terms": { "brand": ["삼성", "애플"] }
          },
          "weight": 1.3,
          "_comment": "최근 30일 내 클릭/구매한 브랜드 boost"
        },
        {
          "filter": {
            "range": {
              "price": {
                "gte": 100000,
                "lte": 300000
              }
            }
          },
          "weight": 1.2,
          "_comment": "사용자의 주요 가격대 boost"
        },
        {
          "filter": {
            "term": { "is_free_shipping": true }
          },
          "weight": 1.1,
          "_comment": "무료배송 선호 사용자 boost"
        }
      ],
      "score_mode": "sum",
      "boost_mode": "multiply",
      "max_boost": 3.0
    }
  },
  "size": 20
}
```

### Session-Based Personalization Signals

| Signal | 수집 방법 | 적용 방식 | 반영 시점 |
|--------|----------|----------|----------|
| **최근 본 카테고리** | 세션 내 클릭 로그 | category boost (weight 1.2~1.5) | 실시간 |
| **최근 본 브랜드** | 세션 내 클릭 로그 | brand boost (weight 1.1~1.3) | 실시간 |
| **가격대 선호** | 클릭/구매 가격 분포 | price range filter boost | 세션 내 |
| **카트 내 상품** | 장바구니 데이터 | 보완재/대체재 boost | 실시간 |
| **검색 히스토리** | 세션 내 이전 쿼리 | query expansion 재료 | 세션 내 |

```kotlin
@Service
class PersonalizedSearchService(
    private val client: ElasticsearchClient,
    private val userProfileService: UserProfileService
) {
    suspend fun personalizedSearch(
        keyword: String,
        userId: String
    ): SearchResult = withContext(Dispatchers.IO) {
        val profile = userProfileService.getProfile(userId)

        val functions = mutableListOf<String>()

        // 선호 카테고리 boost
        profile.preferredCategories.takeIf { it.isNotEmpty() }?.let { cats ->
            functions.add("""
                {
                  "filter": { "terms": { "category": ${objectMapper.writeValueAsString(cats)} } },
                  "weight": 1.4
                }
            """.trimIndent())
        }

        // 선호 브랜드 boost
        profile.preferredBrands.takeIf { it.isNotEmpty() }?.let { brands ->
            functions.add("""
                {
                  "filter": { "terms": { "brand": ${objectMapper.writeValueAsString(brands)} } },
                  "weight": 1.3
                }
            """.trimIndent())
        }

        // 가격대 boost
        profile.priceRange?.let { range ->
            functions.add("""
                {
                  "filter": { "range": { "price": { "gte": ${range.first}, "lte": ${range.last} } } },
                  "weight": 1.2
                }
            """.trimIndent())
        }

        val queryJson = """
        {
          "query": {
            "function_score": {
              "query": {
                "multi_match": {
                  "query": ${objectMapper.writeValueAsString(keyword)},
                  "fields": ["title^3", "description"],
                  "type": "best_fields"
                }
              },
              "functions": [${functions.joinToString(",")}],
              "score_mode": "sum",
              "boost_mode": "multiply",
              "max_boost": 3.0
            }
          },
          "size": 20
        }
        """.trimIndent()

        val request = SearchRequest.of { s ->
            s.index("products").withJson(StringReader(queryJson))
        }
        val response = client.search(request, Product::class.java)

        SearchResult(
            items = response.hits().hits().mapNotNull { it.source() },
            total = response.hits().total()?.value() ?: 0,
            maxScore = response.hits().maxScore()
        )
    }

    companion object {
        private val objectMapper = ObjectMapper()
    }
}
```

### Collaborative Filtering as Document-Level Features

| 방식 | 설명 | 구현 | 장단점 |
|------|------|------|--------|
| **Pre-computed CF score** | 사용자-상품 유사도를 사전 계산하여 문서 필드에 저장 | 배치로 `cf_score_segment_{A,B,C}` 인덱싱 | 검색 시 빠름, 갱신 주기에 종속 |
| **User segment boost** | 사용자 세그먼트별 인기 상품에 가중치 | `function_score` filter by segment | 구현 간단, 개인화 수준 낮음 |
| **Real-time embedding** | 사용자/상품 임베딩 벡터 유사도 | kNN + RRF retriever 활용 | 정밀하지만 인프라 복잡 |

### Privacy 고려사항

| 원칙 | 설명 | 구현 방법 |
|------|------|----------|
| **데이터 최소화** | 개인화에 필요한 최소 데이터만 수집 | 카테고리/브랜드 수준 집계, 개별 상품 기록 X |
| **익명화** | 사용자 식별 불가능하게 처리 | 해시된 세션 ID, 세그먼트 기반 집계 |
| **TTL** | 개인화 데이터 보존 기간 제한 | 세션 데이터 24h, 프로필 90일 TTL |
| **Opt-out** | 사용자가 개인화를 비활성화할 수 있어야 함 | API 파라미터로 `personalized=false` 지원 |
| **쿼리 로그 분리** | 검색 로그에 PII 미포함 | 사용자 ID 대신 익명 세션 ID만 기록 |

## 8. Multi-Stage Retrieval Architecture

### 아키텍처 다이어그램

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    Multi-Stage Retrieval Pipeline                        │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ┌─────────────────┐                                                    │
│  │   User Query     │                                                    │
│  └────────┬────────┘                                                    │
│           ▼                                                             │
│  ┌─────────────────┐  < 10ms                                            │
│  │  L0: Query       │  spell check, intent detection,                   │
│  │  Understanding   │  query expansion, 한영 변환                        │
│  └────────┬────────┘                                                    │
│           ▼                                                             │
│  ┌─────────────────┐  < 50ms         ┌──────────────────┐              │
│  │  L1: Candidate   │  BM25 + kNN ──→│ ~1000 candidates │              │
│  │  Generation      │  broad recall   └────────┬─────────┘              │
│  └────────┬────────┘                           │                        │
│           ▼                                    ▼                        │
│  ┌─────────────────┐  < 20ms         ┌──────────────────┐              │
│  │  L2: Lightweight │  rescore        │ ~200 candidates  │              │
│  │  Scoring         │  phrase boost   └────────┬─────────┘              │
│  └────────┬────────┘                           │                        │
│           ▼                                    ▼                        │
│  ┌─────────────────┐  < 100ms        ┌──────────────────┐              │
│  │  L3: Heavy       │  LTR model /   │ ~50 candidates   │              │
│  │  Reranking       │  cross-encoder  └────────┬─────────┘              │
│  └────────┬────────┘                           │                        │
│           ▼                                    ▼                        │
│  ┌─────────────────┐  < 10ms         ┌──────────────────┐              │
│  │  L4: Business    │  pinning,       │ ~20 final results│              │
│  │  Rules           │  diversity,     └──────────────────┘              │
│  └────────┬────────┘  personalization                                   │
│           ▼                                                             │
│  ┌─────────────────┐                                                    │
│  │   Final Results  │  Total latency < 200ms                            │
│  └─────────────────┘                                                    │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### 단계별 레이턴시 버짓

| Stage | 목표 레이턴시 | 문서 수 | 역할 | 주요 기술 |
|-------|-------------|---------|------|----------|
| **L0** | < 10ms | - | 쿼리 전처리 | spell check, intent, 한영 변환 |
| **L1** | < 50ms | 전체 → ~1000 | 후보 생성 | BM25, kNN, RRF |
| **L2** | < 20ms | ~1000 → ~200 | 경량 재순위화 | rescore (phrase, recency) |
| **L3** | < 100ms | ~200 → ~50 | 정밀 재순위화 | LTR, cross-encoder |
| **L4** | < 10ms | ~50 → ~20 | 비즈니스 규칙 | pinning, diversity, personalization |
| **Total** | **< 200ms** | - | 전체 파이프라인 | - |

### 단계 추가 판단 기준

| 현재 상태 | 추가할 단계 | 판단 기준 |
|----------|-----------|----------|
| L1만 운영 | L0 (Query Understanding) | zero-result rate > 5%, 오타 비율 높음 |
| L0 + L1 | L2 (Rescore) | exact match가 상위에 안 나옴, NDCG 정체 |
| L0 + L1 + L2 | L3 (LTR) | 충분한 클릭 로그 확보, NDCG 오프라인 평가 준비 |
| L0~L3 | L4 (Business Rules) | 머천다이징/프로모션 요구, 결과 다양성 민원 |

### Kotlin MultiStageSearchService

```kotlin
@Service
class MultiStageSearchService(
    private val queryUnderstanding: QueryUnderstandingService,
    private val candidateGenerator: CandidateGenerationService,
    private val lightweightScorer: LightweightScoringService,
    private val heavyReranker: HeavyRerankingService,
    private val businessRules: BusinessRulesService,
    private val meterRegistry: MeterRegistry
) {
    private val logger = LoggerFactory.getLogger(javaClass)

    /**
     * 다단계 검색 파이프라인 실행.
     * 각 단계의 레이턴시를 측정하고, 실패 시 이전 단계 결과로 fallback.
     */
    suspend fun search(request: SearchRequest): SearchResponse {
        val timer = Timer.start(meterRegistry)

        // ── L0: Query Understanding ──
        val l0Result = measureStage("l0_query_understanding") {
            try {
                queryUnderstanding.process(request.query)
            } catch (e: Exception) {
                logger.warn("L0 failed, using raw query", e)
                QueryUnderstandingResult(
                    originalQuery = request.query,
                    processedQuery = request.query,
                    intent = QueryIntent.INFORMATIONAL,
                    corrections = emptyList()
                )
            }
        }
        logger.debug("L0 result: intent={}, corrected={}", l0Result.intent, l0Result.processedQuery)

        // ── L1: Candidate Generation ──
        val l1Result = measureStage("l1_candidate_generation") {
            candidateGenerator.generate(
                query = l0Result.processedQuery,
                intent = l0Result.intent,
                filters = request.filters,
                maxCandidates = 1000
            )
        }
        logger.debug("L1 candidates: {} docs", l1Result.size)

        if (l1Result.isEmpty()) {
            timer.stop(meterRegistry.timer("search.pipeline.total", "status", "no_results"))
            return SearchResponse(
                items = emptyList(),
                total = 0,
                metadata = SearchMetadata(
                    relaxationLevel = null,
                    corrections = l0Result.corrections
                )
            )
        }

        // ── L2: Lightweight Scoring ──
        val l2Result = measureStage("l2_lightweight_scoring") {
            try {
                lightweightScorer.score(
                    candidates = l1Result,
                    query = l0Result.processedQuery,
                    windowSize = 200
                )
            } catch (e: Exception) {
                logger.warn("L2 failed, using L1 results", e)
                l1Result.take(200)
            }
        }
        logger.debug("L2 scored: {} docs", l2Result.size)

        // ── L3: Heavy Reranking ──
        val l3Result = measureStage("l3_heavy_reranking") {
            try {
                heavyReranker.rerank(
                    candidates = l2Result,
                    query = l0Result.processedQuery,
                    intent = l0Result.intent,
                    topK = 50
                )
            } catch (e: Exception) {
                logger.warn("L3 failed, using L2 results", e)
                l2Result.take(50)
            }
        }
        logger.debug("L3 reranked: {} docs", l3Result.size)

        // ── L4: Business Rules ──
        val l4Result = measureStage("l4_business_rules") {
            try {
                businessRules.apply(
                    candidates = l3Result,
                    userId = request.userId,
                    query = l0Result.processedQuery,
                    intent = l0Result.intent,
                    topK = request.size
                )
            } catch (e: Exception) {
                logger.warn("L4 failed, using L3 results", e)
                l3Result.take(request.size)
            }
        }

        timer.stop(meterRegistry.timer("search.pipeline.total", "status", "success"))

        return SearchResponse(
            items = l4Result,
            total = l1Result.size.toLong(),
            metadata = SearchMetadata(
                corrections = l0Result.corrections,
                intent = l0Result.intent,
                stages = StageMetrics(
                    l1Candidates = l1Result.size,
                    l2Scored = l2Result.size,
                    l3Reranked = l3Result.size,
                    l4Final = l4Result.size
                )
            )
        )
    }

    private suspend fun <T> measureStage(stageName: String, block: suspend () -> T): T {
        val start = System.nanoTime()
        try {
            val result = block()
            val durationMs = (System.nanoTime() - start) / 1_000_000.0
            meterRegistry.timer("search.stage.duration", "stage", stageName, "status", "success")
                .record(durationMs.toLong(), TimeUnit.MILLISECONDS)
            return result
        } catch (e: Exception) {
            val durationMs = (System.nanoTime() - start) / 1_000_000.0
            meterRegistry.timer("search.stage.duration", "stage", stageName, "status", "error")
                .record(durationMs.toLong(), TimeUnit.MILLISECONDS)
            throw e
        }
    }
}

data class SearchRequest(
    val query: String,
    val filters: Map<String, Any> = emptyMap(),
    val userId: String? = null,
    val size: Int = 20
)

data class SearchResponse(
    val items: List<Product>,
    val total: Long,
    val metadata: SearchMetadata
)

data class SearchMetadata(
    val corrections: List<String> = emptyList(),
    val intent: QueryIntent? = null,
    val relaxationLevel: Int? = null,
    val stages: StageMetrics? = null
)

data class StageMetrics(
    val l1Candidates: Int,
    val l2Scored: Int,
    val l3Reranked: Int,
    val l4Final: Int
)
```

## 9. Anti-Patterns

| Anti-Pattern | 문제 | 올바른 접근 | Severity |
|-------------|------|-----------|----------|
| rescore `window_size` > 500 without justification | 레이턴시 급증, first-pass 이점 상실 | 벤치마크 기반으로 적정 window_size 결정 (보통 100~200) | **High** |
| LTR 모델 배포 without offline evaluation | 프로덕션에서 검색 품질 저하 감지 못함 | 배포 전 NDCG@10 오프라인 평가 필수, 기존 대비 개선 증명 | **Critical** |
| Reranking on unfiltered full result set | O(N) 스코어링으로 레이턴시 폭증 | first-pass로 후보 축소 후 상위 N개만 reranking | **High** |
| Personalization에 PII를 query logs에 저장 | 개인정보 유출 위험, 법적 이슈 | 익명 세션 ID만 기록, PII는 별도 암호화 저장소에서 관리 | **Critical** |
| 모든 단계를 single ES query에 구현 | 디버깅 불가, 단계별 최적화 불가 | 각 단계를 독립 컴포넌트로 분리, 단계별 메트릭 수집 | **Medium** |
| 새 ranking 단계 추가 시 A/B test 없이 배포 | 개선/악화 판단 불가, 롤백 근거 없음 | 트래픽 일부에만 적용 후 NDCG, CTR 비교 | **High** |
| Query relaxation without logging | 어떤 단계에서 결과를 찾았는지 추적 불가 | relaxation level을 응답 메타데이터에 포함, 로그로 수집 | **Medium** |
| Cross-encoder reranking without timeout | 외부 inference 서비스 장애 시 전체 검색 중단 | 타임아웃 + fallback (L2 결과로 대체) 필수 | **High** |
| Feature set 변경 후 모델 재학습 없이 사용 | feature 순서/의미 불일치로 예측 오류 | feature set 변경 시 반드시 모델 재학습 + 재배포 | **Critical** |
| 개인화 boost weight를 하드코딩 | 환경별 최적값 다름, 튜닝 어려움 | 설정 파일 또는 remote config로 외부화 | **Medium** |

---

**Remember**: 다단계 검색은 점진적으로 구축하세요. L1(BM25 검색)에서 시작하고, 오프라인 평가(NDCG)로 병목을 확인한 후 필요한 단계만 추가하세요. 모든 단계를 한 번에 도입하는 것은 복잡성만 증가시킵니다. rescore는 가장 비용 대비 효과가 큰 재순위화 방법입니다.
