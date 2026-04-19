---
name: lucene-internals
description: Use this skill when diagnosing ES performance at the segment/Lucene level, interpreting _profile or _explain output, understanding scoring internals, tuning merge policies, or reasoning about why an ES setting affects search latency. Covers inverted index structure, segment lifecycle, codec system, scoring models, query execution pipeline, and OS-level performance factors.
---

# Lucene Internals for Elasticsearch Engineers

Elasticsearch의 기반인 Apache Lucene의 내부 구조를 다루는 가이드입니다. ES 성능 문제의 근본 원인은 대부분 Lucene 레벨에 있습니다.

## When to Activate

- `_profile` API 출력에서 `build_scorer`, `advance`, `next_doc` 시간이 비정상적일 때
- `_explain` API 출력에서 IDF/TF/norms 값이 예상과 다를 때
- 세그먼트 수가 증가하거나 force merge 결정이 필요할 때
- `refresh_interval`, translog, flush 설정 튜닝 시
- `doc_values` vs `fielddata` 선택이 필요할 때
- 숫자/geo 쿼리 성능 이슈 (BKD tree)
- OS page cache 사이징 또는 heap vs off-heap 메모리 결정 시
- `index.sort.*` 설정으로 검색 시 early termination 구현 시

## 1. Architecture Fundamentals -- ES Shard = Lucene Index

### ES-Lucene Concept Mapping

하나의 ES shard는 하나의 Lucene `IndexWriter`/`IndexReader` 인스턴스입니다. ES의 모든 개념은 Lucene 개념 위에 매핑됩니다.

| ES Concept | Lucene Concept | 설명 |
|------------|---------------|------|
| Shard | `IndexWriter` + `IndexReader` | 하나의 독립적인 Lucene 인덱스 |
| Document | `Document` | 필드의 컬렉션 |
| `text` field | `TextField` | 분석(tokenize)되어 inverted index에 저장 |
| `keyword` field | `StringField` | 분석 없이 단일 토큰으로 저장 |
| `doc_values` | `DocValuesField` | 정렬/집계용 column-oriented 저장소 |
| `_source` | `StoredField` | 원본 JSON을 그대로 저장 |
| Refresh | `DirectoryReader.openIfChanged()` | 새 세그먼트를 검색 가능하게 만듦 |
| Flush | `IndexWriter.flush()` | 인메모리 버퍼를 세그먼트로 디스크에 기록 |
| Commit | `IndexWriter.commit()` | fsync + commit point 기록 (durability) |
| Merge | `MergePolicy` + `MergeScheduler` | 여러 세그먼트를 하나로 합침 |

### Inverted Index 구조

Lucene의 핵심 자료구조입니다. Term Dictionary는 FST(Finite State Transducer)로 구현되어 메모리 효율적인 prefix 탐색을 지원합니다.

```
Inverted Index (하나의 필드에 대해)
==================================

Term Dictionary (FST)          Postings List
-----------------------        ----------------------------------------
  "검색"  ─────────────────→  DocID: [2, 15, 42, 108]
                               Freq:  [1,  3,  1,   2]
                               Pos:   [(0), (0,5,12), (3), (0,7)]

  "엔진"  ─────────────────→  DocID: [15, 42, 200]
                               Freq:  [1,   2,   1]
                               Pos:   [(1), (1,8), (0)]

  "최적화" ────────────────→  DocID: [2, 200, 305]
                               Freq:  [1,   1,   4]
                               Pos:   [(2), (1), (0,3,7,11)]

FST (Finite State Transducer)
─────────────────────────────
  - Term → Postings 파일 오프셋 매핑
  - 메모리에 상주 (off-heap via mmap)
  - 공통 prefix/suffix 공유로 메모리 절약
  - O(len(term)) 탐색 시간

Postings List 구성 요소
─────────────────────────
  .doc  → DocID + Term Frequency (항상 존재)
  .pos  → Position + Offset (index_options에 따라)
  .pay  → Payload (사용자 정의 바이트)
```

### Doc Values Column Store

`doc_values`는 정렬, 집계, scripting에 사용되는 column-oriented 저장소입니다.

```
Doc Values 레이아웃 (예: "price" 필드)
=======================================

Row-Oriented (stored fields)     Column-Oriented (doc_values)
─────────────────────────────    ─────────────────────────────
Doc0: {name:"A", price:1000}     price 컬럼:
Doc1: {name:"B", price:2500}       Doc0 → 1000
Doc2: {name:"C", price:800}        Doc1 → 2500
Doc3: {name:"D", price:3200}       Doc2 →  800
                                   Doc3 → 3200
                                   (디스크에 연속 배치, mmap으로 접근)

DocValues 타입:
  NUMERIC    → long/double 값 (price, timestamp)
  BINARY     → byte[] (해시, 임의 바이너리)
  SORTED     → ordinal 기반 사전순 (keyword)
  SORTED_SET → 다중 값 ordinal (tags)
  SORTED_NUMERIC → 다중 숫자 값
```

### doc_values vs stored fields vs fielddata

| 기준 | doc_values | stored fields | fielddata |
|------|-----------|---------------|-----------|
| **접근 패턴** | column-oriented (특정 필드, 모든 문서) | row-oriented (특정 문서, 모든 필드) | column-oriented (heap) |
| **메커니즘** | 디스크 + mmap (off-heap) | 디스크에서 읽기 (decompress) | heap에 역인덱스 반전 로드 |
| **Heap 비용** | 없음 (OS page cache 사용) | 없음 | 매우 높음 (OOM 위험) |
| **디스크 레이아웃** | 세그먼트별 `.dvd`/`.dvm` 파일 | `.fdt`/`.fdx` 파일 | 디스크 없음 (런타임 생성) |
| **용도** | 정렬, 집계, scripting | `_source` 반환, highlight | text 필드 집계 (비권장) |
| **기본 활성화** | keyword/numeric/date/etc 자동 | `_source` 자동 | 비활성화 (명시적 활성화 필요) |

**원칙**: `fielddata`는 text 필드에서 집계가 불가피할 때만 사용. 대부분의 경우 `keyword` sub-field + `doc_values`로 대체.

### Segment 기반 아키텍처

Lucene 인덱스는 불변(immutable) 세그먼트의 집합입니다. 삭제는 물리 삭제가 아닌 비트맵 마킹이며, merge 시 실제 제거됩니다.

