# search

> Elasticsearch 검색 엔지니어링 전문 하네스 — 쿼리 최적화·관련성 튜닝·벡터/하이브리드 검색·인덱싱 파이프라인을 전문 에이전트 팀으로 설계·리뷰·진단한다.

## 개요

`search`는 프로덕션 Elasticsearch(8.x, 한국어 nori 컨텍스트) 검색 시스템을 다루는 검색플랫폼팀 전용 하네스다. ES 쿼리 DSL 최적화, 검색 관련성(BM25/분석기/동의어) 튜닝, 벡터·하이브리드 검색(kNN, dense_vector, HNSW, RRF), Kafka/Spark/Iceberg 데이터 파이프라인 연동, 인덱스 수명주기, 그리고 증상 기반 진단(`_profile`/`_explain`/`_termvectors`)까지 검색 도메인 전 범위를 다룬다.

핵심 설계는 **Expert Pool + Fan-out/Fan-in** 팀 오케스트레이션이다. `search-team-orchestrator` 스킬이 작업을 Single/Multi/Full Review로 분류해 5명의 도메인 전문 에이전트를 단일 디스패치하거나 병렬로 Fan-out한 뒤 결과를 하나의 통합 보고서로 Fan-in한다. 정형화된 리뷰가 필요할 때는 슬래시 커맨드를, 심화 지식이 필요할 때는 스킬을 참조하는 3층 구조(커맨드 → 에이전트 → 스킬)로 구성된다.

Kotlin/Spring Boot 검색 서비스 코드 관점을 포함하지만, 오케스트레이터와 에이전트는 직접 코드를 수정하거나 ES 클러스터에 접근하지 않고 설계·리뷰·진단 조언을 산출하는 것을 경계로 삼는다.

## 구성요소

### 커맨드

- `es-query-review` — ES query DSL 리뷰. 안티패턴 탐지, 복잡도 평가, 최적화 제안.
- `es-mapping-review` — 인덱스 매핑 리뷰. 필드 타입 검증, analyzer 체크, 호환성 분석.
- `vector-search-review` — 벡터 검색 리뷰. `dense_vector` 매핑 검증, kNN 쿼리 최적화, 임베딩 파이프라인 분석, 하이브리드(RRF) 설정 점검.
- `search-architecture-review` — 다단계 검색(multi-stage retrieval) 아키텍처 리뷰. 파이프라인 단계 평가, 누락 단계 탐지, 지연 예산(latency budget) 분석.
- `search-quality` — 검색 품질 평가. 관련성 테스트 케이스 설계, 메트릭 프레임워크, A/B 테스트 스펙.
- `index-lifecycle` — 인덱스 수명주기 관리. ILM 정책 설계, 리인덱싱 계획, 샤드 사이징.
- `index-pipeline-check` — 인덱싱 파이프라인 헬스 체크. Kafka 컨슈머 설정 검증, ES 벌크 인덱싱 패턴 리뷰, 모니터링 셋업 감사.

### 에이전트

오케스트레이터가 Fan-out으로 조율하는 5인 Expert Pool:

- `es-query-optimizer` — 쿼리 DSL 성능 분석·최적화. 안티패턴 탐지, `_profile` 출력 해석, 쿼리 리라이트 제안. (QO)
- `search-relevance-engineer` — 검색 품질·관련성 튜닝. 분석기 설계, 스코어링 전략, 동의어 관리, 한국어 형태소 분석, 품질 평가. (RE)
- `search-service-architect` — Kotlin(Spring Boot)+ES 서비스 아키텍처 설계. 클라이언트 설정, 벌크 인덱싱, 비동기 검색, 서킷브레이커, 관찰 가능성. (SA)
- `hybrid-search-architect` — 벡터·시맨틱·하이브리드(RRF) 검색 설계. 임베딩 모델 선택, `dense_vector` 매핑, HNSW 튜닝, 한국어 임베딩 최적화. (HA)
- `search-pipeline-engineer` — 데이터 파이프라인→ES 인덱싱 통합. Kafka 컨슈머, Spark 배치 인덱싱, Iceberg 동기화, DLQ, 파이프라인 모니터링. (PE)

Pool과 별개로 명시 호출하는 온디맨드 리뷰어:

- `search-code-reviewer` — 검색 서비스 Kotlin 코드 리뷰(테크 리드 스타일, `[Sug]`/`[Q]`/`[High]` 태그). 네이밍·헥사고날 경계·DTO·Nullable·하드코딩·검색 도메인 관점. 개발자가 PR 전 셀프 리뷰용으로 직접 호출한다(자동 Fan-out 대상 아님).

### 스킬

