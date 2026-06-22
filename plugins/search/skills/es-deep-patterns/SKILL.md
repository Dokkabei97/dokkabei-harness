---
name: es-deep-patterns
description: Use this skill when designing Elasticsearch queries, mappings, indexing strategies, or operational configurations. Provides deep patterns and anti-patterns for production ES clusters with Korean analysis support.
---

# Elasticsearch Deep Patterns

이 스킬은 Elasticsearch 설계 및 운영에 필요한 심층 패턴을 제공합니다. 쿼리, 매핑, 인덱싱, 운영, 모니터링, 한국어 분석 전반을 다룹니다.

## When to Activate

- Elasticsearch 쿼리 성능 최적화 또는 새 쿼리 설계 시
- 인덱스 매핑 설계 또는 변경 시
- Bulk indexing 파이프라인 구축 또는 튜닝 시
- 클러스터 운영 (shard sizing, hot/warm/cold, snapshot) 관련 작업 시
- 느린 쿼리 디버깅 또는 relevance 문제 조사 시
- 한국어 형태소 분석기 설정 또는 커스터마이징 시
- Cross-cluster search 또는 percolator 활용 시

## 1. Query Design Patterns

### Filter vs Query Context

| Context | 용도 | 스코어링 | 캐싱 |
|---------|------|---------|------|
| **query** | relevance가 중요한 full-text 검색 | O (BM25 계산) | X |
| **filter** | exact match, range, 존재 여부 확인 | X (`_score = 0`) | O (bitset 캐시) |

**원칙**: 스코어링이 불필요한 조건은 반드시 `filter` context에 배치. 성능 차이가 크다.

```json
{
  "query": {
    "bool": {
      "must": [
        { "match": { "title": "검색어" } }
      ],
      "filter": [
        { "term": { "status": "active" } },
        { "range": { "price": { "gte": 1000, "lte": 50000 } } }
      ]
    }
  }
}
```

### Bool Query Composition 패턴

| Clause | 역할 | 스코어 기여 | 사용 예 |
|--------|------|-----------|--------|
| `must` | AND + 스코어 반영 | O | full-text 검색 조건 |
| `filter` | AND + 스코어 무시 | X | 카테고리, 상태, 날짜 필터 |
| `should` | OR + 스코어 부스트 | O | 선호 조건, 동의어 매칭 |
| `must_not` | NOT + 스코어 무시 | X | 제외 조건 |

**`minimum_should_match` 활용**: `must` 없이 `should`만 사용할 때 `minimum_should_match: 1`로 최소 하나 매칭 보장.

### Nested vs Parent-Child

| 기준 | Nested | Parent-Child (join) |
|------|--------|-------------------|
| 성능 | 빠름 (같은 Lucene doc) | 느림 (별도 문서, join 연산) |
| 업데이트 | 전체 문서 재인덱싱 필요 | 자식만 독립 업데이트 가능 |
| 쿼리 복잡도 | `nested` query 필수 | `has_child`/`has_parent` query |
| 적합 케이스 | 변경 빈도 낮은 내장 객체 (상품 옵션) | 1:N 비율 높고 자주 변경 (주문-리뷰) |

**원칙**: 가능하면 nested 우선. Parent-child는 자식 문서가 독립적으로 자주 업데이트될 때만 사용.

### Percolator 패턴

저장된 쿼리에 문서를 매칭하는 역방향 검색. 알림, 모니터링에 활용.

```json
// 1. percolator 매핑
{ "mappings": { "properties": {
  "query": { "type": "percolator" },
  "category": { "type": "keyword" }
}}}

// 2. 쿼리 등록 (알림 조건)
{ "query": { "match": { "title": "신상품" } }, "category": "alert" }

// 3. 새 문서가 들어오면 매칭되는 쿼리 검색
{ "query": { "percolate": { "field": "query", "document": { "title": "신상품 입고" } } } }
```

### Cross-Cluster Search (CCS)

```json
// elasticsearch.yml
cluster.remote.cluster_b.seeds: ["es-cluster-b:9300"]

// 쿼리 시 클러스터 접두사 사용
GET /cluster_b:products/_search
{ "query": { "match": { "name": "상품명" } } }
```

