> [English](README.md) · **한국어**

# search

> Elasticsearch 스페셜리스트 레이어 — 강한 시니어도 놓치기 쉬운 ES/Lucene 성능·매핑·클러스터 운영·Kotlin/Java 클라이언트·색인 파이프라인·한국어(nori) 관련성·벡터/하이브리드 검색의 함정 모음. 모든 항목은 ID, 적용 조건, 신호, 메커니즘, 처방, 반례, 검증 방법, 공식 근거를 가진다.

설치: `/plugin install search@dokkabei-harness`

## 설계

- **진입 허브 3개 + 레퍼런스.** 모델이 스스로 부르는 스킬은 3개뿐이다. 각 `SKILL.md` 는 짧은 트리아지 인덱스(증상 → 레퍼런스 파일 → 항목 ID)이고, 지식은 `references/*.md` 의 ID 항목(`ES-*`, `LUC-*`, `KO-*`, `VEC-*`)에 있다. 스킬 목록 예산을 줄여 description 이 목록에서 탈락하지 않게 한다.
- **강제가 아니라 가이드.** 허브는 먼저 프로젝트 사실(ES 버전, 배포 형태, 클라이언트, 매핑 원본, 색인 경로)을 확인하라고 안내하며 스택을 단정하지 않는다. 항목의 `적용`·`반례` 로 맞지 않는 항목은 버린다.
- **프로젝트별 선별.** 어떤 ID 가 해당 저장소에 유효한지는 프로젝트 `CLAUDE.md`/`.claude/rules` 에 기록한다(예: `workflow:project-rules`). 이 플러그인은 스택 공통 레이어다.

## 구성 요소

### 스킬 (모델 발화 진입 허브)

| 스킬 | 범위 | 항목 접두어 |
|---|---|---|
| `es-deep-patterns` | ES/Lucene 성능, 샤드, 대량 색인, 매핑, 쿼리·집계 비용, 세그먼트·머지, JVM·서킷 브레이커·429, Kotlin/Java·Go 클라이언트, Kafka/Spark→ES 색인, 증상 기반 진단 | `ES-SHD` `ES-IDX` `ES-MAP` `ES-QRY` `ES-AGG` `LUC-SEG` `LUC-EXE` `ES-JVM` `ES-OPS` `ES-CLI` `ES-ING` |
| `search-relevance-engineering` | 관련성, nori 분석, 동의어, 자동완성, BM25·multi_match, 리랭킹·RRF, 품질 평가 | `KO-ANA` `KO-SYN` `KO-AC` `ES-REL` `ES-RNK` `ES-EVL` |
| `vector-hybrid-search-patterns` | dense_vector 메모리·양자화, kNN 필터·재현율, 하이브리드 융합, 한국어 임베딩 | `VEC-MEM` `VEC-IDX` `VEC-QRY` `VEC-HYB` `VEC-EMB` |

사용자 호출 전용: `search-team-orchestrator`(`/search-team-orchestrator`) — 여러 영역에 걸친 작업을 아래 에이전트에 병렬로 나누고 보고서 하나로 통합한다.

### 커맨드 (사용자 호출, `disable-model-invocation: true`)

- `/es-query-review` — 쿼리 DSL·집계 비용 리뷰(`ES-QRY`/`ES-AGG`/`LUC-EXE`).
- `/es-mapping-review` — 매핑·분석기 리뷰, 재색인 필요 변경 탐지.
- `/index-lifecycle` — 샤드 산정, ILM, 무중단 재색인 런북, 색인 경로 점검(`--pipeline`, 구 `/index-pipeline-check`).
- `/vector-search-review` — 벡터·하이브리드 리뷰와 메모리 산정.
- `/search-quality` — 골든 질의셋, `_rank_eval`, 온라인 평가 설계.

### 에이전트

| 에이전트 | 역할 | 사전 로드 스킬 |
|---|---|---|
| `es-query-optimizer` | 쿼리·클러스터 성능(profile, 집계, 매핑 비용, 샤드, JVM) | `es-deep-patterns` |
| `search-relevance-engineer` | 관련성, 한국어 분석, 리랭킹, 벡터·하이브리드 | `search-relevance-engineering`, `vector-hybrid-search-patterns` |
| `search-service-architect` | 클라이언트, 타임아웃·재시도, bulk, Kafka/Spark 색인, 재색인 | `es-deep-patterns` |
| `search-code-reviewer` | 팀 테크리드 스타일 PR 전 Kotlin 리뷰(`[Sug]`/`[Q]`/`[High]`), 명시 호출 | — |

## 아카이브 (2026-10)

`archive/components/search/` 로 이동 — 스페셜리스트 내용은 허브 references 로 추출했다:
스킬 `kotlin-es-client-patterns`, `lucene-internals`, `search-data-pipeline`, `search-diagnostics`(→ `es-deep-patterns/references/diagnostics.md`), `search-observability`, `search-pipeline-reranking`; 커맨드 `index-pipeline-check`(→ `/index-lifecycle --pipeline`), `search-architecture-review`; 에이전트 `hybrid-search-architect`(→ `search-relevance-engineer`), `search-pipeline-engineer`(→ `search-service-architect`).

## 참고

- 항목마다 적용 ES 버전을 적었다(8.x/9.x 차이: `dense_vector` 기본 index_options, `exclude_source_vectors`, Rest5Client 등). 기본값·수치는 링크된 공식 문서 기준이며 사용 중인 클러스터 버전으로 재확인한다.
- 라이브 클러스터에 접근하지 않는다. 에이전트·커맨드는 검증용 요청(`_profile`, `_analyze`, `_rank_eval`, recall@k)을 함께 제시한다.