- `search-team-orchestrator` — 팀 오케스트레이터. 작업 분류(Single/Multi/Full Review), 키워드·증상 기반 라우팅, 병렬 디스패치, 통합 보고서 산출.
- `es-deep-patterns` — ES 쿼리·매핑·인덱싱·운영 심화 패턴/안티패턴(한국어 분석 지원).
- `search-relevance-engineering` — 관련성 튜닝, 분석기 설계, 멀티필드 검색, 동의어, BM25 튜닝, 한국어 분석기, 품질 메트릭.
- `vector-hybrid-search-patterns` — 벡터(kNN)/시맨틱(ELSER·임베딩)/하이브리드(RRF) 설계. `dense_vector` 매핑, HNSW 튜닝, 한국어 임베딩, RRF 융합, Kotlin 클라이언트 패턴.
- `search-pipeline-reranking` — 다단계 검색, 리랭킹(rescore/Retriever/LTR/cross-encoder), 쿼리 이해, 결과 다양화, 개인화. ES 8.x Retriever 추상화 포함.
- `search-data-pipeline` — ES 적재용 데이터 인제스천 파이프라인. Kafka 컨슈머 패턴, Iceberg/Spark/Trino 배치 리인덱싱, 파이프라인 모니터링.
- `kotlin-es-client-patterns` — Kotlin/Python ES 통합 구현. 클라이언트 설정, 검색 구현, 벌크 인덱싱, 테스트, 흔한 실수(elasticsearch-java v8, elasticsearch-py).
- `lucene-internals` — 세그먼트/Lucene 레벨 성능 진단. `_profile`/`_explain` 해석, 스코어링 내부, 역색인 구조, merge policy 튜닝, OS 레벨 성능 요인.
- `search-observability` — 검색 메트릭 수집, 클릭 추적, 검색 A/B 테스트, 품질 모니터링, 슬로우 쿼리 분석. Micrometer, Kotlin/Spring Boot 대시보드 설계.
- `search-diagnostics` — 증상 기반 진단 허브. 무결과·오정렬·느림·불안정 지연 등 증상을 올바른 진단 API(`_profile`/`_explain`/`_termvectors`/`_validate`/`_analyze`/`_tasks`/`hot_threads`/`breaker`)로 라우팅하는 의사결정 트리.

## 사용법

- **정형 리뷰**: `/es-query-review`, `/vector-search-review`, `/search-architecture-review` 등 슬래시 커맨드로 특정 대상을 즉시 점검한다.
- **복합 작업 오케스트레이션**: "검색팀", "하네스" 키워드나 2개 이상 도메인이 교차하는 작업이 감지되면 `search-team-orchestrator`가 자동 트리거되어 적합한 전문가를 선택·조합한다.
  - Single(단일 도메인) → 1명 디스패치, Multi(2~3개 교차) → 해당 에이전트 병렬 Fan-out, Full Review(종합 리뷰/신규 설계) → 5인 전원 Fan-out.
  - 사전 정의 시나리오 예: 신규 검색 기능 설계(SA+RE+QO), 벡터 검색 도입(HA+SA+RE), 인덱싱 파이프라인 점검(PE+SA), 검색 성능 종합 진단(QO+SA+PE).
- **증상 기반 진단**: 검색이 오동작할 때(문서가 안 잡힘/순서 이상/느림/p99 튐) `search-diagnostics`가 증상을 진단 API로 라우팅하고 필요 시 RE·QO 에이전트로 연결한다.
- **PR 전 셀프 리뷰**: `search-code-reviewer`를 명시적으로 호출해 Kotlin 검색 서비스 코드를 로컬에서 점검한다.
- **심화 학습**: 에이전트 분석 후 심화가 필요하면 오케스트레이터가 도메인별 스킬(es-deep-patterns, lucene-internals 등)을 참조로 안내한다.

## 의존성

`plugin.json`/`marketplace.json`에 강제 의존성(`requires`)은 없다. 다만 검색 서비스가 Kotlin/Spring Boot로 구현되는 경우 `backend-kotlin` 플러그인, SQL·아키텍처·성능 심화 리뷰가 필요한 경우 `analyze` 플러그인과 함께 쓰면 상호 보완적이다.

## 참고

- 대상 스택은 **Elasticsearch 8.x**, 한국어 분석은 **nori** 형태소 분석기 컨텍스트를 전제로 한다.
- 오케스트레이터와 5인 Pool 에이전트는 **직접 코드를 수정하거나 ES 클러스터에 접근하지 않는다** — 설계·리뷰·진단 조언을 산출하고 실제 변경은 사용자/개발자가 수행한다.
- `search-code-reviewer`는 자동 Fan-out 대상이 아니며 PR 전 셀프 리뷰용으로 **명시 호출**해야 한다.
- 산출물은 관련성·성능 개선 조언이며, 프로덕션 부하 테스트나 실제 색인 데이터 기반 검증을 대체하지 않는다. 매핑 변경·리인덱싱 등 파괴적 작업은 반영 전 검증 환경에서 확인하라.
