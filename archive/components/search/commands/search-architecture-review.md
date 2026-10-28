---
name: search-architecture-review
description: "Multi-stage retrieval architecture review with pipeline stage assessment, missing stage detection, latency budget analysis, and optimization recommendations"
category: utility
complexity: basic
mcp-servers: []
personas: []
---

# /search-architecture-review - Search Architecture Review

## Triggers
- Multi-stage search pipeline 설계 리뷰 요청
- Search latency 최적화 평가 및 병목 분석
- 신규 reranking 또는 query understanding stage 도입 검토
- 검색 서비스 아키텍처 감사 (스케일링 전 점검)
- LTR, vector search, personalization 추가 여부 판단

## Usage
```
/search-architecture-review [target] [options]

Options:
  --stage-analysis     각 stage별 상세 latency 및 역할 평가
  --suggest-stages     코드베이스 분석 기반 누락 pipeline stage 추천
  --latency-budget     stage 간 latency 배분 분석 및 최적화
```

## Behavioral Flow

### Standard Flow
1. **Discover**: 대상 경로에서 Kotlin/Python 검색 서비스 코드를 스캔하여 pipeline stage 구현체를 탐색
   - L0 지표: spell check, query expansion, classification, relaxation
   - L1 지표: ES search queries, kNN, multi-index, msearch
   - L2 지표: function_score, rescore, boosting, decay
   - L3 지표: LTR, sltr, inference API, cross-encoder
   - L4 지표: pinned queries, collapse, personalization, A/B routing
2. **Map**: 탐지된 구현체를 기반으로 pipeline stage 맵을 구성하고 단계 간 데이터 흐름을 도식화
3. **Assess**: 각 stage에 대해 정확성, 성능, 완성도를 평가하고 maturity level 판정
4. **Recommend**: 누락된 stage, 최적화 기회, 아키텍처 개선 방안을 도출

### Stage Detection Patterns
| Stage | Detection Signals |
|---|---|
| L0 Query Understanding | `suggest`, `didYouMean`, `queryClassifier`, `spellCheck`, `queryExpand`, `relaxation`, `synonym`, `queryRewrite`, `intentDetect` |
| L1 Candidate Generation | `client.search`, `SearchRequest`, `knnSearch`, `msearch`, `RRF`, `retriever`, `multiSearch`, `scrollSearch`, `searchAfter` |
| L2 Lightweight Scoring | `function_score`, `rescore`, `field_value_factor`, `gauss`, `decay`, `script_score`, `weight`, `random_score` |
| L3 Heavy Reranking | `sltr`, `inference`, `rerank`, `LTR`, `cross-encoder`, `RankFeatureQuery`, `ltr_model`, `textExpansion`, `rerankPipeline` |
| L4 Business Rules | `pinned`, `collapse`, `field_collapse`, `personalization`, `experiment`, `abRouting`, `diversify`, `slotting`, `merchandising` |

### Stage Maturity Levels
| Level | Name | Description | Indicators |
|---|---|---|---|
| 0 | Absent | 미구현 상태 | 코드베이스에 해당 패턴 없음 |
| 1 | Basic | 최소 구현, 하드코딩된 로직 | 단일 구현체, 설정 없음, 테스트 없음 |
| 2 | Standard | 운영 가능, 설정 가능, 모니터링 존재 | 설정 외부화, 메트릭 수집, 단위 테스트 존재 |
| 3 | Advanced | A/B 테스트, ML 기반, 지속적 개선 체계 | Feature flag, 모델 버저닝, 자동화된 품질 측정 |

### Stage Ordering Validation
올바른 pipeline 순서를 검증하여 비효율적 배치를 탐지:
```
L0 (Query Understanding) → L1 (Candidate Generation) → L2 (Lightweight Scoring)
→ L3 (Heavy Reranking) → L4 (Business Rules)
```

| 위반 패턴 | Severity | 설명 |
|---|---|---|
| L3 before L1 | Critical | Candidate generation 없이 reranking 수행 불가 |
| L4 before L2 | High | Business rule이 scoring 결과를 덮어쓸 수 있음 |
| L0 absent with L3 present | Medium | Query understanding 없이 heavy reranking은 비효율적 |
| L2 absent with L3 present | Medium | Lightweight scoring 건너뛰면 L3에 과부하 발생 |

