---
name: es-query-review
description: |
  Elasticsearch 쿼리 DSL·집계 비용 리뷰 — es-deep-patterns 항목 ID(ES-QRY/ES-AGG/LUC-EXE)로 판정하고 리라이트 제안.
  Reviews ES query DSL and aggregation cost by item ID. Use when: running /es-query-review.
disable-model-invocation: true
---

# /es-query-review

## Usage
```
/es-query-review [path] [--explain] [--suggest-rewrite]
```
- `--explain`: 쿼리별 단계(can_match → query → collect/aggs → fetch) 비용 설명
- `--suggest-rewrite`: 문제 쿼리의 리라이트(JSON + Kotlin elasticsearch-java 빌더)

## Flow
1. **사실 확인** — ES 버전 단서(빌드 파일의 클라이언트 버전, 인프라 코드, 프로젝트 CLAUDE.md), 대상 인덱스 매핑 파일. 모르는 것은 보고서의 "가정" 칸에.
2. **수집** — `co.elastic.clients.elasticsearch` 빌더(`Query.of`, `BoolQuery`, `SearchRequest`), JSON 문자열/리소스 파일, 템플릿(mustache)을 찾아 등가 JSON DSL 로 복원. 쿼리 vs filter vs post_filter vs aggs 컨텍스트를 구분.
3. **판정** — `es-deep-patterns` 의 `references/query-aggregation.md`(ES-QRY/ES-AGG)와 `segments-lucene.md`(LUC-EXE) 항목을 기준으로. 각 지적에 **항목 ID, 신호(파일:라인), 적용 조건 충족 여부, 반례 검토**를 붙인다. 매핑이 원인이면 ES-MAP 항목으로 연결.
4. **보고**

## Output
```
## ES Query Review — [path]
가정: [확인 못 한 버전/매핑 등]
| # | 위치 | 항목 ID | 신호 | Severity | 처방 | 검증(_profile/took/캐시 통계) |
### 리라이트 (--suggest-rewrite)
### 단계별 비용 (--explain)
```
Severity 기준: Critical = 장애·데이터 오류(빈 페이지, 잘못된 집계를 정답으로 사용), High = p99/자원에 측정 가능한 영향, Medium = 조건부 개선.

## Boundaries
- 라이브 클러스터에 쿼리를 실행하지 않는다 — 실행할 `_profile`/`_validate` 요청을 제시만 한다.
- 관련성(분석기·동의어·스코어링)은 `search-relevance-engineering` 항목으로 넘긴다.