| Anti-Pattern | Fix | Severity |
|-------------|-----|----------|
| filter 조건을 `must`에 배치 | `filter` context로 이동 | **High** |
| 깊은 nested query 중첩 (3단계+) | 데이터 모델 비정규화 | **High** |
| parent-child를 nested로 대체 가능한데 join 사용 | nested로 전환 | **Medium** |
| `from/size`로 10,000건 이상 페이징 | `search_after` 사용 | **Critical** |
| percolator 인덱스에 수만 개 쿼리 무분별 등록 | 카테고리 필터로 대상 축소 | **Medium** |

## 2. Mapping Design Patterns

### Field Type Decision Tree

```
문자열 데이터?
├── 전문 검색 필요 → text (+ analyzer 지정)
│   └── 정렬/집계도 필요 → multi-field (.raw: keyword)
├── 정확히 일치 검색만 → keyword
│   └── 대소문자 무시 → normalizer 적용
└── 둘 다 필요 → multi-field 전략
```

### Multi-Field Strategy

```json
{
  "product_name": {
    "type": "text",
    "analyzer": "nori_standard",
    "fields": {
      "raw": { "type": "keyword" },
      "search": { "type": "text", "analyzer": "nori_search" },
      "autocomplete": { "type": "text", "analyzer": "edge_ngram_analyzer", "search_analyzer": "standard" }
    }
  }
}
```

| Sub-field | 용도 | Analyzer |
|-----------|------|----------|
| (default) | 기본 검색 | nori_standard |
| `.raw` | 정렬, 집계, exact match | keyword (no analyzer) |
| `.search` | 검색 최적화 (동의어 등) | nori_search (search-time synonym) |
| `.autocomplete` | 자동완성 | edge_ngram (index) / standard (search) |

### Dynamic Templates

알려지지 않은 필드가 들어올 때 매핑 자동 적용.

```json
{
  "dynamic_templates": [
    { "strings_as_keywords": {
        "match_mapping_type": "string",
        "mapping": { "type": "keyword", "ignore_above": 256 }
    }},
    { "longs_as_integers": {
        "match_mapping_type": "long",
        "mapping": { "type": "integer" }
    }}
  ]
}
```

### Flattened vs Object vs Nested

| Type | 쿼리 방식 | 내부 필드 독립 검색 | 필드 매핑 폭발 방지 |
|------|----------|------------------|-------------------|
| `object` | dot notation | X (cross-object match) | X |
| `nested` | `nested` query | O (정확한 내부 매칭) | X |
| `flattened` | dot notation | 제한적 (keyword만) | O |

**`flattened` 사용 시점**: 필드 이름이 동적이고 매핑 폭발(mapping explosion)이 우려될 때. 예: 사용자 정의 속성, 로그 메타데이터.

### Runtime Fields vs Indexed

| 기준 | Runtime Fields | Indexed Fields |
|------|---------------|---------------|
| 인덱스 크기 | 증가 없음 | 증가 |
| 쿼리 성능 | 느림 (매 쿼리 계산) | 빠름 (사전 계산) |
| 유연성 | 높음 (스키마 변경 불필요) | 낮음 (reindex 필요) |
| 적합 케이스 | 탐색적 분석, 드문 쿼리 | 빈번한 검색/집계 대상 |

```json
{
  "runtime": {
    "price_with_tax": {
      "type": "double",
      "script": { "source": "emit(doc['price'].value * 1.1)" }
    }
  }
}
```

| Anti-Pattern | Fix | Severity |
|-------------|-----|----------|
| 모든 문자열을 `text`로 설정 | 용도에 따라 `keyword` 또는 multi-field | **High** |
| `dynamic: true`로 매핑 폭발 방치 | `dynamic: strict` 또는 `dynamic_templates` | **Critical** |
| nested 불필요한 곳에 nested 사용 | object 또는 flattened 검토 | **Medium** |
| runtime field를 고빈도 쿼리에 사용 | indexed field로 전환 | **High** |
| `ignore_above` 미설정으로 긴 keyword 인덱싱 | `ignore_above: 256` (또는 적정 값) 설정 | **Medium** |