```
Lucene Index (= 1 ES Shard)
════════════════════════════════════════════════════════════

  In-Memory Buffer (IndexWriter)
  ┌─────────────────────────────┐
  │  새로 인덱싱된 문서들         │ ──── Flush ────┐
  │  (아직 검색 불가)             │                 │
  └─────────────────────────────┘                 ▼
                                          ┌──────────────┐
  Searchable Segments                     │  Segment_N   │
  ┌──────────┐ ┌──────────┐ ┌──────────┐ │  (최신)       │
  │ Segment_0│ │ Segment_1│ │ Segment_2│ └──────────────┘
  │ 50K docs │ │ 30K docs │ │ 10K docs │
  │ .si .doc │ │ .si .doc │ │ .si .doc │
  │ .pos .dvd│ │ .pos .dvd│ │ .pos .dvd│
  │ .tim .tip│ │ .tim .tip│ │ .tim .tip│
  └──────────┘ └──────────┘ └──────────┘
       │              │            │
       └──────────────┴────────────┘
                    │
                  Merge ──→  ┌──────────────────┐
                             │ Merged_Segment    │
                             │ 90K docs          │
                             │ (삭제 문서 제거됨)  │
                             └──────────────────┘

  Delete Bitmap (per segment)
  ┌─────────────────────────────────────────┐
  │ Segment_0: [0,0,1,0,0,0,1,0,...] (bit) │  ← doc 2, 6 삭제됨
  │ Segment_1: [0,0,0,0,...] (bit)          │  ← 삭제 없음
  └─────────────────────────────────────────┘

  segments_N 파일 (commit point)
  ┌───────────────────────────────────┐
  │ generation: 5                     │
  │ segments: [Seg_0, Seg_1, Seg_2]   │
  │ userData: {translog_uuid: "..."}  │
  └───────────────────────────────────┘
```

### Codec 시스템

각 세그먼트의 데이터 구조는 Codec에 의해 결정됩니다. ES 8.x는 Lucene 9.x 코덱을 사용합니다.

| Codec Format | 파일 확장자 | 역할 |
|-------------|-----------|------|
| `Lucene99PostingsFormat` | `.doc`, `.pos`, `.pay` | Postings list (DocID, Freq, Position, Payload) |
| `Lucene90DocValuesFormat` | `.dvd`, `.dvm` | Doc values (정렬/집계용 column store) |
| `Lucene90StoredFieldsFormat` | `.fdt`, `.fdx`, `.fdm` | Stored fields (`_source` 포함) |
| `Lucene90NormsFormat` | `.nvd`, `.nvm` | Norms (필드 길이 인코딩 값) |
| `Lucene90TermVectorsFormat` | `.tvd`, `.tvx`, `.tvm` | Term vectors (문서별 term 정보) |
| `Lucene90PointsFormat` | `.kdd`, `.kdi`, `.kdm` | BKD tree (숫자/geo/IP 범위 쿼리) |
| `Lucene90SegmentInfoFormat` | `.si` | 세그먼트 메타데이터 |
| `Lucene90LiveDocsFormat` | `.liv` | 삭제 비트맵 |

### Directory 추상화와 Page Cache

| Directory 구현 | 메커니즘 | 특성 |
|---------------|---------|------|
| `MMapDirectory` | `mmap()` 시스템 콜 | 파일을 가상 메모리에 매핑. OS page cache 활용. **ES 기본값** |
| `NIOFSDirectory` | `FileChannel.read()` | Java NIO 기반. mmap보다 느리지만 주소 공간 제한 없음 |

**Page Cache가 중요한 이유**: Lucene은 파일을 `mmap`으로 열고, 실제 I/O는 OS page cache에 위임합니다. 충분한 page cache가 없으면 모든 쿼리가 디스크 I/O를 발생시켜 지연 시간이 급증합니다. JVM heap을 물리 메모리의 50% 이하로 설정하고 나머지를 page cache로 남겨야 하는 이유입니다.

## 2. Scoring & Similarity Deep Dive

### BM25 공식 분해

ES 8.x의 기본 유사도 함수입니다. 각 term-document 쌍에 대해 다음을 계산합니다:

```
score(q, d) = SUM_over_t_in_q [
    IDF(t) * ( tf(t,d) * (k1 + 1) ) / ( tf(t,d) + k1 * (1 - b + b * dl/avgdl) )
]

여기서:
  IDF(t)  = ln(1 + (N - df(t) + 0.5) / (df(t) + 0.5))
  tf(t,d) = sqrt(freq(t in d))    -- Lucene BM25Similarity 구현
  dl      = 문서 d의 필드 길이 (토큰 수, norms로 인코딩)
  avgdl   = 전체 문서의 평균 필드 길이
  N       = 전체 문서 수 (해당 shard 기준)
  df(t)   = term t를 포함하는 문서 수
  k1      = 1.2 (기본값, TF saturation 제어)
  b       = 0.75 (기본값, 문서 길이 정규화 제어)
```

### 스코어링 구성 요소 상세

| Component | 소스 | 저장 위치 | 설명 |
|-----------|------|----------|------|
| `tf` (Term Frequency) | Postings list `.doc` 파일 | freq 값에서 계산 | 문서 내 term 출현 빈도. Lucene은 `sqrt(freq)` 사용 |
| `df` (Document Frequency) | Term Dictionary 메타데이터 | 세그먼트별 `.tip` 파일 | term을 포함하는 문서 수 |
| `dl` (Document Length) | Norms | `.nvd` 파일 | 필드의 토큰 수. `SmallFloat`로 1바이트 인코딩 |
| `avgdl` | 세그먼트 메타데이터에서 계산 | `sumTotalTermFreq / docCount` | shard 전체의 평균 필드 길이 |
| `N` (docCount) | 세그먼트 메타데이터 | `SegmentInfo` | 해당 shard의 전체 문서 수 (삭제 포함 주의) |
| `k1` | Similarity 설정 | 인덱스 settings | TF 포화 곡선 제어. 높을수록 TF 영향 증가 |
| `b` | Similarity 설정 | 인덱스 settings | 문서 길이 보정. 0이면 길이 무시, 1이면 완전 정규화 |

### Norms: 1바이트 필드 길이 인코딩

`dl`(필드 길이)은 norms로 인코딩됩니다. `SmallFloat.intToByte4()`를 사용하여 정수를 1바이트(256가지 값)로 압축합니다.

```
Norms 인코딩 예시:
  필드 길이 1   → norms byte: 100  (정확)
  필드 길이 2   → norms byte: 120  (정확)
  필드 길이 3   → norms byte: 126  (정확)
  필드 길이 5   → norms byte: 122  (근사값)
  필드 길이 10  → norms byte: 116  (근사값)
  필드 길이 100 → norms byte: 80   (근사값, 정밀도 ↓)
  필드 길이 500 → norms byte: 64   (근사값, 정밀도 ↓↓)

주의:
  - 256가지 값만 표현 가능하므로 긴 필드에서는 정밀도 손실
  - 필드 길이 1-5 사이에서는 정확하지만, 100 이상은 근사치
  - norms 비활성화 시 ("norms": false) dl=1로 처리되어 길이 정규화 불가
  - keyword, _id 등은 기본적으로 norms 비활성화
```

