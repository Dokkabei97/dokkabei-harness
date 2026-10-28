---
name: search-team-orchestrator
description: |
  검색팀 오케스트레이터(사용자 호출 전용) — 영역이 겹치는 검색 작업을 전문 에이전트 3명에 병렬 분배하고 보고서 하나로 통합.
  Fans out cross-domain ES work to specialist agents and merges one report. Use when: running /search-team-orchestrator.
disable-model-invocation: true
---

# Search Team Orchestrator

검색 영역 전문 에이전트 3명을 조율한다. 단일 영역 질문은 오케스트레이터 없이 해당 허브 스킬(es-deep-patterns / search-relevance-engineering / vector-hybrid-search-patterns)로 충분하다 — 이 스킬은 `/search-team-orchestrator` 로 명시 호출할 때만 쓴다.

## Team Members

| ID | 에이전트 | 영역 | 사전 로드 허브 |
|----|---------|------|---------------|
| QO | es-query-optimizer | 쿼리 DSL·집계 성능, 매핑 비용, 샤드·세그먼트·JVM·서킷 브레이커 | es-deep-patterns |
| RE | search-relevance-engineer | 관련성·nori·동의어·자동완성, 리랭킹, 벡터·하이브리드, 품질 평가 | search-relevance-engineering, vector-hybrid-search-patterns |
| SA | search-service-architect | Kotlin/Java 클라이언트, 타임아웃·재시도, bulk·Kafka/Spark→ES 색인, 재색인·alias | es-deep-patterns |

`search-code-reviewer` 는 PR 전 셀프 리뷰용으로 개발자가 직접 호출한다 — 자동 fan-out 대상이 아니다.

## Step 1 · 분류

| 유형 | 조건 | 실행 |
|------|------|------|
| Single | 한 영역 | 1명 디스패치(또는 허브 스킬로 직접 처리) |
| Multi | 2~3 영역 교차 | 해당 에이전트를 한 메시지에서 병렬 호출 |
| Full | 신규 검색 서비스 설계, 종합 점검, 메이저 업그레이드 계획 | 3명 전원 |

라우팅 힌트(키워드가 아니라 문제의 위치로 판단):
- 느림·timeout·p99·집계·샤드·힙·429 → QO (클라이언트 측 대기가 의심되면 SA 동시 투입 — ES `took` 과 앱 지연 차이)
- 무결과·순위 이상·형태소·동의어·자동완성·벡터·RRF·리랭커 → RE
- 클라이언트 설정·직렬화·bulk 실패·유실/중복/순서 역전·재색인 절차 → SA

사전 정의 시나리오: 신규 검색 기능(SA+RE+QO), 벡터 도입(RE+QO — 메모리·샤드 산정), 색인 파이프라인 점검(SA+QO), 매핑 변경 영향(RE+QO+SA — 재색인 절차).

## Step 2 · 디스패치

```
Agent({ description: "{에이전트} — {작업 요약}", subagent_type: "{agent-id}", prompt: "{대상 파일 경로·ES 버전·배포 형태·질문 범위·출력 형식}" })
```
- 에이전트는 이전 대화를 모른다 — 파일 경로, 확인된 프로젝트 사실(버전, 클라이언트, 색인 소스), 분석 범위를 명시한다.
- 출력 형식 지정: "항목 ID + 신호(근거 코드/메트릭) + 처방 + 검증 방법, severity 포함".
- 의존성이 있으면(예: SA 의 색인 경로 파악 → QO 의 refresh/샤드 판단) 순차 실행.

## Step 3 · 통합 보고서

```markdown
## 통합 분석 보고서
### 요약 (1~3문장)
### 발견 사항
| 에이전트 | 항목 ID | 신호(근거) | Severity | 처방 | 검증 |
### 교차 분석 — 상충 의견, 한 영역 처방의 타 영역 부작용(예: refresh 완화 ↔ 실시간성 요구)
### 우선순위 액션 플랜 — Critical → High → Medium, 각 항목에 측정 방법
### 확인되지 않은 가정 — 버전·설정 등 코드에서 확인 못 한 사실
```
규칙: 두 에이전트가 같은 문제를 지적하면 severity 한 단계 상향. 측정 근거 없는 처방은 "가설"로 표기.

## Error Handling

| 상황 | 대응 |
|------|------|
| 에이전트 실패/타임아웃 | 해당 결과 없이 통합하고 표시 |
| 라우팅 불명확 | 사용자에게 의도 확인 |
| 결과 상충 | 양쪽 근거 제시 + 측정으로 판정할 방법 제안 |

## Boundaries

- 코드 직접 수정, ES 클러스터 직접 접근 없음 — 설계·리뷰·진단 조언만.
- CI/CD·인프라 프로비저닝은 범위 밖.