## 3. Indexing Patterns

### Bulk API Optimization

| Parameter | 권장값 | 설명 |
|-----------|-------|------|
| Batch size | 5-15 MB per request | 문서 수보다 총 바이트 기준 |
| 동시 요청 수 | `number_of_data_nodes` 기준 | 너무 많으면 reject |
| `refresh_interval` | 인덱싱 중 `"-1"` (비활성) | 완료 후 `"1s"`로 복원 |
| `number_of_replicas` | 인덱싱 중 `0` | 완료 후 복원 |
| `index.translog.durability` | `async` (대량 적재 시) | 완료 후 `request`로 복원 |

### Ingest Pipeline Design

```json
PUT _ingest/pipeline/product-pipeline
{
  "processors": [
    { "set": { "field": "indexed_at", "value": "{{_ingest.timestamp}}" } },
    { "lowercase": { "field": "category" } },
    { "trim": { "field": "title" } },
    { "remove": { "field": "internal_memo", "ignore_missing": true } },
    { "script": {
        "source": "ctx.title_length = ctx.title.length()"
    }}
  ]
}
```

### Update-by-Query vs Reindex

| 기준 | Update-by-Query | Reindex |
|------|----------------|---------|
| 매핑 변경 | X | O |
| 스크립트 적용 | O | O |
| 대상 인덱스 | 동일 인덱스 | 새 인덱스 |
| 롤백 | 어려움 | alias 전환으로 즉시 롤백 |
| 권장 사례 | 필드 값 일괄 변경 | 매핑 변경, analyzer 변경 |

**Alias를 활용한 무중단 reindex**:
1. 새 인덱스 생성 (new mapping)
2. `_reindex` 실행
3. alias를 새 인덱스로 전환
4. 구 인덱스 삭제

### Optimistic Concurrency Control

```json
// 문서 조회 시 seq_no, primary_term 확인
GET /products/_doc/1
// → "_seq_no": 5, "_primary_term": 1

// 업데이트 시 조건부 적용
PUT /products/_doc/1?if_seq_no=5&if_primary_term=1
{ "title": "수정된 상품명" }
// 충돌 시 409 Conflict → 재시도 로직 필요
```

| Anti-Pattern | Fix | Severity |
|-------------|-----|----------|
| 단건 인덱싱 반복 (loop) | Bulk API 사용 | **Critical** |
| 대량 적재 시 `refresh_interval: "1s"` 유지 | `"-1"`로 변경 후 복원 | **High** |
| reindex 없이 매핑 변경 시도 | alias + reindex 패턴 | **High** |
| optimistic concurrency 미적용으로 데이터 유실 | `seq_no/primary_term` 사용 | **Medium** |
| ingest pipeline에서 heavy script 실행 | 인덱싱 전 애플리케이션에서 처리 | **Medium** |

## 4. Operational Patterns

### Shard Sizing 가이드

| 항목 | 권장 |
|------|------|
| 단일 shard 크기 | 10-50 GB |
| shard 수 / 노드 | 노드 힙 GB당 20개 이하 |
| 인덱스당 primary shard | 데이터 총량 / 30GB 기준 |
| 일별 인덱스 | 일 데이터량이 50GB 이상일 때 |

**Overshard 방지**: shard가 너무 작으면 (< 1GB) 클러스터 상태 관리 오버헤드 증가. 작은 인덱스는 1 primary shard로 충분.

### Segment Merge

```json
// force merge (읽기 전용 인덱스에서만)
POST /logs-2024.01/_forcemerge?max_num_segments=1

// merge policy 튜닝
PUT /products/_settings
{ "index.merge.policy.max_merged_segment": "5gb" }
```

**주의**: 쓰기 중인 인덱스에 force merge 금지. I/O 폭증으로 클러스터 불안정.

### Hot/Warm/Cold Architecture

```
Hot  (NVMe SSD)  → 최근 데이터, 활발한 읽기/쓰기
Warm (SSD/HDD)   → 조회 빈도 낮은 데이터, 읽기 전용
Cold (HDD/S3)    → 아카이브, 드문 조회
Frozen (S3)      → searchable snapshot, 거의 조회 안 함
```

