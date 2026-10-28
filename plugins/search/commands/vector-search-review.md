---
name: vector-search-review
description: |
  Elasticsearch 벡터·하이브리드 리뷰 — dense_vector 메모리 산정, 양자화, kNN 필터, RRF 융합, 임베딩 규약을 VEC 항목 ID 로 판정.
  Reviews vector/hybrid search with a memory estimate. Use when: running /vector-search-review.
disable-model-invocation: true
---

# /vector-search-review

## Usage
```
/vector-search-review [path] [--estimate-memory] [--check-embedding] [--compare-retrievers]
```
- `--estimate-memory`: VEC-MEM-01 산식으로 노드당 필요 RAM 계산 (입력: 벡터 수, dims, index_options, m, 레플리카, 샤드 배치)
- `--check-embedding`: 임베딩 코드의 모델 규약·정규화·캐시·타임아웃 폴백 (VEC-EMB-*, VEC-IDX-05)
- `--compare-retrievers`: BM25 단독 / kNN 단독 / 융합 구성 비교와 `_rank_eval`·recall@k 측정 계획 (VEC-HYB-*, ES-RNK-03)

## Flow
1. **사실 확인** — ES 버전·라이선스(기본 index_options, rescore_vector, exclude_source_vectors 지원이 버전별), 매핑 원본, 벡터 수·차원, 노드 RAM/힙, 임베딩 모델 카드.
2. **판정** — `vector-hybrid-search-patterns` 의 `references/vector-index.md`, `vector-query.md`. 필요 시 `es-deep-patterns` 의 LUC-SEG-04, ES-IDX-02, ES-ING-05. 각 지적에 항목 ID·신호(파일:라인)·적용 버전.
3. **측정 계획** — 재현율 주장은 exact(script_score) 대비 recall@k, 품질은 `_rank_eval`.

## Output
```
## Vector Search Review — [path]
가정: [버전/라이선스/벡터 수]
| 위치 | 항목 ID | 신호 | Severity | 처방(매핑/쿼리/Kotlin) | 검증 |
### 메모리 산정 (--estimate-memory): 산식 · 입력 · 결과 · 노드 RAM 대비 여유
### 측정 계획: recall@k / nDCG / 지연 분해(임베딩·ES·후처리)
```

## Boundaries
- 임베딩 모델 학습·파인튜닝은 범위 밖. 클러스터에 적용하지 않는다.
