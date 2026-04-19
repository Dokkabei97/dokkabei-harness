---
name: vector-search-review
description: "Vector search implementation review with dense_vector mapping validation, kNN query optimization, embedding pipeline analysis, and hybrid search (RRF) configuration checks"
category: utility
complexity: basic
mcp-servers: []
personas: []
---

# /vector-search-review - Vector Search Implementation Review

## Triggers
- dense_vector 매핑 신규 설계 또는 변경 시 사전 검증
- kNN search 쿼리 성능 튜닝 및 최적화 요청
- Hybrid search (RRF) 구성 리뷰 및 랭킹 품질 점검
- Embedding pipeline 안정성 및 효율성 감사
- Vector index 메모리 사용량 추정 및 용량 계획
- Lexical search에서 vector search로 전환 시 구현 리뷰

## Usage
```
/vector-search-review [target] [options]

Options:
  --check-embedding         Embedding pipeline 코드 분석 — 모델 호출, 배치 처리, 캐싱, 에러 핸들링 검증
  --estimate-memory         Vector index 메모리 사용량 추정 — dims, doc count, quantization 기준 계산
  --compare-retrievers      Lexical vs vector vs hybrid retriever 구성 비교 — 쿼리 구조, 필터링, 점수 결합 분석
```

## Behavioral Flow

### Standard Flow
1. **Discover**: 대상 경로에서 vector search 관련 파일 탐색 — dense_vector 매핑 정의, kNN 쿼리 구성, embedding 호출 코드, RRF 설정
2. **Validate**: 매핑, 쿼리, 파이프라인 각 영역별 체크리스트 적용하여 이슈 식별
3. **Analyze**: 발견된 이슈 간 연관성 분석 — 매핑-쿼리 불일치, embedding 차원 불일치, quantization-메모리 영향 평가
4. **Report**: severity 기준으로 정렬된 findings와 수정 가이드 제시

### Vector Mapping Checklist
| Issue | Severity | Description |
|---|---|---|
| `index: false` 설정 | Critical | kNN search 불가 — brute-force script_score만 사용 가능하여 대용량에서 치명적 성능 저하 |
| similarity 함수 불일치 | Critical | 모델 학습 시 사용한 distance metric과 매핑의 `similarity` 설정이 다르면 랭킹 품질 왜곡 |
| `index_options` 미설정 | Medium | HNSW 파라미터가 기본값으로 적용됨 — 워크로드에 따라 튜닝 필요할 수 있음 |
| dims 값 불일치 | Critical | 매핑의 `dims`와 실제 embedding 모델 출력 차원이 다르면 인덱싱 실패 |
| 5M 문서 이상에서 quantization 미적용 | High | int8 또는 int4 quantization 없이 대용량 벡터 인덱스는 메모리 비용이 과도하게 증가 |
| HNSW `m` 값 < 8 또는 > 48 | High | m이 너무 낮으면 recall 저하, 너무 높으면 인덱싱 속도 저하 및 메모리 낭비 |
| `ef_construction` < 50 | High | 그래프 빌드 품질 저하로 검색 recall이 낮아짐 — 최소 100 이상 권장 |

### kNN Query Checklist
| Issue | Severity | Description |
|---|---|---|
| `num_candidates` == `k` | High | 후보 풀이 결과 수와 동일하면 recall이 크게 저하됨 — 최소 k * 1.5 이상 권장 |
| `num_candidates` > 10000 | Medium | 과도한 후보 탐색은 latency를 증가시킴 — 대부분의 워크로드에서 불필요 |
| pre-filter 미적용 | High | 전체 인덱스 대상 kNN 수행 후 post-filter 적용 시 결과가 k보다 적을 수 있음 |
| query_vector 하드코딩 | Critical | 테스트용 벡터가 프로덕션 코드에 남아있으면 모든 쿼리가 동일한 결과를 반환 |
| `_source` 필터링 미적용 | Medium | 벡터 필드까지 포함한 전체 _source 반환은 네트워크 대역폭을 낭비 |

### Hybrid Search Checklist
| Issue | Severity | Description |
|---|---|---|
| RRF에 sub_search가 1개만 존재 | Medium | RRF는 2개 이상의 sub_search를 결합해야 의미가 있음 — 단일 검색이면 RRF 불필요 |
| `rank_constant` != 60 | Medium | 기본값 60에서 변경 시 랭킹 특성이 달라짐 — 변경 근거와 A/B 테스트 결과 확인 필요 |
| `window_size` < `k` | High | window_size가 최종 반환 수보다 작으면 RRF 재랭킹에 사용할 후보가 부족 |
| sub_search 간 공통 filter 미적용 | Medium | lexical과 vector 검색에 서로 다른 필터가 적용되면 결과 집합 불일치로 RRF 품질 저하 |
| 쿼리 시점 embedding 누락 | Critical | Hybrid search에서 vector sub_search의 query_vector를 쿼리 시점에 생성하지 않으면 검색 불가 |

### Embedding Pipeline Checklist
| Issue | Severity | Description |
|---|---|---|
| 동기 단건 embedding 호출 | High | 인덱싱 시 문서 1건마다 동기 모델 호출은 처리량 병목 — 배치 처리 필수 |
| timeout 미설정 | High | 외부 모델 서버 호출에 timeout이 없으면 장애 전파 위험 |
| 모델 버전 추적 미비 | High | 모델 업데이트 시 기존 벡터와의 호환성 보장 불가 — 재인덱싱 판단 기준 부재 |
| embedding 캐시 미적용 | Medium | 동일 텍스트의 반복 embedding 호출은 불필요한 비용과 latency 유발 |
| 텍스트 truncation 미처리 | Medium | 모델의 max token 초과 입력 시 silent truncation 또는 에러 발생 — 명시적 처리 필요 |