## Tool Coordination
- **Glob**: 검색 서비스 파일, 설정 파일, ES query 파일 탐색 (`**/search/**/*.kt`, `**/search/**/*.py`, `**/config/**/*.yml`)
- **Grep**: `function_score`, `rescore`, `sltr`, `collapse`, `pinned`, `suggest`, `knnSearch`, `inference`, `rerank` 등 stage 지표 패턴 탐색
- **Read**: 검색 서비스 아키텍처, query 구성 로직, reranking 파이프라인, 설정 파일 분석
- **Bash**: 의존성 확인 (LTR 플러그인 설치 여부, inference endpoint 상태, 모델 배포 상태)

## Key Patterns
- **Pipeline Completeness**: 5개 stage(L0-L4) 중 구현된 stage와 누락된 stage를 식별하여 아키텍처 성숙도 판단
- **Latency Chain**: 각 stage의 예상 latency를 합산하여 전체 검색 응답 시간 추정 및 병목 stage 식별
- **Stage Ordering**: pipeline stage 간 실행 순서의 논리적 정합성 검증 (e.g., reranking이 candidate generation보다 먼저 실행되는 위반 탐지)
- **Observability Gap**: 각 stage의 메트릭 수집, 로깅, 알림 설정 여부를 점검하여 모니터링 사각지대 식별

## Examples

### 검색 서비스 전체 아키텍처 리뷰
```
/search-architecture-review src/main/kotlin/com/example/search/
# Kotlin 검색 서비스 코드 전체를 스캔하여 pipeline stage 탐지
# L0-L4 각 stage 구현 현황과 maturity 평가
# 누락 stage 및 개선 권고안 제시
```

### Stage별 상세 latency 분석
```
/search-architecture-review src/main/kotlin/com/example/search/ --stage-analysis
# 각 pipeline stage별 상세 역할 및 latency 영향도 분석
# Stage 간 데이터 전달 방식 및 직렬/병렬 처리 여부 확인
# 각 stage의 maturity level 상세 근거 제시
```

### 누락 stage 추천
```
/search-architecture-review src/main/kotlin/com/example/search/ --suggest-stages
# 현재 구현된 pipeline 분석 후 다음으로 추가할 stage 추천
# ROI 기반 우선순위와 구현 스케치 제공
# 추천 stage가 기존 파이프라인에 미치는 latency 영향도 추정
```

### Latency budget 분석 및 최적화
```
/search-architecture-review src/main/kotlin/com/example/search/ --latency-budget
# 전체 검색 latency 예산 대비 각 stage 소비량 분석
# p50/p95/p99 기준 latency 배분 현황 표시
# Budget 초과 stage 식별 및 최적화 방안 제시
```

## Output Format

