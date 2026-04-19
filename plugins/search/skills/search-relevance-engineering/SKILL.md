---
name: search-relevance-engineering
description: Use this skill when tuning search relevance, designing analyzers, configuring multi-field search, managing synonyms, or evaluating search quality. Covers BM25 tuning, Korean analyzer design, and search quality metrics.
---

# Search Relevance Engineering

검색 품질(relevance)을 설계하고 측정하는 종합 가이드입니다. 스코어링 원리, 분석기 설계, 다중 필드 검색, 동의어 관리, 품질 평가까지 다룹니다.

## When to Activate

- 검색 결과 품질 개선 또는 relevance 튜닝 시
- 새로운 analyzer 설계 또는 기존 analyzer 수정 시
- multi_match, function_score 등 검색 쿼리 최적화 시
- 동의어 사전 구축 또는 관리 시
- 검색 품질 평가 메트릭 설계 또는 측정 시
- BM25 파라미터 조정 검토 시
- 한국어 형태소 분석기 설정 시

## 1. Relevance Scoring Fundamentals

### BM25 알고리즘 이해

Elasticsearch 기본 스코어링 알고리즘. 두 핵심 파라미터:

| Parameter | Default | 역할 | 효과 |
|-----------|---------|------|------|
| **k1** | 1.2 | term frequency saturation | 높을수록 TF 영향 증가 |
| **b** | 0.75 | field-length normalization | 높을수록 짧은 필드 선호 |

**k1 튜닝 가이드**:
- `k1 = 0`: TF 무시 (키워드 반복 무의미)
- `k1 = 1.2` (기본): 대부분의 경우 적절
- `k1 > 2.0`: 긴 문서에서 반복 등장이 중요한 경우 (논문, 블로그)
- 상품 검색은 기본값 유지 권장 (제목이 짧아 TF 변동 적음)

**b 튜닝 가이드**:
- `b = 0`: 필드 길이 무시 (긴 문서와 짧은 문서 동등 취급)
- `b = 0.75` (기본): 짧은 필드에 약간의 보너스
- `b = 1.0`: 필드 길이 정규화 극대화
- 상품 제목 검색: `b = 0.3` 정도로 낮추면 긴 제목 불이익 완화

```json
// 인덱스 레벨 BM25 파라미터 커스텀
PUT /products
{
  "settings": {
    "index": {
      "similarity": {
        "custom_bm25": {
          "type": "BM25",
          "k1": "1.2",
          "b": "0.3"
        }
      }
    }
  },
  "mappings": {
    "properties": {
      "title": {
        "type": "text",
        "similarity": "custom_bm25"
      }
    }
  }
}
```

### Practical Tuning 예시

```
문제: "삼성 갤럭시 S24 울트라 256GB" 같은 긴 제목이 "갤럭시 S24"보다 점수가 낮음
원인: b=0.75가 긴 제목에 페널티 적용
해결: b를 0.3으로 낮춰 필드 길이 페널티 완화

문제: "이어폰 이어폰 이어폰" 같은 키워드 스터핑이 높은 점수
원인: k1이 높아 TF가 과도하게 반영
해결: k1을 0.8로 낮추거나, 쿼리 레벨에서 제한
```

## 2. Analyzer Design Workflow

### 5-Step Process

```
Step 1: Define Requirements
  ├── 대상 언어 (한국어, 영어, 혼합)
  ├── 검색 시나리오 (full-text, autocomplete, exact)
  └── 토큰화 수준 (형태소, 어절, 음절)

Step 2: Select Tokenizer
  ├── Korean → nori_tokenizer
  ├── English → standard
  ├── Autocomplete → edge_ngram
  └── 패턴 기반 → pattern tokenizer

Step 3: Design Filter Chain
  ├── nori_part_of_speech (불용 품사 제거)
  ├── nori_readingform (한자 → 한글)
  ├── lowercase
  ├── synonym_graph (동의어)
  └── stop (불용어)

Step 4: Test with _analyze API
  └── 각 단계별 토큰 출력 확인

Step 5: Validate with Sample Queries
  └── 실제 검색 쿼리로 relevance 검증
```

### _analyze API 활용

```json
// 단계별 토큰 분석
POST /products/_analyze
{
  "analyzer": "nori_standard",
  "text": "삼성전자 무선 이어폰 갤럭시 버즈3",
  "explain": true
}

// 특정 tokenizer만 테스트
POST /_analyze
{
  "tokenizer": {
    "type": "nori_tokenizer",
    "decompound_mode": "mixed"
  },
  "text": "삼성전자"
}
// 결과: ["삼성전자", "삼성", "전자"]
```

### Korean-Specific: Nori Tokenizer 설정