### IDF per-shard 문제와 dfs_query_then_fetch

기본 `query_then_fetch`에서 IDF는 shard-local로 계산됩니다. 문서 분포가 불균등하면 동일 term에 대해 shard마다 다른 IDF를 반환합니다.

```json
// 문제 상황: shard 0에 "검색" 포함 문서 10,000개, shard 1에 5개
// → shard 1에서 "검색"의 IDF가 매우 높아져 비정상적인 점수

// 해결: dfs_query_then_fetch (2-pass 방식)
GET /products/_search?search_type=dfs_query_then_fetch
{
  "query": { "match": { "title": "검색 엔진" } }
}
// Pass 1: 모든 shard에서 df, docCount 수집
// Pass 2: 글로벌 통계로 스코어링
// 트레이드오프: 추가 라운드트립 발생. 대규모 클러스터에서는 오버헤드 주의
```

### Custom Similarity 설정

```json
// ES 인덱스 설정에서 similarity 커스텀
PUT /products
{
  "settings": {
    "index": {
      "similarity": {
        "custom_bm25": {
          "type": "BM25",
          "k1": "1.0",
          "b": "0.3",
          "discount_overlaps": "true"
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

// Scripted Similarity (고급)
PUT /products
{
  "settings": {
    "index": {
      "similarity": {
        "scripted_tfidf": {
          "type": "scripted",
          "script": {
            "source": "double tf = Math.sqrt(doc.freq); double idf = Math.log((field.docCount+1.0)/(term.docFreq+1.0)) + 1.0; double norm = 1/Math.sqrt(doc.length); return query.boost * tf * idf * norm;"
          }
        }
      }
    }
  }
}
```

### Alternative Similarity 모델

| Similarity | 설명 | 적합 케이스 |
|-----------|------|-----------|
| `BM25` (기본) | Okapi BM25, TF saturation + 길이 정규화 | 대부분의 검색 |
| `DFR` | Divergence From Randomness | 학술 검색, 긴 문서 |
| `DFI` | Divergence From Independence | 짧은 문서, 키워드 매칭 |
| `IB` | Information-Based Model | 자연어 처리 연구용 |
| `LMDirichlet` | Language Model, Dirichlet smoothing | 짧은 쿼리, 긴 문서 |
| `LMJelinekMercer` | Language Model, Jelinek-Mercer smoothing | 긴 쿼리 |
| `scripted` | 사용자 정의 스크립트 | 완전 커스텀 스코어링 |
| `boolean` | TF/IDF 무시, 매칭 여부만 | filter-like 스코어링 |

### _explain API 출력 읽기

```json
// 요청
GET /products/_explain/42
{
  "query": {
    "bool": {
      "must": [
        { "match": { "title": "무선 이어폰" } }
      ],
      "filter": [
        { "term": { "status": "active" } }
      ]
    }
  }
}

// 응답 해석
{
  "matched": true,
  "_explanation": {
    "value": 8.234,                          // ← 최종 스코어
    "description": "sum of:",
    "details": [
      {
        "value": 8.234,
        "description": "sum of:",            // ← bool.must의 합
        "details": [
          {
            "value": 4.512,
            "description": "weight(title:무선 in 42) [PerFieldSimilarity]",
            "details": [
              {
                "value": 4.512,
                "description": "score(freq=1.0), computed as boost * idf * tf",
                "details": [
                  { "value": 2.2, "description": "boost" },
                  {
                    "value": 3.145,          // ← IDF 값
                    "description": "idf, computed as log(1 + (N - n + 0.5) / (n + 0.5))",
                    "details": [
                      { "value": 50000, "description": "N, total number of documents" },
                      { "value": 1200, "description": "n, number of documents containing term" }
                    ]
                  },
                  {
                    "value": 0.651,          // ← TF-Norm 값
                    "description": "tf, computed as freq / (freq + k1 * (1 - b + b * dl / avgdl))",
                    "details": [
                      { "value": 1.0, "description": "freq, occurrences of term within document" },
                      { "value": 1.2, "description": "k1" },
                      { "value": 0.75, "description": "b" },
                      { "value": 3.0, "description": "dl, length of field" },
                      { "value": 5.2, "description": "avgdl, average length of field" }
                    ]
                  }
                ]
              }
            ]
          },
          {
            "value": 3.722,
            "description": "weight(title:이어폰 in 42) [PerFieldSimilarity]"
            // ... 동일 구조
          }
        ]
      }
      // filter 절은 스코어에 기여하지 않으므로 여기 나타나지 않음
    ]
  }
}
```

**_explain 읽기 체크리스트**:
- `N` (total documents)이 예상 shard 크기와 일치하는지 확인
- `n` (documents containing term)이 합리적인지 확인 (너무 크면 IDF 낮음)
- `dl` (document length)이 해당 문서의 실제 토큰 수와 일치하는지 확인
- `freq`가 해당 문서 내 term 출현 수와 일치하는지 확인
- filter 절은 score에 나타나지 않음 (0.0 기여)

## 3. Segment Lifecycle -- Refresh, Flush, Merge, Commit

### Write Path 타임라인

```
Index Request 도착
       │
       ▼
  ┌──────────────────┐
  │  Translog 기록    │  ← 내구성 보장 (fsync 또는 async)
  │  (WAL 역할)       │
  └────────┬─────────┘
           │
           ▼
  ┌──────────────────┐
  │  In-Memory Buffer │  ← IndexWriter의 DWPT
  │  (인덱싱 + 분석)   │     (DocumentsWriterPerThread)
  └────────┬─────────┘
           │
     Refresh (기본 1초)
           │
           ▼
  ┌──────────────────┐
  │  New Segment      │  ← 디스크에 기록되지만 fsync 안 됨
  │  (검색 가능!)      │     DirectoryReader.openIfChanged()
  └────────┬─────────┘
           │
     Flush / Commit
           │
           ▼
  ┌──────────────────┐
  │  Committed Seg    │  ← fsync 완료, segments_N에 기록
  │  (내구성 보장)     │     translog 삭제 가능
  └────────┬─────────┘
           │
     Merge (비동기, MergePolicy가 결정)
           │
           ▼
  ┌──────────────────┐
  │  Merged Segment   │  ← 여러 세그먼트 합병, 삭제 문서 제거
  │  (최적화된 상태)   │     구 세그먼트 파일 삭제
  └──────────────────┘
```