### Standard Output
```
## Search Architecture Review
- Target: [path]
- 서비스 유형: [product search / content search / autocomplete 등]
- 파일 스캔: [count]개
- Pipeline Stages 탐지: [count]/5

## Pipeline Stage Map
| Stage | Name | 구현 현황 | Maturity | 예상 Latency | 주요 파일 |
|---|---|---|---|---|---|
| L0 | Query Understanding | spell check, query expansion | Standard (2) | ~15ms | QueryPreprocessor.kt |
| L1 | Candidate Generation | ES multi-search, kNN | Standard (2) | ~45ms | ProductSearchService.kt |
| L2 | Lightweight Scoring | function_score (gauss decay) | Basic (1) | ~10ms | ScoringConfig.kt |
| L3 | Heavy Reranking | Absent | Absent (0) | - | - |
| L4 | Business Rules | pinned queries | Basic (1) | ~5ms | MerchandisingService.kt |

## Total Estimated Latency
- 전체 예상 latency: ~75ms
- Latency budget: 200ms
- 상태: Budget 내 (여유: 125ms)

## Stage Details

### L0 Query Understanding
- 탐지된 구현:
  - `spellCheck()` — QueryPreprocessor.kt:45 (nori 기반 맞춤법 교정)
  - `expandSynonyms()` — QueryPreprocessor.kt:78 (동의어 확장)
- 누락된 기능:
  - Query classification (카테고리 의도 분류)
  - Query relaxation (zero-result fallback)
- 권고: Query relaxation 추가로 zero-result rate 감소 가능

### L1 Candidate Generation
- 탐지된 구현:
  - `client.msearch()` — ProductSearchService.kt:120 (multi-index 검색)
  - `knnSearch()` — VectorSearchService.kt:45 (벡터 유사도 검색)
- 누락된 기능:
  - RRF (Reciprocal Rank Fusion) retriever를 통한 hybrid search
- 권고: lexical + vector 결과를 RRF로 결합하면 recall 향상 기대

### L2 Lightweight Scoring
- 탐지된 구현:
  - `function_score` with `gauss` decay — ScoringConfig.kt:30
- 누락된 기능:
  - `field_value_factor` (인기도/판매량 반영)
  - 설정 외부화 (현재 하드코딩)
- 권고: Boosting 파라미터를 설정 파일로 외부화하여 A/B 테스트 지원

### L3 Heavy Reranking — ABSENT
- 탐지된 구현: 없음
- 권고: LTR 모델 도입 검토 (아래 --suggest-stages 참조)

### L4 Business Rules
- 탐지된 구현:
  - `pinned` queries — MerchandisingService.kt:22
- 누락된 기능:
  - `field_collapse` (중복 제거)
  - Personalization (사용자별 결과 개인화)
- 권고: field_collapse로 동일 판매자 상품 중복 노출 방지

## Observability Assessment
| Stage | Metrics | Logging | Alerting | 상태 |
|---|---|---|---|---|
| L0 Query Understanding | latency histogram | query rewrite 로그 | 없음 | 부분적 |
| L1 Candidate Generation | latency, hit count | search request 로그 | p99 > 100ms | 양호 |
| L2 Lightweight Scoring | 없음 | 없음 | 없음 | 미흡 |
| L3 Heavy Reranking | - | - | - | 미구현 |
| L4 Business Rules | pinned count | 없음 | 없음 | 미흡 |

## Summary
- 아키텍처 성숙도: **Standard** (구현 4/5 stages, 평균 maturity 1.25)
- 탐지된 stages: L0, L1, L2, L4
- 누락된 stages: L3 (Heavy Reranking)
- 전체 예상 latency: ~75ms (budget 200ms 내)
- Critical Gaps:
  1. L3 Heavy Reranking 부재 — 검색 품질 상한선 제한
  2. L2 설정 하드코딩 — A/B 테스트 불가
  3. Observability 부족 — L2, L4 모니터링 사각지대
- Top 3 권고:
  1. [HIGH] L3 LTR 모델 도입으로 검색 품질 개선 (NDCG +10~15% 기대)
  2. [HIGH] L2 scoring 파라미터 설정 외부화 및 A/B 테스트 프레임워크 연동
  3. [MEDIUM] 전 stage 메트릭/알림 체계 구축 (특히 L2, L4)
```

### With --suggest-stages
```
## Recommended Next Stage: L3 Heavy Reranking (LTR)

### 추천 근거
- 현재 L0-L2-L4가 구현되어 있으나 L3이 부재하여 ranking 품질 상한선이 L2 수준에 제한됨
- L1 candidate generation이 충분한 recall을 제공하므로 L3 도입 시 precision 개선 효과 극대화
- Latency budget 여유분 125ms 중 ~30-50ms를 L3에 할당 가능

### 예상 효과
| Metric | 현재 추정 | 도입 후 기대 | 개선폭 |
|---|---|---|---|
| NDCG@10 | ~0.65 | ~0.75-0.80 | +15~23% |
| 전체 latency | ~75ms | ~105-125ms | +30-50ms |
| CTR (예상) | baseline | +5~10% | 유의미한 개선 |

### 구현 스케치 (5단계)

#### Step 1: Feature Set 정의
- 활용 feature 후보: BM25 score, recency, popularity, category match, price range match, seller rating
- Feature store 또는 ES stored field에서 추출 가능한 feature 목록 확정
- 예상 feature 수: 15-30개

#### Step 2: Judgment List 구축
- 기존 클릭/구매 로그 기반 implicit judgment 생성
- /search-quality 커맨드로 graded relevance 테스트 케이스 설계
- 최소 300개 query x 50개 document judgment 확보 목표

#### Step 3: Model Training
- RankLib 또는 XGBoost 기반 LambdaMART 모델 학습
- Offline evaluation: NDCG@10으로 모델 성능 검증
- 모델 경량화 및 ES LTR 플러그인 호환 포맷 (JSON/PMML) 변환

#### Step 4: Integration
```kotlin
// RescoringService.kt
fun applyLTR(searchResponse: SearchResponse, model: String): SearchResponse {
    val rescoreBuilder = QueryRescorerBuilder(
        SltrQueryBuilder()
            .modelName(model)
            .featureSetName("product-features")
            .params(mapOf("query_string" to queryString))
    )
    rescoreBuilder.windowSize(100)  // top-100 재랭킹
    // ... rescore 적용
}
```

#### Step 5: A/B Test
- Control: 기존 L0→L1→L2→L4 파이프라인
- Variant: L0→L1→L2→L3(LTR)→L4 파이프라인
- Primary metric: NDCG@10, Secondary: CTR, latency p95
- Traffic split: 10% → 30% → 50% 단계적 확대
- Guardrail: latency p99 < 200ms, error rate < 0.1%
```

