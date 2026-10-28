---
name: vector-hybrid-search-patterns
description: |
  벡터·하이브리드 검색 허브(Elasticsearch) — kNN 이 느림·재현율 낮음·필터 걸면 결과가 k보다 적음, dense_vector 메모리 산정(HNSW·int8/int4/BBQ 양자화), num_candidates·oversample, _source 벡터 제외, RRF·하이브리드 점수 융합, 한국어 임베딩(ELSER 영어 전용, E5 접두어). 증상에서 ID 붙은 함정 항목(VEC-*)으로 안내한다.
  Hub for Elasticsearch vector (kNN/HNSW/quantization) and hybrid (RRF) search. Use when: sizing memory for dense_vector, kNN is slow or misses results, combining kNN with filters, fusing BM25 and vector scores, or choosing a Korean embedding setup.
---

# Vector & Hybrid Search Patterns (벡터·하이브리드 허브)

이 스킬은 **트리아지 인덱스**다. 지식은 `references/` 항목(적용/신호/메커니즘/처방/반례/검증/근거)에 있다.
BM25·분석기는 `search-relevance-engineering`, 샤드·색인·JVM 은 `es-deep-patterns` 허브로.

## 0. 먼저 확인할 사실 (단정 금지)

- ES 서버 버전과 라이선스 — 기본 `index_options`, `rescore_vector`, `exclude_source_vectors`, retriever 종류가 버전에 따라 다르다. 버전을 모르면 버전별 분기로 답한다.
- 실제 매핑: `GET idx/_mapping?include_defaults=true` (dims, similarity, index_options).
- 벡터 수 × 차원 × (1+레플리카), 데이터 노드 RAM·힙 — VEC-MEM-01 계산의 입력.
- 임베딩 모델과 규약(정규화, 접두어), 질의 임베딩이 어디서 계산되는지(애플리케이션/inference 엔드포인트).

## 1. 증상 → 레퍼런스

| 증상 / 질문 | 먼저 볼 곳 | 이어서 |
|---|---|---|
| 메모리가 얼마나 필요한가 / 지연 들쭉날쭉 | `vector-index.md` VEC-MEM-01 | VEC-IDX-06, LUC-EXE-03 |
| 양자화 선택·재현율 하락 | VEC-IDX-01/02 | VEC-QRY-01 |
| 적재 후 kNN 느림 / 재임베딩 | VEC-IDX-03 | ES-IDX-02, LUC-SEG-04 |
| 응답·디스크가 큼, 재색인 후 벡터 소실 | VEC-IDX-04 | ES-ING-05 |
| 필터 걸면 결과가 적음 | `vector-query.md` VEC-QRY-02 | VEC-QRY-03 |
| 재현율 튜닝 | VEC-QRY-01 | VEC-IDX-02 |
| 하이브리드 점수가 BM25 에 끌려감 | VEC-HYB-01/02 | ES-RNK-03 |
| 청크 단위 검색 | VEC-QRY-05 | ES-MAP-07 |
| 한국어 시맨틱 모델 | VEC-EMB-01/02 | VEC-EMB-03 |

## 2. 메모리 빠른 계산 (VEC-MEM-01 요약)

```
벡터당 RAM: float dims*4 | int8 dims+16 | int4 ceil(dims/2)+16 | bbq ceil(dims/64)*8+14   (bytes)
그래프:     num_vectors * 4 * m        (m 기본 16)
필요 RAM ≈ (num_vectors * 벡터당 + 그래프) * (1 + replicas)  — 힙이 아닌 OS 페이지 캐시 몫
```
예: 1M × 1024d, int8, 레플리카 1 → (1.04GB + 64MB) × 2 ≈ 2.2GB. 텍스트 필드의 캐시 몫은 별도.

## 3. 사용법

- 항목의 **적용**(버전·element_type·라이선스)을 0절 사실과 대조하고, 맞지 않으면 버린다.
- 재현율 주장에는 반드시 exact(브루트포스) 대비 recall@k 측정을 붙인다. 품질 주장은 `_rank_eval` 로.
- 프로젝트별 유효 ID 는 `workflow:project-rules` 로 규칙 파일에 선별해 두는 것을 권장한다.

## 4. 항목 인덱스

| ID | 함정 | 파일 |
|---|---|---|
| VEC-MEM-01 | HNSW 는 "벡터 + 그래프" 가 페이지 캐시에 들어가야 빠르다 — 공식 산식으로 레플리카 포함 계산 | vector-index |
| VEC-IDX-01 | 기본 `index_options` 는 버전마다 다르다 — 8.14+ float 은 `int8_hnsw`, 9.1+ 은 384차원 이상이면 `bbq_hnsw` | vector-index |
| VEC-IDX-02 | 양자화(int8/int4/BBQ)는 oversample + rescore 와 세트 — 재현율은 측정으로 회복 | vector-index |
| VEC-IDX-03 | 세그먼트마다 HNSW 그래프 — 세그먼트 수가 곧 검색 비용, 머지는 그래프 재구축 비용 | vector-index |
| VEC-IDX-04 | `_source` 에서 벡터 제외 — 9.2+ 는 `index.mapping.exclude_source_vectors`(신규 인덱스 기본 on), `excludes` 는 재색인을 깨뜨린다 | vector-index |
| VEC-IDX-05 | `dot_product` 는 단위 벡터 전제 — 정규화가 확실하지 않으면 `cosine` | vector-index |
| VEC-IDX-06 | 필요한 것만 preload — `.vec`(원본 float) 은 preload 하지 않는다 | vector-index |
| VEC-QRY-01 | `num_candidates` 기본 1.5×k(최대 10,000), k 기본 = size — 재현율 노브는 num_candidates | vector-query |
| VEC-QRY-02 | bool `filter` 는 kNN 의 post-filter — 필터는 knn 의 `filter` 에 넣어야 k 개가 보장된다 | vector-query |
| VEC-QRY-03 | 아주 좁은 pre-filter 는 HNSW 를 비효율적으로 만든다 — 극단적 선택도는 exact 검색이 낫다 | vector-query |
| VEC-QRY-04 | `similarity` 파라미터는 점수가 아니라 원시 유사도 기준 — boost·정규화된 _score 로 임계값을 잡지 않는다 | vector-query |
| VEC-QRY-05 | nested 벡터(청크) kNN 은 `score_mode=max` 만 — 문서 점수 = 가장 비슷한 청크 | vector-query |
| VEC-HYB-01 | `query` + top-level `knn` 을 함께 주면 점수는 단순 합 — BM25 스케일이 벡터 점수를 압도한다 | vector-query |
| VEC-HYB-02 | RRF 의 `rank_window_size` 가 페이지 상한이자 융합 품질 노브 | vector-query |
| VEC-EMB-01 | ELSER 는 영어 전용 — 한국어 시맨틱 검색은 다국어 dense 모델 | vector-query |
| VEC-EMB-02 | E5 계열 모델은 `query: ` / `passage: ` 접두어 규약 — 빠뜨리면 재현율이 조용히 떨어진다 | vector-query |
| VEC-EMB-03 | 질의 임베딩 지연이 검색 지연의 대부분일 수 있다 — 헤드 질의 캐시와 타임아웃 폴백 | vector-query |

## 5. 관련 컴포넌트

- 커맨드(사용자 호출): `/vector-search-review` — 이 ID 로 판정.
- 에이전트: `search-relevance-engineer`(벡터·하이브리드 포함) — 이 스킬을 사전 로드한다.