## Tool Coordination
- **Glob**: dense_vector 매핑 JSON, index template, kNN 쿼리 파일, embedding 관련 소스 코드 탐색
- **Grep**: `dense_vector`, `knn`, `query_vector`, `num_candidates`, `rank` (RRF), embedding 모델 호출 패턴 검색
- **Read**: 매핑 정의, 쿼리 구성 로직, embedding pipeline 코드, RRF 설정 상세 분석
- **Bash**: JSON 문법 검증, dims/similarity 값 추출, 메모리 사용량 계산

## Key Patterns
- **Cross-Layer Consistency**: 매핑의 `dims`/`similarity`와 embedding 모델 출력 차원/distance metric 간 일관성 검증
- **Filter Propagation**: kNN pre-filter와 hybrid search의 sub_search 간 필터 조건 동기화 여부 추적
- **Quantization Impact Analysis**: quantization 적용 시 메모리 절감량과 recall 영향을 문서 수 기준으로 정량 평가

## Examples

### Vector search 매핑 및 쿼리 전체 리뷰
```
/vector-search-review src/main/resources/mappings/
# dense_vector 매핑 검증, kNN 쿼리 패턴 분석
# 매핑-쿼리 간 불일치 및 anti-pattern 리포트
```

### Embedding pipeline 코드 분석
```
/vector-search-review src/main/kotlin/com/example/embedding/ --check-embedding
# 모델 호출 패턴, 배치 처리, 캐싱, timeout 검증
# 모델 버전 추적 및 텍스트 truncation 처리 확인
```

### Vector index 메모리 추정
```
/vector-search-review mappings/product-vector.json --estimate-memory
# dims, 예상 문서 수, quantization 설정 기반 메모리 계산
# int8/int4 적용 시 절감량 비교
```

### Lexical vs Vector vs Hybrid 비교
```
/vector-search-review src/main/kotlin/com/example/search/ --compare-retrievers
# lexical (BM25), vector (kNN), hybrid (RRF) 쿼리 구조 비교
# 필터링 전략, 점수 결합 방식, 결과 품질 trade-off 분석
```

## Output Format

### Standard Output
```
## Vector Search Review
- Target: [path]
- Vector Fields: [count]
- kNN Queries: [count]
- Hybrid (RRF) Configurations: [count]
- Embedding Pipelines: [count]

## Vector Mapping Validation

### Critical Issues
- `product_embedding`: `index: false` → kNN search 불가, `index: true` 설정 필요
- `product_embedding`: dims 768 but model outputs 1024 → dims를 모델 출력에 맞춰 수정

### High Issues
- `product_embedding`: 문서 8M건 예상, quantization 미적용 → `element_type: byte` 또는 int8 quantization 권장
- `product_embedding`: `ef_construction: 30` → 최소 100 이상으로 상향 권장

### Medium Issues
- `product_embedding`: `index_options` 미설정 → HNSW 파라미터 명시적 튜닝 검토

## kNN Query Analysis

### Critical Issues
- ProductSearchService.kt:45 — query_vector가 하드코딩됨 → 런타임 embedding 호출로 교체

### High Issues
- ProductSearchService.kt:72 — `num_candidates: 10` == `k: 10` → `num_candidates: 50` 이상 권장
- ProductSearchService.kt:72 — pre-filter 미적용 → `filter` 절 추가하여 대상 문서 사전 제한

## Hybrid Search Analysis
- RRF 구성 정상: sub_search 2개 (BM25 + kNN), window_size: 100, rank_constant: 60
- [MEDIUM] sub_search 간 `category` 필터 불일치 → 공통 필터 적용 권장

## Summary
- Critical: [count] | High: [count] | Medium: [count]
- Overall Risk: [Low|Medium|High|Critical]
```

### With --estimate-memory
```
## Vector Index Memory Estimation
- Field: [field name]
- Dimensions: [dims]
- Document Count: [count]
- Similarity: [cosine|dot_product|l2_norm]

### Raw (No Quantization)
- Vector Storage: [dims] x 4 bytes x [doc_count] = [size] GB
- HNSW Graph: ~[size] GB (m=[m], estimated)
- Total Estimated: [size] GB

### With int8 Quantization
- Vector Storage: [dims] x 1 byte x [doc_count] = [size] GB
- HNSW Graph: ~[size] GB
- Total Estimated: [size] GB
- Savings: [percentage]% reduction

### With int4 Quantization
- Vector Storage: [dims] x 0.5 bytes x [doc_count] = [size] GB
- HNSW Graph: ~[size] GB
- Total Estimated: [size] GB
- Savings: [percentage]% reduction

### Recommendation
- [quantization 적용 여부 및 타입 권장사항]
- [JVM heap 대비 vector index 메모리 비율 경고 여부]
```

## Boundaries

**Will:**
- dense_vector 매핑의 dims, similarity, index_options, quantization 설정 검증
- kNN 쿼리의 num_candidates, pre-filter, query_vector 구성 분석
- Hybrid search (RRF)의 sub_search 구성, window_size, rank_constant 점검
- Embedding pipeline의 배치 처리, timeout, 캐싱, 모델 버전 관리 감사
- Vector index 메모리 사용량을 dims/doc count/quantization 기준으로 추정

**Will Not:**
- 실제 Elasticsearch 클러스터에 쿼리를 실행하거나 매핑을 적용
- Embedding 모델의 품질(recall, accuracy)을 평가 (use `/search-quality` instead)
- 벡터 데이터를 직접 생성하거나 모델 학습을 수행
- 클러스터 레벨 설정(shard 수, replica, JVM heap)을 변경 (use `/index-lifecycle` instead)
