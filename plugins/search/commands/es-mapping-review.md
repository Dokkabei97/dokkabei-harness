---
name: es-mapping-review
description: |
  Elasticsearch 매핑·분석기 리뷰 — 필드 타입·매핑 폭발·nested 비용·nori 체인과 재색인 필요 변경을 항목 ID(ES-MAP/KO)로 판정.
  Reviews ES mappings and analyzers, flags reindex-requiring changes. Use when: running /es-mapping-review.
disable-model-invocation: true
---

# /es-mapping-review

## Usage
```
/es-mapping-review [path] [--check-compatibility <old-mapping>]
```
- `--check-compatibility`: 구/신 매핑 diff → 재색인 필요 변경(타입·analyzer·index_options·similarity·nested 전환·index sorting·dense_vector 파라미터) vs 무중단 가능 변경(새 필드 추가, search-time `updateable` 동의어, 일부 동적 설정)을 구분

## Flow
1. **사실 확인** — 매핑 원본(인덱스 템플릿/컴포넌트 템플릿/마이그레이션 스크립트), ES 버전, 쿼리 코드에서 각 필드의 실제 용도(검색·필터·정렬·집계·표시). 용도표 없이 타입을 판정하지 않는다.
2. **필드 판정** — `es-deep-patterns` 의 `references/mapping.md`(ES-MAP-*). 대용량·갱신형이면 `shards-indexing.md`(ES-IDX-07)도.
3. **분석 체인 판정** — `search-relevance-engineering` 의 `references/korean-analysis.md`(KO-*): decompound_mode 의 색인/검색 분리, 품사 필터 위치 간격, 사용자 사전 반영 경로, 동의어 위치(search analyzer), edge_ngram 의 search_analyzer. `_analyze` 검증 요청을 함께 제시.
4. **벡터 필드** — `dense_vector` 가 있으면 `vector-hybrid-search-patterns` 의 VEC-IDX-*.
5. **보고**

## Output
```
## ES Mapping Review — [path]
가정: [...]
| 필드 경로 | 용도(근거 코드) | 항목 ID | 신호 | Severity | 처방(매핑 JSON) | 재색인 필요 |
### 호환성 (--check-compatibility): 변경 목록 → 재색인 필요/불필요 → alias 스왑 절차(ES-ING-04)
### 검증 요청: _analyze / _disk_usage / _field_caps 예시
```

## Boundaries
- 매핑을 클러스터에 적용하지 않는다. 변경안은 새 인덱스 기준으로 제시한다.
