---
name: team-harness
description: |
  Multi-agent team design meta-skill. 도메인 분석, 팀 아키텍처 패턴 선택(6종),
  에이전트 정의 및 오케스트레이터 설계를 수행한다.
  Use when designing teams of 2+ agents that collaborate on complex workflows.
  Use when: "하네스 구성해줘", "팀 설계해줘", "에이전트 팀 만들어줘",
  "build a harness", "design agent team", 멀티 에이전트 협업이 필요한 복합 작업.
  Delegates component creation to /create-flow and validation to /verify-flow.
metadata:
  version: 1.0.0
  category: workflow
  origin: revfactory/harness (Apache-2.0)
---

# Team Harness — 멀티 에이전트 팀 설계 메타 스킬

도메인/프로젝트에 맞는 에이전트 팀을 설계하고, 전문 에이전트를 정의하며, 에이전트가 사용할 스킬을 생성하는 메타 스킬이다.

## When to Apply

- 2명 이상의 에이전트가 협업해야 하는 복합 작업 설계 시
- 기존 에이전트를 팀으로 조직화하려 할 때
- 도메인 분석 → 팀 구성 → 오케스트레이터 설계가 필요할 때
- "하네스 구성", "팀 설계", "에이전트 팀" 키워드가 등장할 때
- 기존 하네스의 유지보수/확장/피드백 반영 시

## Core Principles

1. **에이전트-스킬 분리**: 에이전트는 "누가(Who)" 수행하는지, 스킬은 "어떻게(How)" 수행하는지를 정의
2. **에이전트 팀 우선**: 2명 이상 협업 시 Agent Teams를 기본으로, Sub-agents는 통신 불필요 시 대안
3. **위임 아키텍처**: 컴포넌트 생성은 `/create-flow --team`, 검증은 `/verify-flow --target team`에 위임
4. **살아있는 시스템**: 피드백과 실행 사이클을 통해 진화, 변경 이력은 `claude/CLAUDE.md`에 기록

## Execution Modes

| 모드 | 방법 | 사용 시점 |
|------|------|----------|
| **Agent Teams** (기본) | `TeamCreate` + `SendMessage` + `TaskCreate` | 2+ 에이전트, 상호 통신 필요 |
| **Sub-agents** (대안) | `Agent` 도구 직접 호출 | 결과만 전달, 통신 불필요 |
| **Hybrid** (고급) | Phase별 모드 전환 | Phase마다 협업 요구가 다를 때 |

**판단 기준**: 에이전트 간 교차 통신이 필요한가? → 팀. 결과만 받으면 충분한가? → 서브.

## 6 Architecture Patterns

| 패턴 | 핵심 | 적합한 상황 |
|------|------|-----------|
| **Pipeline** | 순차 핸드오프 | 분석 → 설계 → 구현 → 검증 |
| **Fan-out/Fan-in** | 병렬 분석 → 통합 | 다관점 리서치, 코드 리뷰 |
| **Expert Pool** | 라우터가 전문가 선택 | 요청 유형별 분기 |
| **Producer-Reviewer** | 생성-검증 루프 | 품질 게이트가 필요한 작업 |
| **Supervisor** | 동적 작업 분배 | 런타임 조건에 따른 배정 |
| **Hierarchical** | 재귀적 분해 | 대규모 작업 (2레벨 제한) |

상세: [references/agent-design-patterns.md](references/agent-design-patterns.md)

## Workflow (7 Phases)

### Phase 0: Audit (기존 인프라 감사)
```
Glob: agents/*.md                    → 기존 에이전트 목록
Glob: skills/*/SKILL.md              → 기존 스킬 목록
Read: claude/CLAUDE.md               → 기존 하네스 등록 확인
```
- 기존 하네스 존재 시: 확장/유지보수 분기
- 신규: Phase 1 진행
- `_workspace/` 존재 시: 재실행 감지

### Phase 1: Domain Analysis (도메인 분석)
- 작업 유형과 역할 분해
- 기존 에이전트/스킬과의 충돌 탐지
- 사용자 기술 수준 파악
- 코드베이스 탐색 (기술 스택, 데이터 모델, 모듈 구조)

### Phase 2: Team Architecture Design (팀 설계)
1. 실행 모드 선택 (Team → Sub → Hybrid 우선순위)
2. 패턴 선택 (6종 중 택일 또는 복합)
3. 4축 분리 기준 적용:
   - **전문성**: 도메인이 다른가?
   - **병렬성**: 독립 실행 가능한가?
   - **컨텍스트 범위**: 컨텍스트 부하가 높은가?
   - **재사용성**: 다른 팀/세션에서 재사용 가능한가?