```json
{
  "settings": {
    "analysis": {
      "tokenizer": {
        "nori_mixed": {
          "type": "nori_tokenizer",
          "decompound_mode": "mixed",
          "user_dictionary_rules": [
            "삼성전자", "갤럭시버즈", "에어팟프로", "쿠팡로켓"
          ],
          "discard_punctuation": true
        }
      },
      "filter": {
        "pos_filter": {
          "type": "nori_part_of_speech",
          "stoptags": ["E", "IC", "J", "MAG", "MAJ", "MM",
                       "SP", "SSC", "SSO", "SC", "SE",
                       "XPN", "XSA", "XSN", "XSV",
                       "UNA", "NA", "VSV"]
        }
      },
      "analyzer": {
        "nori_standard": {
          "type": "custom",
          "tokenizer": "nori_mixed",
          "filter": ["pos_filter", "nori_readingform", "lowercase"]
        },
        "nori_search": {
          "type": "custom",
          "tokenizer": "nori_mixed",
          "filter": ["pos_filter", "nori_readingform", "lowercase", "synonym_filter"]
        }
      }
    }
  }
}
```

### Custom Morphological Analyzer Integration

Nori 외 사내 자체 형태소 분석기 플러그인 통합 시:

```json
{
  "analyzer": {
    "custom_korean_analyzer": {
      "type": "custom",
      "tokenizer": "custom_morph_tokenizer",
      "filter": ["lowercase", "custom_pos_filter", "synonym_filter"]
    }
  }
}
```

- 플러그인 JAR을 모든 노드 `plugins/` 디렉토리에 배포
- `elasticsearch.yml`에서 플러그인 활성화 확인
- 클러스터 롤링 리스타트로 적용 (shard allocation 일시 비활성화)
- _analyze API로 토큰화 결과 검증 후 인덱스 적용

## 3. Multi-Field Search Strategy

### multi_match Type Decision Matrix

| Type | 동작 | 적합 케이스 | 예시 |
|------|------|-----------|------|
| `best_fields` | 가장 높은 점수 필드 사용 | 하나의 필드에 정답이 있을 때 | 상품명 or 설명 중 하나 |
| `most_fields` | 모든 필드 점수 합산 | 동일 내용의 다중 분석 | `title` + `title.search` |
| `cross_fields` | 모든 필드를 하나처럼 | 이름+성 같은 분산 정보 | `first_name` + `last_name` |
| `phrase` | 구문 매칭 | 어순이 중요한 검색 | 영화 제목, 노래 가사 |
| `phrase_prefix` | 접두사 구문 매칭 | 자동완성 | 타이핑 중 실시간 검색 |

### Field Boost 전략

```json
{
  "query": {
    "multi_match": {
      "query": "무선 이어폰",
      "type": "best_fields",
      "fields": [
        "title^5",           // 제목 최우선
        "title.search^3",    // 검색 최적화 분석 결과
        "brand^2",           // 브랜드명
        "description",       // 설명 (boost 1, 기본)
        "tags^1.5"           // 태그
      ],
      "tie_breaker": 0.3
    }
  }
}
```

**`tie_breaker` 역할**: `best_fields`에서 최고 점수 필드 외 나머지 필드 점수 반영 비율. 0이면 최고만, 1이면 `most_fields`와 동일. 보통 `0.1 ~ 0.3` 권장.

### copy_to vs multi_match

| 전략 | 장점 | 단점 |
|------|------|------|
| `copy_to` | 단일 필드 쿼리, 성능 좋음 | 필드별 boost 불가, 인덱스 크기 증가 |
| `multi_match` | 필드별 boost 가능, 유연 | 쿼리 복잡, 약간 느릴 수 있음 |

```json
// copy_to 예시
"title": { "type": "text", "copy_to": "all_text" },
"description": { "type": "text", "copy_to": "all_text" },
"all_text": { "type": "text" }
```

**권장**: 필드별 가중치가 필요하면 `multi_match`, 단순 통합 검색이면 `copy_to`.

### Phrase Matching & Slop

```json
// 정확한 구문 매칭
{ "match_phrase": { "title": "무선 이어폰" } }

// slop으로 단어 사이 허용 거리 설정
{ "match_phrase": { "title": { "query": "삼성 이어폰", "slop": 2 } } }
// "삼성 무선 이어폰" 매칭 (사이에 1단어)
// "삼성 갤럭시 무선 이어폰" 매칭 (사이에 2단어)
```

## 4. Synonym Management

### synonym vs synonym_graph

| Type | 멀티토큰 동의어 | 사용 위치 | 권장 |
|------|--------------|----------|------|
| `synonym` | 부정확 (단일 토큰으로 취급) | index/search | 단일 단어 동의어만 |
| `synonym_graph` | 정확 (그래프 기반) | search-time만 | 멀티토큰 포함 시 필수 |

### Index-time vs Search-time Synonyms

