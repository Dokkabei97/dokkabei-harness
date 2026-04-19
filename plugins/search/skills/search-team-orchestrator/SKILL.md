---
name: search-team-orchestrator
description: "검색플랫폼팀 하네스 오케스트레이터. 검색 관련 복합 작업을 분석하여 전문 에이전트를 선택·조합하고, 병렬 분석 결과를 통합하여 통합 보고서를 산출합니다. 검색 설계, 리뷰, 최적화, 파이프라인 작업에 자동 트리거됩니다."
---

# Search Team Orchestrator

검색플랫폼팀의 5명의 전문 에이전트를 조율하는 오케스트레이터.
작업을 분류하고, 적합한 전문가를 선택하며, 복합 작업은 병렬 분석 후 통합한다.

## When to Apply

- 검색 관련 설계/리뷰/최적화 작업이 감지될 때
- 사용자가 "검색팀", "search team", "하네스" 키워드를 사용할 때
- 2개 이상 검색 도메인이 교차하는 복합 작업일 때
- `/es-query-review`, `/search-architecture-review` 등 검색 커맨드 실행 후 후속 조치가 필요할 때

## Architecture

- **패턴**: Expert Pool + Fan-out/Fan-in 하이브리드
- **실행 모드**: Sub-agents (Agent 도구로 전문가 호출, 결과 통합)
- **라우팅**: 오케스트레이터가 작업 분류 → 단일 또는 다중 에이전트 디스패치

## Agent Roster

| ID | 에이전트 | 도메인 | 강점 |
|----|---------|--------|------|
| QO | es-query-optimizer | 쿼리 성능 | DSL 안티패턴, _profile 해석, Lucene 레벨 최적화 |
| RE | search-relevance-engineer | 검색 품질 | 분석기 설계, BM25 튜닝, 동의어, nori, NDCG/MRR |
| SA | search-service-architect | 서비스 설계 | Kotlin+ES 아키텍처, 벌크 인덱싱, 서킷브레이커, 관찰 가능성 |
| HA | hybrid-search-architect | 벡터 검색 | kNN, dense_vector, HNSW, RRF, 임베딩 모델 |
| PE | search-pipeline-engineer | 파이프라인 | Kafka→ES, Spark 배치, Iceberg 동기화, DLQ |

## Execution Workflow

### Step 1: Task Classification

작업을 아래 3가지 유형으로 분류한다:

| 유형 | 조건 | 실행 방식 |
|------|------|----------|
| **Single** | 단일 도메인에 해당 | 1명 디스패치 |
| **Multi** | 2~3개 도메인 교차 | 해당 에이전트 병렬 Fan-out |
| **Full Review** | 종합 리뷰/신규 설계 | 전원(5명) Fan-out |

### Step 2: Routing Rules

#### Single Dispatch (키워드 기반 라우팅)

```
쿼리, DSL, _profile, 슬로우쿼리, from/size, search_after  → QO
분석기, 스코어링, BM25, 동의어, nori, 형태소, 품질, NDCG   → RE
아키텍처, 클라이언트, 벌크, 서킷브레이커, 설계, 서비스      → SA
벡터, kNN, dense_vector, RRF, 임베딩, HNSW, 시맨틱         → HA
Kafka, Spark, Iceberg, 파이프라인, DLQ, 컨슈머, 인덱싱      → PE
```

#### Multi Dispatch (사전 정의 시나리오)

| 시나리오 | 투입 | 근거 |
|----------|------|------|
| 신규 검색 기능 설계 | SA + RE + QO | 서비스 구조 → 관련성 전략 → 쿼리 최적화 |
| 벡터 검색 도입/전환 | HA + SA + RE | 벡터 설계 → 서비스 통합 → 품질 평가 |
| 인덱싱 파이프라인 점검 | PE + SA | 파이프라인 헬스 → 서비스 영향 분석 |
| 매핑 변경 영향 분석 | RE + QO + HA | 분석기 영향 → 쿼리 호환 → 벡터 필드 영향 |
| 검색 성능 종합 진단 | QO + SA + PE | 쿼리 레벨 → 서비스 레벨 → 인덱싱 레벨 |