### Refresh vs Flush vs Commit

| 작업 | 내부 동작 | 트리거 | 검색 가능? | 내구성 보장? |
|------|----------|--------|-----------|------------|
| **Refresh** | `DirectoryReader.openIfChanged()` 호출, 새 세그먼트를 reader에 노출 | `refresh_interval` (기본 1초), 수동 `_refresh` | O | X (fsync 없음) |
| **Flush** | 인메모리 버퍼 → 세그먼트 파일 기록, translog는 유지 | 버퍼 크기 초과, 수동 `_flush` | O (refresh 포함) | 부분적 (translog로 복구) |
| **Commit** | `IndexWriter.commit()`, fsync + `segments_N` 기록, translog 정리 | translog 크기 초과, 수동 `_flush?force` | O | O (완전한 내구성) |

### ES Settings -> Lucene 메커니즘 매핑

| ES Setting | 기본값 | Lucene 메커니즘 | 영향 |
|-----------|-------|----------------|------|
| `refresh_interval` | `"1s"` | `DirectoryReader.openIfChanged()` 호출 주기 | 낮추면 near-real-time 지연 감소, 세그먼트 생성 증가 |
| `translog.durability` | `"request"` | 매 요청마다 `fsync` | `"async"` 시 성능 증가, 장애 시 최대 `sync_interval`만큼 유실 |
| `translog.flush_threshold_size` | `"512mb"` | Translog 크기 초과 시 commit 트리거 | 높이면 commit 빈도 감소, 복구 시간 증가 |
| `translog.sync_interval` | `"5s"` | async 모드에서 fsync 주기 | 낮추면 유실 위험 감소, I/O 부하 증가 |

### Merge 전후 시각화

```
Merge 전 (5개 세그먼트)                    Merge 후 (2개 세그먼트)
═══════════════════════                   ═══════════════════════

 Seg_0    Seg_1    Seg_2                   Merged_0
┌──────┐ ┌──────┐ ┌──────┐               ┌──────────────────┐
│ 50K  │ │ 30K  │ │ 10K  │  ──Merge──→  │ 85K docs         │
│ docs │ │ docs │ │ docs │               │ (삭제 5K 제거됨)  │
│ del:2K│ │ del:3K│ │ del:0│               └──────────────────┘
└──────┘ └──────┘ └──────┘
                                           Seg_3    Seg_4
 Seg_3    Seg_4                           ┌──────┐ ┌──────┐
┌──────┐ ┌──────┐                         │ 20K  │ │  5K  │
│ 20K  │ │  5K  │  ──(아직 merge 안 됨)   │ docs │ │ docs │
│ docs │ │ docs │                         └──────┘ └──────┘
└──────┘ └──────┘

총 문서: 115K (삭제 5K 포함)              총 문서: 110K (삭제 제거됨)
세그먼트: 5개                             세그먼트: 3개
디스크: 세그먼트 오버헤드 5x              디스크: 세그먼트 오버헤드 3x
```

### TieredMergePolicy 파라미터

ES의 기본 merge policy입니다. 세그먼트 크기를 기준으로 비슷한 크기의 세그먼트끼리 merge합니다.

| Parameter | 기본값 | 설명 |
|-----------|-------|------|
| `max_merged_segment` (`maxMergedSegmentMB`) | `5gb` | merge 결과 세그먼트의 최대 크기. 이보다 큰 세그먼트는 merge 대상에서 제외 |
| `segments_per_tier` (`segmentsPerTier`) | `10` | tier당 허용 세그먼트 수. 낮추면 merge 빈번, 높이면 세그먼트 많아짐 |
| `max_merge_at_once` (`maxMergeAtOnce`) | `10` | 한 번의 merge에 합칠 최대 세그먼트 수 |
| `floor_segment` (`floorSegmentMB`) | `2mb` | 이 크기 이하의 세그먼트는 동일 크기로 취급 (작은 세그먼트 빈번 merge 방지) |
| `deletes_pct_allowed` (`deletesPctAllowed`) | `33%` | 삭제 비율이 이 값을 초과하면 merge 강제 트리거 |

```json
// ES에서 TieredMergePolicy 튜닝
PUT /products/_settings
{
  "index.merge.policy.max_merged_segment": "5gb",
  "index.merge.policy.segments_per_tier": "10",
  "index.merge.policy.max_merge_at_once": "10",
  "index.merge.policy.floor_segment": "2mb",
  "index.merge.policy.deletes_pct_allowed": "20"
}
```

### Force Merge 결정 매트릭스

| 시나리오 | Force Merge? | 이유 |
|---------|-------------|------|
| 읽기 전용 인덱스 (ILM warm/cold 전환 후) | **YES** (`max_num_segments=1`) | 세그먼트 통합으로 검색 성능 향상, 더 이상 쓰기 없음 |
| 활발히 쓰기 중인 인덱스 | **NEVER** | merge 중 I/O 폭증, 새 세그먼트 계속 생성되어 무의미 |
| Bulk reindex 완료 직후 | **YES** | reindex로 생성된 많은 소규모 세그먼트 정리 |
| 삭제 비율 > 30%인 읽기 전용 인덱스 | **YES** | 삭제 문서 물리 제거로 디스크 회수 + 검색 성능 회복 |
| 일별 인덱스, 다음 날로 rollover 완료 | **YES** | 더 이상 쓰기 없으므로 안전하게 최적화 가능 |

### Segment Lifecycle Anti-Patterns

| Anti-Pattern | Fix | Severity |
|-------------|-----|----------|
| `refresh_interval: "1s"`로 대량 인덱싱 수행 | 대량 적재 시 `"-1"`로 비활성화, 완료 후 복원 | **Critical** |
| 쓰기 중 인덱스에 force merge 실행 | 읽기 전용 전환 후에만 force merge | **Critical** |
| `segments_per_tier`를 2로 설정하여 과도한 merge | 기본값 10 유지, 필요 시 점진적 조정 | **High** |
| translog.durability=async를 영구 적용 | 대량 적재 시에만 임시 적용, 완료 후 `request`로 복원 | **High** |
| 세그먼트 수 모니터링 없이 운영 | `_segments` API 주기적 확인, 세그먼트 > 50개 시 조사 | **Medium** |
| `max_merged_segment`를 너무 크게 설정 (50gb+) | 5-10gb 범위 유지, merge I/O와 검색 효율 균형 | **Medium** |