### Phase 3: Component Generation (생성 — create-flow 위임)
```
/create-flow --team --team-name {team-name}
```
- 각 멤버 agent → `agents/{name}.md`
- 오케스트레이터 → `skills/{team-name}-orchestrator/SKILL.md`
- 팀 훅 (선택) → `hooks/hooks.json` 엔트리
- team-agent 템플릿 사용 (Team Communication Protocol 포함)

### Phase 4: Team Registration (등록)
`claude/CLAUDE.md`에 최소 포인터 등록:
```markdown
## Harness: {Domain}
**Trigger:** Use `{orchestrator-skill}` for {domain} tasks.
**Change History:**
| Date | Change | Target | Reason |
```
등록 내용: 트리거 규칙 + 변경 이력 테이블만. 에이전트 목록/디렉토리 구조는 포함하지 않음.

### Phase 5: Validation (검증 — verify-flow 위임)
```
/verify-flow --target team
```
- TEAM-001~008 규칙 (팀 구조 검증)
- ORC-001~008 규칙 (오케스트레이터 검증)
- AGT-021~026 규칙 (팀 에이전트 검증)
- Health Score + Team Assessment 리포트

### Phase 6: Feedback Loop (피드백 루프)
1. 실행 후 피드백 수집 (선택적, 강제하지 않음)
2. 피드백 유형별 라우팅:
   - 결과 품질 → 스킬 수정
   - 역할 문제 → 에이전트 정의 수정
   - 워크플로우 → 오케스트레이터 수정
   - 팀 구성 → 오케스트레이터 + 에이전트
   - 트리거 미스 → description 수정
3. `claude/CLAUDE.md` 변경 이력 업데이트
4. 패턴 반복 2회 이상 또는 실패 발생 시 진화 제안

## Agent Definition Convention

에이전트는 반드시 `agents/{name}.md` 파일로 정의한다 (빌트인 타입도 파일 생성 권장).

필수 섹션:
- 핵심 역할 (Core Responsibilities)
- 작업 원칙 (Work Principles)
- 입력/출력 프로토콜 (I/O Protocol)
- 에러 핸들링 (Error Handling)
- 팀 통신 프로토콜 (Team Communication Protocol) — 팀 모드 시 필수

모델 선택: 모든 팀 에이전트는 `model: "opus"` 필수. 팀 협업의 품질은 모델 능력에 직결되므로 최고 성능 모델을 강제한다

## Skill Writing Convention

- `skills/{name}/SKILL.md` < 500줄; 초과 시 `references/`로 분리
- Description을 "적극적으로" 작성: 트리거 조건과 경계 케이스를 명시
- Why-first: 규칙 강제보다 이유 설명
- 일반화: 특정 예시에만 맞는 수정 대신 원리 수준 수정
- 반복 번들링: 3회 이상 반복되는 스크립트는 `scripts/`에 번들

상세: [references/skill-writing-guide.md](references/skill-writing-guide.md)

## Data Transfer Between Agents

| 방식 | 용도 | 예시 |
|------|------|------|
| **Message** | 실시간 조율 | `SendMessage({to: "reviewer", message: "..."})` |
| **Task** | 작업 상태 + 의존성 | `TaskCreate`, `TaskUpdate` |
| **File** | 대용량 아티팩트 | `_workspace/{phase}_{agent}_{artifact}.{ext}` |
| **Return value** | 서브 에이전트 결과 | `Agent()` 반환값 |

## Reference Files

- [agent-design-patterns.md](references/agent-design-patterns.md) — 6가지 패턴 상세, 분리 기준, 모드 선택
- [orchestrator-template.md](references/orchestrator-template.md) — 3가지 실행 모드별 오케스트레이터 템플릿
- [team-examples.md](references/team-examples.md) — 프로덕션 팀 예시 (리서치, 소설, 코드 리뷰 등)
- [skill-writing-guide.md](references/skill-writing-guide.md) — 스킬 작성 원칙 및 트리거 메커니즘
- [skill-testing-guide.md](references/skill-testing-guide.md) — 이중 평가 프레임워크, 테스트 방법론
- [qa-agent-guide.md](references/qa-agent-guide.md) — QA 에이전트 설계, 경계면 검증 패턴