#### Full Review

아래 키워드 감지 시 전원 투입:
- "종합 리뷰", "전체 점검", "검색 아키텍처 리뷰", "마이그레이션 계획"
- 신규 서비스 런칭, 대규모 리팩터링

### Step 3: Agent Dispatch

**Sub-agent 모드**로 실행한다. 각 에이전트는 `Agent` 도구를 통해 호출:

```
Agent({
  description: "{에이전트명} — {작업 요약}",
  subagent_type: "{agent-id}",
  prompt: "{구체적 분석 요청. 컨텍스트 포함}"
})
```

**병렬 디스패치 규칙:**
- Multi/Full 유형에서는 독립 에이전트를 **단일 메시지에 병렬 Agent 호출**로 디스패치
- 에이전트 간 의존성이 있으면 순차 실행 (예: SA 결과가 QO 입력에 필요한 경우)

**프롬프트 작성 원칙:**
- 에이전트는 이전 대화를 모른다 — 파일 경로, 기술 스택, 분석 대상을 명시
- 분석 범위를 구체적으로 한정 (어떤 파일, 어떤 기능, 어떤 관점)
- 출력 형식 지정: "200자 이내 요약", "테이블 형식", "severity 등급" 등

### Step 4: Result Integration

모든 에이전트 결과를 받은 후 통합 보고서를 작성한다:

```markdown
## 통합 분석 보고서

### 요약
[1~3문장 핵심 결론]

### 에이전트별 분석

| 에이전트 | 핵심 발견 | Severity | 권장 조치 |
|----------|----------|----------|----------|
| QO       | ...      | ...      | ...      |
| RE       | ...      | ...      | ...      |
| ...      | ...      | ...      | ...      |

### 교차 분석
[에이전트 간 의견 충돌, 상호 영향, 통합 관점에서의 인사이트]

### 우선순위 액션 플랜
1. [Critical] ...
2. [High] ...
3. [Medium] ...

### 참고 스킬
[심화 학습이 필요한 경우 관련 스킬 참조 안내]
```

**교차 분석 규칙:**
- 에이전트 간 상충되는 의견이 있으면 명시하고, 오케스트레이터가 판단 근거를 제시
- 한 에이전트의 제안이 다른 도메인에 부작용을 줄 수 있으면 경고
- 공통으로 지적된 이슈는 severity를 한 단계 올림

## Skill References

에이전트 분석 후 심화가 필요한 영역은 아래 스킬로 안내:

| 도메인 | 참조 스킬 |
|--------|----------|
| 쿼리/매핑 심화 | es-deep-patterns |
| Kotlin 클라이언트 | kotlin-es-client-patterns |
| 관련성 튜닝 | search-relevance-engineering |
| 벡터/하이브리드 | vector-hybrid-search-patterns |
| Lucene 내부 | lucene-internals |
| 데이터 파이프라인 | search-data-pipeline |
| 리랭킹/파이프라인 | search-pipeline-reranking |
| 모니터링/대시보드 | search-observability |

## Error Handling

| 상황 | 대응 |
|------|------|
| 에이전트 타임아웃 | 해당 에이전트 결과 없이 통합, "[타임아웃]" 표시 |
| 에이전트 실패 | 에러 원인 보고 후 나머지 결과로 통합 |
| 라우팅 불명확 | 사용자에게 작업 의도 확인 후 재분류 |
| 결과 상충 | 양쪽 관점 모두 제시, 오케스트레이터 권장안 명시 |

## Boundaries

**Will:**
- 작업 분류 및 에이전트 라우팅
- 병렬 디스패치 및 결과 통합
- 교차 분석 및 우선순위 도출
- 관련 스킬/커맨드 안내

**Will Not:**
- 직접 코드 수정 (에이전트에게 위임)
- ES 클러스터 직접 접근
- 에이전트 역할 범위 밖의 작업 (CI/CD, 인프라 등)