## 4. Index-Time Processing -- Analyzer Chain Internals

### Analyzer 파이프라인

Lucene의 Analyzer는 3단계 파이프라인으로 구성됩니다. 각 단계는 독립적으로 교체 가능합니다.

```
입력 텍스트: "삼성전자 Galaxy S24 울트라<br>할인!"
       │
       ▼
  ┌──────────────────────────────┐
  │  CharFilter(s)               │  ← 문자 수준 변환 (HTML strip, 매핑 등)
  │  html_strip: "<br>" → " "    │
  │  mapping: "&" → "and"        │
  │                              │
  │  결과: "삼성전자 Galaxy S24   │
  │         울트라 할인!"         │
  └──────────┬───────────────────┘
             │
             ▼
  ┌──────────────────────────────┐
  │  Tokenizer                   │  ← 텍스트를 토큰 스트림으로 분리
  │  nori_tokenizer              │
  │  (decompound_mode: mixed)    │
  │                              │
  │  결과:                        │
  │  ["삼성전자","삼성","전자",    │
  │   "Galaxy","S24","울트라",    │
  │   "할인"]                     │
  └──────────┬───────────────────┘
             │
             ▼
  ┌──────────────────────────────┐
  │  TokenFilter(s) 체인          │  ← 토큰 수준 변환 (순서 중요!)
  │                              │
  │  1. nori_part_of_speech      │  ← 불용 품사 제거 (조사, 감탄사 등)
  │  2. nori_readingform         │  ← 한자 → 한글 변환
  │  3. lowercase                │  ← "Galaxy" → "galaxy"
  │  4. synonym_graph            │  ← 동의어 확장
  │  5. stop                     │  ← 불용어 제거
  │                              │
  │  최종: ["삼성전자","삼성",     │
  │         "전자","galaxy","s24",│
  │         "울트라","할인"]       │
  └──────────────────────────────┘
```

### Token Attributes

각 토큰은 여러 속성(attribute)을 가집니다. 이 속성들이 inverted index에 저장되는 방식을 결정합니다.

| Attribute | 설명 | Inverted Index 저장 위치 |
|-----------|------|------------------------|
| `PositionIncrementAttribute` | 이전 토큰과의 position 차이 (기본 1) | `.pos` 파일 |
| `OffsetAttribute` | 원본 텍스트에서의 시작/끝 위치 (highlight 용) | `.pos` 파일 (offsets 활성화 시) |
| `PayloadAttribute` | 토큰에 부착하는 사용자 정의 바이트 | `.pay` 파일 |
| `TypeAttribute` | 토큰 타입 (word, synonym, NUM 등) | 인덱스에 저장되지 않음 (분석 시에만 사용) |
| `CharTermAttribute` | 토큰 문자열 자체 | `.tim`/`.tip` (term dictionary) |
| `FlagsAttribute` | 비트 플래그 (커스텀 용도) | 인덱스에 저장되지 않음 |

### Position Gap과 Multi-Value Fields

배열 필드에서 값 사이의 position gap은 `position_increment_gap`으로 제어됩니다.

```
매핑: { "tags": { "type": "text", "position_increment_gap": 100 } }

문서: { "tags": ["무선 이어폰", "블루투스 헤드셋"] }

토큰화 결과 (position 포함):
  "무선"     → position 0
  "이어폰"   → position 1
                                ← gap: 100 (position_increment_gap)
  "블루투스"  → position 101
  "헤드셋"   → position 102

Phrase Query "이어폰 블루투스":
  position 차이 = 101 - 1 = 100 ≠ 1
  → 매칭 안 됨! (의도한 동작)

만약 position_increment_gap = 0이었다면:
  "이어폰"   → position 1
  "블루투스"  → position 2
  → "이어폰 블루투스" phrase query가 잘못 매칭됨!
```

### Custom Analyzer Plugin 구조

Java 기반 커스텀 분석기 플러그인을 작성할 때의 핵심 인터페이스:

```
Plugin JAR 구조
├── META-INF/
│   └── services/
│       └── org.elasticsearch.plugins.AnalysisPlugin
├── com/example/
│   ├── MyAnalysisPlugin.java          ← implements AnalysisPlugin
│   ├── MyTokenizerFactory.java        ← extends AbstractTokenizerFactory
│   ├── MyTokenizer.java               ← extends Tokenizer
│   ├── MyTokenFilterFactory.java      ← extends AbstractTokenFilterFactory
│   └── MyTokenFilter.java             ← extends TokenFilter
└── plugin-descriptor.properties

핵심 인터페이스:
  AnalysisPlugin
  ├── getTokenizers()     → Map<String, AnalysisModule.AnalysisProvider<TokenizerFactory>>
  ├── getTokenFilters()   → Map<String, AnalysisModule.AnalysisProvider<TokenFilterFactory>>
  ├── getCharFilters()    → Map<String, AnalysisModule.AnalysisProvider<CharFilterFactory>>
  └── getAnalyzers()      → Map<String, AnalysisModule.AnalysisProvider<AnalyzerProvider>>
```

## 5. Query Execution Internals

### Query Lifecycle

ES DSL부터 최종 결과 반환까지의 전체 파이프라인입니다.

```
ES Query DSL (JSON)
       │
       ▼
  ┌─────────────────────────┐
  │  QueryBuilder.toQuery()  │  ← DSL → Lucene Query 변환
  │  (ES 레이어)              │
  └───────────┬─────────────┘
              │
              ▼
  ┌─────────────────────────┐
  │  Query.rewrite()         │  ← 쿼리 최적화/단순화
  │  - MultiTermQuery 확장   │     (와일드카드 → 개별 TermQuery들)
  │  - Boolean 단순화         │     (단일 clause → 내부 쿼리로 언래핑)
  └───────────┬─────────────┘
              │
              ▼
  ┌─────────────────────────┐
  │  Query.createWeight()    │  ← 글로벌 통계 수집 (IDF 등)
  │  → Weight 객체 생성       │     검색 컨텍스트 준비
  └───────────┬─────────────┘
              │
              ▼
     ┌────────┴────────┐
     │  foreach Segment │  ← 세그먼트별 병렬 처리
     │                  │
     │  ┌─────────────────────────┐
     │  │  Weight.scorer(segment)  │  ← 세그먼트별 Scorer 생성
     │  │  → Scorer 객체 (iterator)│     Postings 접근 준비
     │  └───────────┬─────────────┘
     │              │
     │              ▼
     │  ┌─────────────────────────┐
     │  │  Scorer.iterator()       │  ← DocID 순회
     │  │  .nextDoc() / .advance() │     matching + scoring
     │  │  .score()                │
     │  └───────────┬─────────────┘
     │              │
     │              ▼
     │  ┌─────────────────────────┐
     │  │  Collector.collect()     │  ← 결과 수집 (top-N heap)
     │  │  → LeafCollector         │     정렬/집계 처리
     │  └─────────────────────────┘
     └─────────────────────┘
              │
              ▼
  ┌─────────────────────────┐
  │  TopDocs 병합             │  ← 세그먼트별 결과를 priority queue로 합침
  │  → 최종 결과 반환          │     (shard 간에도 동일 과정)
  └─────────────────────────┘
```