ILM (Index Lifecycle Management) 정책:
```json
{
  "policy": {
    "phases": {
      "hot":    { "actions": { "rollover": { "max_size": "50gb", "max_age": "7d" } } },
      "warm":   { "min_age": "30d", "actions": { "shrink": { "number_of_shards": 1 }, "forcemerge": { "max_num_segments": 1 } } },
      "cold":   { "min_age": "90d", "actions": { "allocate": { "require": { "data": "cold" } } } },
      "delete": { "min_age": "365d", "actions": { "delete": {} } }
    }
  }
}
```

### Snapshot & Restore

```json
// 리포지토리 등록 (S3)
PUT /_snapshot/s3_backup
{ "type": "s3", "settings": { "bucket": "es-snapshots", "region": "ap-northeast-2" } }

// SLM (Snapshot Lifecycle Management) 정책
PUT /_slm/policy/daily-snapshot
{
  "schedule": "0 0 2 * * ?",
  "name": "<daily-{now/d}>",
  "repository": "s3_backup",
  "config": { "indices": ["products*", "orders*"], "ignore_unavailable": true }
}
```

| Anti-Pattern | Fix | Severity |
|-------------|-----|----------|
| 모든 인덱스가 hot 노드에 상주 | ILM으로 hot/warm/cold 분리 | **High** |
| shard 1개가 100GB 이상 | shard 분할 또는 rollover 설정 | **Critical** |
| snapshot 미설정 | SLM 정책 설정 및 복원 테스트 | **Critical** |
| 쓰기 중 인덱스에 force merge | 읽기 전용 전환 후 merge | **High** |
| 노드당 shard 수천 개 | 인덱스 통합 또는 rollup | **High** |

## 5. Monitoring & Debugging

### Key Metrics

| Metric | 위험 임계값 | 확인 API |
|--------|-----------|---------|
| Heap usage | > 75% | `_nodes/stats/jvm` |
| CPU usage | > 80% sustained | `_nodes/stats/os` |
| Search latency (p99) | > 500ms | `_nodes/stats/indices/search` |
| Indexing latency | > 100ms/doc | `_nodes/stats/indices/indexing` |
| Pending tasks | > 0 sustained | `_cluster/pending_tasks` |
| Circuit breaker trips | > 0 | `_nodes/stats/breaker` |
| Disk watermark | > 85% (high) | `_cluster/health` |
| Rejected threads | > 0 | `_nodes/stats/thread_pool` |

### Slow Log 설정

```json
PUT /products/_settings
{
  "index.search.slowlog.threshold.query.warn": "5s",
  "index.search.slowlog.threshold.query.info": "2s",
  "index.search.slowlog.threshold.fetch.warn": "1s",
  "index.indexing.slowlog.threshold.index.warn": "10s"
}
```

### Debugging APIs

```bash
# 쿼리 스코어 설명
GET /products/_explain/1
{ "query": { "match": { "title": "무선 이어폰" } } }

# 쿼리 실행 프로파일링
GET /products/_search
{ "profile": true, "query": { "match": { "title": "무선 이어폰" } } }

# 핫 스레드 확인 (CPU 사용 원인)
GET /_nodes/hot_threads

# 클러스터 allocation 설명
GET /_cluster/allocation/explain
```

### 증상 기반 진단 API 라우팅 마스터 테이블

> 증상 기반 진입(증상 → 도구 시퀀스)은 `search-diagnostics` 스킬을 허브로 참조. 여기서는 각 도구의 깊은 사용법을 다룬다.

위 Debugging APIs 블록을 증상별 시퀀스로 확장한다. 증상을 만나면 아래 표의 순서대로 도구를 좁혀 들어간다(같은 증상 행은 모든 search 스킬에서 동일하게 유지).