| 기준 | Index-time | Search-time |
|------|-----------|-------------|
| 적용 시점 | 인덱싱 시 토큰 확장 | 검색 시 쿼리 확장 |
| 사전 업데이트 | reindex 필요 | reload search analyzers로 반영 |
| 인덱스 크기 | 증가 (확장된 토큰 저장) | 변화 없음 |
| 성능 | 검색 시 빠름 | 검색 시 약간 느림 (확장 처리) |
| 권장 | 거의 변하지 않는 동의어 | 자주 변경되는 동의어 |

**권장**: search-time synonym 우선. 사전 업데이트가 reindex 없이 가능.

```json
// search-time synonym 설정
{
  "settings": {
    "analysis": {
      "filter": {
        "search_synonyms": {
          "type": "synonym_graph",
          "synonyms_path": "synonyms.txt",
          "updateable": true
        }
      },
      "analyzer": {
        "search_analyzer": {
          "type": "custom",
          "tokenizer": "nori_mixed",
          "filter": ["pos_filter", "lowercase", "search_synonyms"]
        }
      }
    }
  },
  "mappings": {
    "properties": {
      "title": {
        "type": "text",
        "analyzer": "nori_standard",
        "search_analyzer": "search_analyzer"
      }
    }
  }
}

// 사전 업데이트 후 reload (reindex 불필요!)
POST /products/_reload_search_analyzers
```

### Korean Synonym Handling

```
// synonyms.txt (Solr format)
노트북, 랩탑, laptop
핸드폰, 휴대폰, 스마트폰, mobile phone, cellphone
TV, 텔레비전, 티비, television
냉장고, 냉동고, 김치냉장고 => 냉장고
이어폰, 이어버드, earphone, earbud
```

**Solr Format 규칙**:
- `A, B, C`: 양방향 (A→B→C 모두 상호 치환)
- `A, B => C`: 단방향 (A, B 검색 시 C로 치환, C 검색 시 A/B 미매칭)

**한국어 동의어 주의**:
- 형태소 분석 후 동의어 적용: filter chain에서 nori 필터 → synonym 순서
- 형태소 분석 결과 기준으로 동의어 작성 (원형이 아닌 분석 결과 토큰)
- 복합어는 user dictionary에 등록 후 동의어 설정

## 5. Search Quality Evaluation

### Offline Metrics

| Metric | 설명 | 계산 | 적합 시나리오 |
|--------|------|------|-------------|
| **NDCG** | 등급화된 관련성 반영 (0-1) | graded relevance 기반 DCG 정규화 | 순위가 중요한 검색 |
| **MRR** | 첫 관련 결과 순위의 역수 | 1/rank_of_first_relevant | 하나의 정답을 찾는 검색 |
| **MAP** | 관련 문서 각 위치의 precision 평균 | avg(precision@k for relevant k) | 여러 관련 문서가 있는 검색 |
| **Precision@K** | 상위 K개 중 관련 문서 비율 | relevant_in_K / K | 상위 결과 품질 |
| **Recall@K** | 전체 관련 문서 중 상위 K에 포함된 비율 | relevant_in_K / total_relevant | 커버리지 중요 시 |

### 5-Point Graded Relevance Scale

| Grade | Label | 설명 | 예시 |
|-------|-------|------|------|
| 4 | **Perfect** | 정확히 원하는 결과 | "갤럭시 버즈3" → 갤럭시 버즈3 상품 |
| 3 | **Excellent** | 매우 관련 있음 | "갤럭시 버즈3" → 갤럭시 버즈3 케이스 |
| 2 | **Good** | 관련 있지만 최적은 아님 | "갤럭시 버즈3" → 갤럭시 버즈2 |
| 1 | **Fair** | 약간 관련 | "갤럭시 버즈3" → 삼성 무선 이어폰 일반 |
| 0 | **Bad** | 관련 없음 | "갤럭시 버즈3" → 갤럭시 S24 케이스 |

### Elasticsearch Ranking Evaluation API

```json
// _rank_eval API로 오프라인 메트릭 계산
GET /products/_rank_eval
{
  "requests": [
    {
      "id": "query_1",
      "request": { "query": { "match": { "title": "무선 이어폰" } } },
      "ratings": [
        { "_index": "products", "_id": "1", "rating": 4 },
        { "_index": "products", "_id": "2", "rating": 3 },
        { "_index": "products", "_id": "5", "rating": 0 }
      ]
    },
    {
      "id": "query_2",
      "request": { "query": { "match": { "title": "노트북 가방" } } },
      "ratings": [
        { "_index": "products", "_id": "10", "rating": 4 },
        { "_index": "products", "_id": "11", "rating": 2 }
      ]
    }
  ],
  "metric": {
    "dcg": {
      "k": 10,
      "normalize": true
    }
  }
}
```

### Online Metrics