### ES Query DSL -> Lucene Query 매핑

| ES Query DSL | Lucene Query | 설명 |
|-------------|-------------|------|
| `match` (단일 term) | `TermQuery` | 분석 후 단일 term이면 TermQuery |
| `match` (복수 term) | `BooleanQuery(SHOULD)` | 분석 후 여러 term이면 BooleanQuery |
| `match_phrase` | `PhraseQuery` | position 기반 인접 매칭 |
| `match_phrase_prefix` | `PhraseQuery` + `PrefixQuery` | 마지막 term만 prefix 매칭 |
| `bool.filter` | `ConstantScoreQuery` + `BooleanQuery(FILTER)` | 스코어 0, bitset 캐시 가능 |
| `term` | `TermQuery` | 분석 없이 exact match |
| `range` (numeric) | `PointRangeQuery` | BKD tree 탐색 |
| `range` (keyword) | `TermRangeQuery` | term dictionary 범위 스캔 |
| `wildcard` | `AutomatonQuery` | finite automaton으로 term 매칭 |
| `prefix` | `PrefixQuery` → `MultiTermQuery` | term dictionary prefix 스캔 |
| `nested` | `ToParentBlockJoinQuery` | 블록 단위 parent-child 조인 |
| `function_score` | `FunctionScoreQuery` | 커스텀 스코어 함수 래핑 |
| `dis_max` | `DisjunctionMaxQuery` | 최고 점수 clause + tie_breaker |
| `constant_score` | `ConstantScoreQuery` | 내부 쿼리 매칭, 고정 점수 |
| `exists` | `FieldExistsQuery` (DocValues/Norms 기반) | 필드 존재 여부 |

### Collector 계층

| Collector | 역할 | 사용 시점 |
|-----------|------|----------|
| `TopScoreDocCollector` | 점수 기반 top-N 수집, min-heap | `sort` 미지정 시 기본 |
| `TopFieldCollector` | 필드 기반 정렬 top-N 수집 | `sort` 지정 시 |
| `TotalHitCountCollector` | 총 매칭 문서 수만 계산 | `size: 0` + `track_total_hits: true` |
| `BucketCollector` | aggregation용 수집기 | `aggs` 사용 시 |
| `MultiCollector` | 여러 collector를 동시 실행 | 검색 + 집계 동시 수행 시 |
| `EarlyTerminatingCollector` | N개 수집 후 세그먼트 스킵 | `terminate_after` 설정 시 |
| `FilteredCollector` | post_filter 적용 후 수집 | `post_filter` 사용 시 |

### Early Termination 전략

**WAND/MaxScore (track_total_hits: false)**

```json
// track_total_hits를 false로 설정하면 정확한 총 매칭 수를 계산하지 않음
// Lucene의 WAND(Weak AND) / MaxScore 알고리즘이 활성화되어
// 현재 top-N의 최저 점수보다 높은 점수를 낼 수 없는 문서를 건너뜀
GET /products/_search
{
  "track_total_hits": false,
  "size": 10,
  "query": { "match": { "title": "무선 이어폰" } }
}
// 효과: 대규모 인덱스에서 쿼리 지연 시간 크게 감소
// 트레이드오프: total.hits.value가 정확하지 않음 (lower bound만 제공)
```

**Index Sorting으로 Early Termination**

```json
// 인덱스 생성 시 정렬 기준 설정
PUT /products
{
  "settings": {
    "index": {
      "sort.field": ["created_at", "price"],
      "sort.order": ["desc", "asc"]
    }
  },
  "mappings": {
    "properties": {
      "created_at": { "type": "date" },
      "price": { "type": "long" }
    }
  }
}

// 검색 시 동일 정렬 기준 사용하면 early termination 가능
GET /products/_search
{
  "sort": [
    { "created_at": "desc" },
    { "price": "asc" }
  ],
  "size": 10,
  "query": { "match_all": {} }
}
// Lucene이 정렬된 세그먼트에서 상위 N개를 빠르게 수집한 후
// 나머지 문서를 안전하게 건너뜀
```

**Index Sorting 결정 테이블**

| 기준 | Index Sorting 적합 | Index Sorting 부적합 |
|------|-------------------|-------------------|
| 주요 쿼리 패턴 | 항상 동일 필드로 정렬 | 다양한 정렬 기준 사용 |
| 쿼리 유형 | range/date 기반 필터 | full-text relevance 검색 |
| 인덱싱 성능 | 다소 느려도 무방 | 인덱싱 처리량이 최우선 |
| 사용 사례 | 로그/이벤트 (타임스탬프 정렬) | 상품 검색 (복합 정렬) |

### BKD Tree (숫자/Geo 쿼리)

```
BKD Tree (Block KD-Tree)
========================
숫자, 날짜, IP, geo_point 필드에 사용되는 다차원 공간 인덱스

예: price 필드 (1차원)

                    [100, 500, 200, 800, 150, 350, 900, 50]
                                    │
                         Split at median (300)
                        ┌───────────┴───────────┐
                   [100,200,150,50]         [500,800,350,900]
                        │                        │
                  Split at 125               Split at 625
                 ┌──────┴──────┐          ┌──────┴──────┐
              [100,50]    [200,150]    [500,350]    [800,900]
                (leaf)      (leaf)      (leaf)       (leaf)

Range Query: price >= 100 AND price <= 400
  1. Root: 300으로 분할 → 양쪽 모두 탐색 필요
  2. 좌측: 125로 분할 → [100,50] 중 100 매칭, [200,150] 전체 매칭
  3. 우측: 625로 분할 → [500,350] 중 350 매칭, [800,900] 스킵!
  결과: [100, 200, 150, 350] → 4개 문서

특성:
  - O(sqrt(N)) 탐색 시간 (1차원)
  - leaf 블록은 연속 디스크 배치 (I/O 효율적)
  - 다차원 지원 (geo_point = 2D, geo_shape = 2D+)
  - Lucene 파일: .kdd (data), .kdi (inner nodes), .kdm (meta)
```