### With --latency-budget
```
## Latency Budget Analysis
- 전체 latency budget: 200ms (p95 기준)
- 현재 사용량: ~75ms (37.5%)
- 여유분: ~125ms (62.5%)

### Stage별 Latency 배분
| Stage | p50 | p95 | p99 | Budget 할당 | Status |
|---|---|---|---|---|---|
| L0 Query Understanding | 8ms | 15ms | 25ms | 20ms | OK |
| L1 Candidate Generation | 25ms | 45ms | 80ms | 80ms | OK |
| L2 Lightweight Scoring | 5ms | 10ms | 18ms | 15ms | OK |
| L3 Heavy Reranking | - | - | - | 50ms (미사용) | 미구현 |
| L4 Business Rules | 2ms | 5ms | 10ms | 10ms | OK |
| Network/Serialization | 3ms | 8ms | 15ms | 25ms | OK |
| **Total** | **43ms** | **75ms** | **148ms** | **200ms** | **Budget 내** |

### Latency Hotspot 분석
1. **L1 Candidate Generation** (p95 45ms, budget의 22.5%) — 가장 큰 비중
   - msearch 호출 시 multi-index fan-out이 주요 원인
   - 최적화: 불필요한 index 제외, routing key 활용으로 shard 스캔 범위 축소
2. **L0 Query Understanding** (p99 25ms, budget 초과 없음)
   - Spell check 외부 API 호출 시 간헐적 지연 가능
   - 최적화: Local dictionary 캐시 적용으로 p99 안정화

### 최적화 기회
| 대상 | 현재 | 목표 | 절감 | 방법 |
|---|---|---|---|---|
| L1 multi-index | p95 45ms | p95 30ms | -15ms | Routing key로 shard 타겟팅 |
| L0 spell check | p99 25ms | p99 15ms | -10ms | Local dictionary 캐시 |
| L1 response parsing | p95 8ms | p95 3ms | -5ms | _source 필터링으로 payload 축소 |
| L4 pinned query | p95 5ms | p95 3ms | -2ms | Pinned ID 캐시 적용 |

### Latency Budget 재배분 권고
L3 도입을 가정한 latency budget 재배분:

| Stage | 현재 Budget | 권고 Budget | 변경 사유 |
|---|---|---|---|
| L0 Query Understanding | 20ms | 20ms | 유지 |
| L1 Candidate Generation | 80ms | 60ms | 최적화 후 축소 |
| L2 Lightweight Scoring | 15ms | 15ms | 유지 |
| L3 Heavy Reranking | 50ms (미사용) | 50ms | LTR rescore 할당 |
| L4 Business Rules | 10ms | 10ms | 유지 |
| Network/Serialization | 25ms | 25ms | 유지 |
| Buffer | 0ms | 20ms | 예비 여유분 확보 |
| **Total** | **200ms** | **200ms** | - |
```

## Boundaries

**Will:**
- 코드베이스 스캔을 통한 pipeline stage 탐지 및 맵 구성
- 각 stage의 maturity level 평가 및 상세 근거 제시
- 전체 latency budget 분석 및 stage별 배분 현황 평가
- 누락 stage 추천과 ROI 기반 구현 우선순위 도출
- 구현 스케치(feature set, judgment, training, integration, A/B test) 제공
- Stage별 observability(메트릭, 로깅, 알림) 점검

**Will Not:**
- 실제 검색 쿼리를 실행하거나 실 latency를 측정
- Pipeline stage를 직접 구현하거나 코드를 변경
- ES 클러스터 설정(shard, replica, node) 리뷰 (use `/index-lifecycle` instead)
- LTR 모델을 직접 학습하거나 배포
- 실시간 트래픽 기반 성능 프로파일링