| Metric | 설명 | 목표 |
|--------|------|------|
| **CTR** (Click-Through Rate) | 검색 결과 클릭률 | > 30% (top 3) |
| **Session Success Rate** | 검색 후 구매/전환까지 성공 | > 15% |
| **Zero-Result Rate** | 결과 0건 비율 | < 5% |
| **Reformulation Rate** | 검색어 수정 비율 | < 20% |
| **Mean Reciprocal Rank** (live) | 클릭된 결과의 평균 순위 역수 | > 0.5 |
| **Time to First Click** | 첫 클릭까지 시간 | < 5초 |

### Test Set Design

| Category | 비율 | 설명 | 예시 |
|----------|------|------|------|
| **Head** | 20% | 고빈도 인기 검색어 | "이어폰", "노트북", "신발" |
| **Torso** | 30% | 중빈도 검색어 | "무선 이어폰 노이즈캔슬링", "남성 러닝화" |
| **Tail** | 30% | 저빈도 롱테일 | "삼성 갤럭시 버즈3 화이트 256기가" |
| **Zero-result** | 10% | 결과 없는 쿼리 | 오타, 신조어, 미등록 브랜드 |
| **Edge cases** | 10% | 특수 케이스 | 숫자만, 특수문자, 한영 혼합 |

## 6. Common Problems & Solutions

| Problem | 원인 | Solution | 구현 |
|---------|------|----------|------|
| exact match가 상위에 안 옴 | full-text 스코어에 묻힘 | phrase boost + keyword field | `bool.should: [match_phrase(boost=10), match(boost=1)]` |
| 짧은 쿼리 ("이어폰") 결과 너무 많음 | 하나의 토큰이 너무 많은 문서 매칭 | `minimum_should_match` 적용 | `multi_match.minimum_should_match: "75%"` |
| 신규 상품이 검색 안 됨 | 기존 문서의 IDF 우세 | recency boost (decay function) | `function_score.gauss.created_at` |
| 동의어가 precision 저하 | index-time synonym으로 과도한 토큰 확장 | search-time synonym으로 전환 | `search_analyzer`에만 synonym 적용 |
| 카테고리 필터 후 결과 부족 | 필터가 너무 엄격 | 2단계 검색 (필터 → fallback 없이 검색) | 결과 < N이면 필터 완화 재검색 |
| 한영 오타 ("dlfhsks" → "이어폰") | 키보드 전환 미스 | 한영 변환 사전 또는 전처리 | 입력 전처리 레이어에서 변환 후 검색 |
| 특정 브랜드가 항상 상위 | 해당 브랜드 문서가 많아 TF 높음 | 브랜드 균형 boosting | `function_score.field_value_factor` 또는 결과 다양성 |
| 복합어 검색 실패 ("무선이어폰") | 분석기가 분해 못함 | user dictionary에 등록 | `user_dictionary_rules: ["무선이어폰"]` |

### Exact Match Boosting 패턴

```json
{
  "query": {
    "bool": {
      "must": [
        { "multi_match": { "query": "갤럭시 버즈3", "fields": ["title^3", "description"], "type": "best_fields" } }
      ],
      "should": [
        { "match_phrase": { "title": { "query": "갤럭시 버즈3", "boost": 10 } } },
        { "term": { "title.raw": { "value": "갤럭시 버즈3", "boost": 20 } } }
      ]
    }
  }
}
```

### Recency Boost (시간 감쇠)

```json
{
  "query": {
    "function_score": {
      "query": { "match": { "title": "이어폰" } },
      "functions": [
        {
          "gauss": {
            "created_at": {
              "origin": "now",
              "scale": "30d",
              "offset": "7d",
              "decay": 0.5
            }
          },
          "weight": 2
        }
      ],
      "boost_mode": "sum",
      "score_mode": "multiply"
    }
  }
}
```

### Result Diversity (다양성 확보)

```json
// field_value_factor로 인기도 반영하되 과도한 독점 방지
{
  "query": {
    "function_score": {
      "query": { "match": { "title": "이어폰" } },
      "functions": [
        {
          "field_value_factor": {
            "field": "sales_count",
            "modifier": "log1p",  // log(1+x)로 극단값 완화
            "factor": 0.5
          }
        }
      ],
      "boost_mode": "sum"
    }
  }
}

// collapse로 브랜드당 1개만 노출 (결과 다양성)
{
  "query": { "match": { "title": "이어폰" } },
  "collapse": {
    "field": "brand",
    "inner_hits": { "name": "brand_variants", "size": 3 }
  }
}
```

---

**Remember**: 검색 품질은 한 번의 설정으로 완성되지 않습니다. 측정 → 분석 → 튜닝 → 측정 사이클을 반복하세요. 반드시 테스트 세트를 먼저 구축하고, 변경 전후의 NDCG를 비교하여 개선을 증명하세요.