## 6. Performance Deep Dive

### 물리 메모리 레이아웃

```
Physical RAM (예: 64GB)
═══════════════════════════════════════════════════════════

┌───────────────────────────────┬──────────────────────────────┐
│   JVM Heap (~50%, 31GB 이하)  │   OS Page Cache (~50%)        │
│                               │                              │
│  ┌─────────────────────────┐  │  ┌────────────────────────┐  │
│  │ Lucene Segment Readers  │  │  │ .doc/.pos/.pay 파일     │  │
│  │ (SegmentCoreReaders)    │  │  │ (postings)             │  │
│  ├─────────────────────────┤  │  ├────────────────────────┤  │
│  │ Indexing Buffers        │  │  │ .dvd/.dvm 파일          │  │
│  │ (indices.memory.        │  │  │ (doc values)           │  │
│  │  index_buffer_size)     │  │  ├────────────────────────┤  │
│  ├─────────────────────────┤  │  │ .tim/.tip 파일          │  │
│  │ Query/Request Cache     │  │  │ (term dictionary FST)  │  │
│  ├─────────────────────────┤  │  ├────────────────────────┤  │
│  │ Field Data Cache        │  │  │ .kdd/.kdi 파일          │  │
│  │ (text 집계 시에만)       │  │  │ (BKD tree)             │  │
│  ├─────────────────────────┤  │  ├────────────────────────┤  │
│  │ Aggregation Buffers     │  │  │ .fdt/.fdx 파일          │  │
│  │ (bucket 계산 등)         │  │  │ (stored fields/_source)│  │
│  ├─────────────────────────┤  │  └────────────────────────┘  │
│  │ Network/Transport       │  │                              │
│  │ Buffers                 │  │  mmap()으로 가상 주소에 매핑   │
│  └─────────────────────────┘  │  실제 I/O는 OS가 관리         │
└───────────────────────────────┴──────────────────────────────┘

핵심 원칙:
  - JVM Heap은 물리 메모리의 50% 이하, 절대 31GB 초과 금지
    (CompressedOops 비활성화로 heap 효율 급감)
  - 나머지 50%는 Lucene 파일의 page cache로 활용
  - page cache miss → 디스크 I/O → 쿼리 지연 시간 급증
```

### Heap vs Off-Heap 구성 요소

| 구성 요소 | 위치 | 크기 결정 요인 | 관리 방법 |
|----------|------|-------------|----------|
| Segment Readers (SegmentCoreReaders) | Heap | 열려 있는 세그먼트 수 | merge로 세그먼트 수 감소 |
| Indexing Buffer | Heap | `indices.memory.index_buffer_size` (10%) | 설정값 조정 |
| Query Cache (bitset) | Heap | `indices.queries.cache.size` (10%) | LRU 자동 eviction |
| Request Cache | Heap | `indices.requests.cache.size` (1%) | 인덱스 refresh 시 무효화 |
| Field Data | Heap | 필드 cardinality * 포인터 크기 | circuit breaker로 제한 |
| Aggregation Buffers | Heap | 쿼리 복잡도, bucket 수 | request circuit breaker |
| FST (Term Dictionary) | Off-Heap (mmap) | unique term 수, prefix 공유율 | page cache에 의존 |
| Doc Values | Off-Heap (mmap) | 문서 수 * 필드당 바이트 | page cache에 의존 |
| Postings Lists | Off-Heap (mmap) | 인덱스 총 크기 | page cache에 의존 |
| BKD Tree | Off-Heap (mmap) | 숫자/geo 필드 문서 수 | page cache에 의존 |
| Stored Fields | Off-Heap (mmap) | `_source` 크기 합계 | page cache에 의존 |

### Query Cache 동작 상세

Query cache는 세그먼트별 LRU bitset으로 구현됩니다. 모든 쿼리가 캐싱되지는 않습니다.

```
Query Cache 적격 조건:
  1. filter context에서 실행된 쿼리만 (query context는 캐시 불가)
  2. 해당 쿼리가 5회 이상 실행됨 (history count >= 5)
  3. 세그먼트의 문서 수가 10,000개 이상
  4. 세그먼트가 전체 인덱스 문서의 3% 이상을 포함
  5. TermQuery, MatchAllDocsQuery 등 비용이 낮은 쿼리는 제외

캐시 구조 (세그먼트별):
  Segment_0:
    Query("status:active") → BitSet [1,1,0,1,0,1,1,...] (문서 매칭 비트맵)
    Query("price:[100 TO 500]") → BitSet [0,1,1,0,0,1,0,...]

  Segment_1:
    Query("status:active") → BitSet [1,0,1,1,0,0,1,...]
    (다른 세그먼트이므로 별도 BitSet)

무효화:
  - 세그먼트가 merge되면 해당 세그먼트의 캐시 전체 무효화
  - refresh로 새 세그먼트가 생기면 해당 세그먼트에는 캐시 없음
  - LRU eviction: 메모리 한도 초과 시 가장 오래된 엔트리 제거
```

### Circuit Breakers

| Circuit Breaker | 기본 한도 | 보호 대상 | 트리거 상황 |
|----------------|----------|----------|-----------|
| `fielddata` | Heap의 40% | field data 로드 | text 필드에 대한 집계/정렬 |
| `request` | Heap의 60% | 단일 요청 메모리 | 대규모 aggregation, 큰 결과셋 |
| `in_flight_requests` | Heap의 100% | 전송 중인 요청 | 동시 요청 과다 |
| `parent` | Heap의 95% | 전체 heap 사용량 | 여러 breaker 합산 초과 |
| `accounting` | Heap의 100% | Lucene 세그먼트 메모리 | 세그먼트 과다 |

```json
// Circuit breaker 설정 조정
PUT /_cluster/settings
{
  "persistent": {
    "indices.breaker.fielddata.limit": "30%",
    "indices.breaker.request.limit": "50%",
    "indices.breaker.total.limit": "90%"
  }
}
```

### Skip Lists (Postings 내부)

Postings list 탐색을 가속하는 multi-level skip list 구조입니다.

```
Skip List 구조 (Postings List 가속)
═══════════════════════════════════

Level 2:  1 ─────────────────────────── 97 ──────────────────── 193
          │                              │                       │
Level 1:  1 ──────── 33 ──────── 65 ── 97 ──── 129 ──── 161 ── 193
          │          │           │      │       │        │       │
Level 0:  1,2,3,...  33,34,35..  65,66  97,98   129,130  161,162 193,...
          (DocIDs in postings list)

advance(150) 실행 과정:
  1. Level 2: 1 → 97 (150 > 97, 계속)  → 193 (150 < 193, Level 1로)
  2. Level 1: 97 → 129 (150 > 129)     → 161 (150 < 161, Level 0로)
  3. Level 0: 129 → 130 → ... → 150 (찾음!)

skip 없이 선형 탐색: 150 steps
skip list 탐색:     ~15 steps (O(sqrt(N)))

BooleanQuery에서의 활용:
  AND(term_A, term_B): 짧은 리스트의 DocID로 긴 리스트를 advance()
  → skip list 덕분에 긴 리스트 대부분을 건너뜀
```