| 증상 | 1차 절단 | 2차 정밀 | 3차 교차검증 | 확정/배제 |
|------|---------|---------|-------------|----------|
| **무결과/특정 문서 누락** | `_explain/{id}` (matched:false? filter 제거 재호출로 filter vs query 이분) | `_validate/query?rewrite=true&all_shards=true` (파싱된 Lucene term) | `_analyze`(search_analyzer 명시) ∩ `_termvectors/{id}`(색인된 실제 토큰) = ∅ → 분석기 불일치 확정 | [일치하는데 0건] `_field_caps` (searchable:false / 멀티인덱스 type conflict) |
| **오정렬/순위·스코어 이상** | `_explain/{id}` (BM25/function_score 트리) | `_search` `explain:true` (상위 hit 좌우 비교; ★dfs 전역 IDF·rescore 점수는 여기서만 — `_explain`은 search_type 무시 issue#2612) | `_termvectors` `term_statistics:true` (doc_freq를 `_explain` idf의 n과 교차) | `min_score`/`from`·`size`(track_total_hits:true) 컷 배제 → `_rank_eval`(골든셋 nDCG/MRR) |
| **timeout/느림** | `_search` `profile:true` 5섹션 1차 절단 (query vs collector vs aggregations vs fetch, '가장 느린 단일 샤드' 기준) | 주범 단계 정밀 breakdown (query 9필드 / agg 6필드 / fetch load_source·load_stored_fields) | took vs Σtime_in_nanos 갭 (took ≫ 합이면 '단계 밖') | [단계 밖] `_nodes/hot_threads` + `_tasks` + `_cat/thread_pool/search` + `_nodes/stats/breaker` |
| **불안정 latency** | `_nodes/hot_threads?type=cpu` (여러 번 스냅샷) | `_cat/thread_pool/search?v` (active/queue/rejected) | `_nodes/stats/breaker` (data too big tripped, 증가율) | [첫 쿼리만 느림] eager_global_ordinals 검토 / [페이지마다 변동] PIT(`_pit`)+search_after / [벤치마크 변동] `_cache/clear?request=true` 후 재측정 |

#### 무결과 플로우 상세 — `_validate/query` 역할 구분

```bash
# rewrite=true 가 실제 파싱된 Lucene term 문자열을 노출한다(무결과 1차 단서).
# all_shards=true 미지정 시 단일 랜덤 샤드만 검사 → 비결정적. 반드시 명시.
# explain=true 는 '에러 시 상세'용이지 term 확인용이 아니다 — 역할이 다르다.
GET /products/_validate/query?rewrite=true&all_shards=true&explain=true
{ "query": { "match": { "title": "무선 이어폰" } } }
```

이분 절차:
1. `_explain/{id}` 의 `matched:false` → filter를 제거하고 재호출. 결과가 바뀌면 filter가 범인, 그대로면 query 자체가 범인.
2. `_validate/query?rewrite=true&all_shards=true` 의 파싱 term 과,
3. `_analyze`(검색 시점 분석기 명시) 토큰 ∩ `_termvectors/{id}`(색인 시점 토큰)을 비교.
   - 교집합이 공집합이면 **분석기 불일치 확정**(검색 분석기 ≠ 색인 분석기, 또는 analyzer 변경 후 reindex 누락).
4. 토큰이 일치하는데도 0건이면 `_field_caps` 로 `searchable:false` 또는 멀티인덱스 `type conflict` 확인.

### `_termvectors`/`_mtermvectors` 색인 토큰 검증

색인된 '실제 토큰'을 확인해 검색 분석기 토큰(`_analyze`)과 대조하는 도구. `_analyze`는 가설(검색 시점), `_termvectors`는 실측(색인 시점)이다.

```bash
# 단일 문서: 색인된 실제 토큰 + 통계
GET /products/_termvectors/1?fields=title&term_statistics=true&field_statistics=true
```

응답 구조(검증된 사실):

```json
{
  "term_vectors": {            // 루트는 복수형 term_vectors
    "title": {
      "field_statistics": { "doc_count": 1000, "sum_doc_freq": 5000, "sum_ttf": 7000 },
      "terms": {               // 키 = 색인된 실제 토큰
        "무선": {
          "doc_freq": 320,     // term_statistics=true 일 때만; _explain idf의 n과 동일 출처
          "ttf": 410,
          "term_freq": 1,
          "tokens": [ { "position": 0, "start_offset": 0, "end_offset": 2 } ]
        },
        "이어폰": {
          "doc_freq": 290, "ttf": 350, "term_freq": 1,
          "tokens": [ { "position": 1, "start_offset": 3, "end_offset": 6 } ]
        }
      }
    }
  }
}
```

#### `_mtermvectors` body 2형식 + 문서군 일괄 대조

```bash
# 형식 1: 공통 옵션 — 같은 인덱스의 여러 id 에 동일 fields/term_statistics 적용
POST /products/_mtermvectors
{ "ids": ["1", "2", "3"], "fields": ["title"], "term_statistics": true }

# 형식 2: 문서별 — 멀티인덱스 / per_field_analyzer / artificial doc 혼합
POST /_mtermvectors
{
  "docs": [
    { "_index": "products", "_id": "1", "fields": ["title"] },
    { "_index": "products", "doc": { "title": "무선 이어폰" },
      "per_field_analyzer": { "title": "nori_standard" } }
  ]
}
```

활용 — **'잡히는 문서군 vs 안 잡히는 문서군' 일괄 대조**: 검색에 걸린 id 와 안 걸린 id 를 형식 1로 한 번에 뽑아, 안 걸린 군에만 기대 토큰(예: `이어폰`)이 없으면 색인 단계(분석기/사전) 문제로 확정한다. **색인 품질 audit**: 토큰 0개(분석기가 전부 제거), 거대 토큰(분해 실패로 원문 통째), 사전 미반영(`삼성전자`가 `삼성`+`전자`로 쪼개짐) 같은 패턴을 문서군 단위로 스캔.

#### 한계 및 함정 (검증된 사실)

- **shard-local 통계**: `doc_freq`/`ttf`/`field_statistics`는 호출이 닿은 샤드 기준 — 전역 통계 아님. 멀티샤드 score 편차 디버깅 시 단일 샤드 테스트 인덱스 또는 클라이언트 재계산으로 대응한다(★`dfs` 파라미터는 ES 5.0 PR#16452에서 제거되어 8.x에 없음 — 절대 기재 금지).
- **삭제 문서 doc_freq 잔존**: 세그먼트 머지 전까지 삭제 문서가 `doc_freq`에 남아 `_explain` idf의 n 과 미세하게 어긋날 수 있다.
- **on-the-fly 재분석 drift**: 매핑이 `term_vector:no`(기본)면 `_source`를 '현재' index_analyzer로 즉석 재분석한다. analyzer 변경 후 reindex를 누락하면 stored(과거 색인) ≠ on-the-fly(현재) 라도 이 도구로는 drift가 안 잡힌다. 진짜 색인 토큰은 `term_vector:with_positions_offsets`(색인 시점부터, 소급 불가) 또는 reindex 후 교차검증.
- **artificial doc routing**: artificial doc(`doc:{...}`)은 routing 미지정 시 무작위 샤드로 가 통계가 부정확하다. 통계 노이즈 없는 검증이 목적이면 artificial doc이 가장 깔끔하되 통계를 신뢰하지 말 것.
- **per_field_analyzer + 저장 id**: 저장 문서(id)에 `per_field_analyzer`를 줘도 stored term을 무시하고 재생성한다 → 의도가 '저장된 그대로'면 id 형식, '다른 분석기로 시뮬레이션'이면 artificial doc 형식을 쓴다.
- **offset 단위**: `start_offset`/`end_offset`은 UTF-16 code unit. 한글 BMP 1글자=1단위로 안전하나 이모지·보충문자만 2단위.

#### 포터빌리티 경고 (ES 8.x ↔ OpenSearch)

- `_disk_usage`·`_field_usage_stats`는 **ES 8.x 전용** — OpenSearch는 no handler.
- PIT 엔드포인트가 다르다: ES `_pit` ↔ OpenSearch `_search/point_in_time`.
- `_termvectors`의 `dfs` 파라미터는 ES 5.0에서 제거 — 어느 버전 예제에도 넣지 말 것.

| Anti-Pattern | Fix | Severity |
|-------------|-----|----------|
| slow log 미설정 | 모든 주요 인덱스에 설정 | **High** |
| 성능 문제 시 쿼리만 의심 | `_profile`, `hot_threads`로 근본 원인 파악 | **Medium** |
| heap 75% 이상 방치 | GC 튜닝 또는 노드 증설 | **Critical** |
| circuit breaker trip 무시 | 쿼리 최적화 또는 메모리 증설 | **Critical** |

## 6. Korean Analysis Patterns

### Nori Tokenizer 설정

```json
{
  "settings": {
    "analysis": {
      "tokenizer": {
        "nori_mixed": {
          "type": "nori_tokenizer",
          "decompound_mode": "mixed",
          "user_dictionary_rules": [
            "삼성전자", "무선이어폰", "에어팟프로"
          ]
        }
      },
      "analyzer": {
        "nori_standard": {
          "type": "custom",
          "tokenizer": "nori_mixed",
          "filter": ["nori_readingform", "lowercase", "nori_part_of_speech"]
        }
      }
    }
  }
}
```

### Decompound Mode 비교

| Mode | 입력: "삼성전자" | 검색 특성 |
|------|----------------|----------|
| `none` | `["삼성전자"]` | exact match만 가능, 재현율 낮음 |
| `discard` | `["삼성", "전자"]` | 개별 토큰만 남아 정밀도 낮아질 수 있음 |
| `mixed` | `["삼성전자", "삼성", "전자"]` | 원형 + 분해 모두 유지, 균형 잡힌 선택 |

**권장**: 대부분의 상품 검색에서 `mixed` 모드 사용. 원형 매칭과 부분 매칭 모두 지원.

### User Dictionary 관리

```json
// 방법 1: inline rules (소규모)
"user_dictionary_rules": ["삼성전자", "쿠팡로켓"]

// 방법 2: 파일 기반 (대규모)
"user_dictionary": "userdict_ko.txt"
// userdict_ko.txt: config 디렉토리에 배치
// 한 줄에 하나의 단어, 또는 "단어 품사1+품사2" 형식
```

**운영 팁**: 사전 파일 변경 시 인덱스 close/open 또는 reindex 필요. 동적 반영 안 됨.

### Custom Morphological Analyzer Plugin

Nori 외 커스텀 형태소 분석기 (예: 사내 분석기 플러그인) 통합 시:

```json
{
  "analysis": {
    "analyzer": {
      "custom_korean": {
        "type": "custom",
        "tokenizer": "custom_morphological",
        "filter": ["lowercase", "synonym_filter", "stop_filter"]
      }
    }
  }
}
```

- 플러그인 설치: 모든 노드에 동일 버전 설치 필수
- 롤링 리스타트 시 shard allocation 일시 중지 권장
- 버전 호환성: ES 메이저 버전 업그레이드 시 플러그인 재빌드 필요

### Korean Synonym 처리

```json
{
  "filter": {
    "korean_synonyms": {
      "type": "synonym_graph",
      "synonyms": [
        "노트북, 랩탑, laptop",
        "핸드폰, 휴대폰, 스마트폰, mobile phone",
        "TV, 텔레비전, 티비"
      ]
    }
  }
}
```

**주의사항**:
- `synonym_graph`는 search-time에만 사용 권장 (index-time은 reindex 필요)
- 한국어 동의어는 형태소 분석 후 적용되도록 filter chain 순서 주의
- Nori 분석 후 synonym 적용: `tokenizer → nori_part_of_speech → synonym_graph`

| Anti-Pattern | Fix | Severity |
|-------------|-----|----------|
| `decompound_mode: none`으로 복합어 검색 불가 | `mixed` 모드로 전환 | **High** |
| 브랜드명/신조어 미등록 | user dictionary에 등록 | **Medium** |
| index-time synonym으로 사전 업데이트마다 reindex | search-time synonym으로 전환 | **High** |
| 형태소 분석 전에 synonym 적용 | filter chain 순서 재배치 | **Medium** |
| 사전 파일 노드 간 불일치 | 배포 파이프라인에 사전 동기화 포함 | **Critical** |

---

**Remember**: Elasticsearch 설계는 쿼리 패턴에서 시작합니다. 어떤 쿼리를 실행할지 먼저 정의하고, 그에 맞는 매핑과 인덱싱 전략을 수립하세요. 운영 중인 클러스터 변경은 반드시 staging에서 먼저 검증하세요.