### Block Encoding (FOR Delta Encoding)

Postings list의 DocID는 Frame of Reference (FOR) delta encoding으로 압축됩니다.

```
원본 DocIDs:   [101, 105, 108, 115, 120, 133, 140, 145]

Step 1 - Delta Encoding:
  [101, 4, 3, 7, 5, 13, 7, 5]   ← 첫 값은 그대로, 나머지는 이전 값과의 차이

Step 2 - Frame of Reference:
  Block (128개 단위): 블록 내 최대 delta = 13
  → 4 bits면 충분 (2^4 = 16 > 13)
  → 128개 값 * 4 bits = 64 bytes (vs 원본 128 * 4 bytes = 512 bytes)
  → 압축률: ~87.5%

SIMD 최적화:
  - 128개 정수를 한 블록으로 묶어 CPU SIMD 명령으로 일괄 디코딩
  - vectorized bit-unpacking으로 높은 처리량
  - Lucene의 ForUtil 클래스에서 구현
```

### Selective Filter가 BooleanQuery 성능을 극적으로 개선하는 이유

```
시나리오: 100만 문서 인덱스에서 검색

쿼리 1 (filter 없음):
  { "match": { "title": "이어폰" } }
  → "이어폰" postings: 50,000 docs
  → 50,000개 문서 전부 scoring 필요
  → 소요: ~50ms

쿼리 2 (선택적 filter 추가):
  { "bool": {
      "must": { "match": { "title": "이어폰" } },
      "filter": { "term": { "brand": "삼성" } }
  }}
  → "이어폰" postings: 50,000 docs
  → "삼성" filter bitset: 5,000 docs (캐시됨!)
  → 교집합: 리드 쿼리가 짧은 리스트(5,000)를 순회하며 긴 리스트를 advance()
  → scoring 대상: ~500 docs
  → 소요: ~5ms (10x 개선!)

핵심 메커니즘:
  1. filter는 bitset으로 캐시되어 재사용 (scoring 오버헤드 없음)
  2. BooleanQuery의 conjunction은 가장 짧은 postings list를 리드로 선택
  3. skip list의 advance()로 긴 리스트의 대부분을 건너뜀
  4. scoring은 교집합에 포함된 문서에 대해서만 수행
```

## 7. Lucene-ES Setting Mapping Reference

ES의 인덱스/클러스터 설정이 Lucene 내부에서 어떤 메커니즘으로 구현되는지 종합 정리합니다.

| ES Setting | 기본값 | Lucene 메커니즘 | 성능 영향 |
|-----------|-------|----------------|----------|
| `number_of_shards` | 1 | shard당 하나의 `IndexWriter` 인스턴스 | shard 수 = Lucene 인덱스 수. 과다 시 heap/FD 낭비, 과소 시 병렬성 부족 |
| `refresh_interval` | `"1s"` | `DirectoryReader.openIfChanged()` 호출 주기 | 짧으면 작은 세그먼트 다수 생성 → merge 부하. `"-1"`로 비활성화 가능 |
| `merge.policy.max_merged_segment` | `"5gb"` | `TieredMergePolicy.maxMergedSegmentMB` | 큰 세그먼트는 merge 제외됨. 너무 낮으면 세그먼트 파편화 |
| `merge.policy.segments_per_tier` | `10` | `TieredMergePolicy.segmentsPerTier` | 낮추면 merge 빈번 (I/O 증가), 높이면 세그먼트 수 증가 |
| `merge.policy.deletes_pct_allowed` | `33` | `TieredMergePolicy.deletesPctAllowed` | 삭제 비율 한도. 낮추면 삭제 문서가 빨리 정리됨 |
| `merge.scheduler.max_thread_count` | `Math.max(1, Math.min(4, cores/2))` | `ConcurrentMergeScheduler.maxThreadCount` | merge 병렬성. I/O 바운드이므로 과다 스레드는 비효율 |
| `sort.field` / `sort.order` | (없음) | `IndexWriterConfig.indexSort` | 세그먼트 내부가 정렬됨. 동일 정렬의 쿼리에서 early termination 가능 |
| `codec` | `"default"` | `Lucene99Codec` | `best_compression` 시 `DEFLATE` 사용 (stored fields 압축률 향상, CPU 비용 증가) |
| `max_result_window` | `10000` | `TopDocsCollector` heap 크기 제한 | 깊은 페이징 방지. 초과 시 `search_after` 사용 |
| `mapping.total_fields.limit` | `1000` | 세그먼트 메타데이터, 필드별 인덱스 구조 | 필드 과다 시 세그먼트 오버헤드 증가, mapping explosion |
| `highlight.max_analyzed_offset` | `1000000` | `UnifiedHighlighter` 오프셋 탐색 범위 | 큰 문서의 highlight 시 메모리/CPU 보호 |
| `indices.memory.index_buffer_size` | `10%` | `IndexWriter`의 RAM buffer 총량 | indexing throughput에 영향. 대량 적재 시 증가 고려 |
| `indices.queries.cache.size` | `10%` | LRU BitSet 캐시 (세그먼트별) | filter 쿼리 캐시. 높이면 반복 쿼리 가속, heap 사용 증가 |
| `index.translog.durability` | `"request"` | 매 요청 `fsync` | `"async"` 시 배치 fsync로 인덱싱 성능 향상, 데이터 유실 위험 |
| `index.translog.flush_threshold_size` | `"512mb"` | translog 크기 초과 시 Lucene commit 트리거 | 높이면 commit 빈도 감소, 노드 재시작 시 복구 시간 증가 |

---

**Remember**: Elasticsearch는 Lucene 위에 구축된 분산 시스템입니다. ES 성능 문제의 근본 원인은 대부분 Lucene 레벨에 있습니다 -- 세그먼트가 너무 많은지, 적절한 필드 타입을 사용하는지, filter context를 활용하는지, OS 페이지 캐시를 위한 메모리가 충분한지 확인하세요. `_profile` API와 `_explain` API는 Lucene 내부를 들여다보는 창입니다. 추측하지 말고, 측정하세요.
