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

### 검증·루프 보강 패턴 (2026 트렌드 반영)

위 6패턴 위에 아래 보강 패턴을 선택적으로 결합한다. "검증은 모델 밖에 둔다" / "루프 엔지니어링" 트렌드 대응 — 에이전트의 자기평가는 신뢰하지 않는 것이 핵심.

| 보강 패턴 | 핵심 | 결합 대상 | 주의 |
|----------|------|----------|------|
| **Adversarial Verify** | 독립 비평가가 발견을 *반증* 시도(자기 발견 제외), 반증 실패 시 통과 | Fan-out/Fan-in, Expert Pool | 절대 점수보다 반증·비교가 신뢰성 ↑. 기본값 통과로 과잉 강등 방지 |
| **Loop-until-dry** | 새 발견이 없을 때까지 반복(고정 횟수 ❌) | 발견 범위 미상의 대형 작업 | 도메인이 고정·소수면 미적용(과잉) |
| **Verification Gate** | 테스트·린터·타입체커 등 *결정론적* 게이트가 종료 조건 | Pipeline | 검증을 LLM 자기평가에 맡기지 말 것 |
| **Guardrails** | circuit breaker·no-progress·토큰 예산 | 모든 장기 실행 | 비용 폭주·무한 루프 차단 |

> 적용 예: search 오케스트레이터(Expert Pool + Adversarial Verify + Loop-until-dry), legacy 오케스트레이터(Pipeline + Verification Gate + Guardrails).

## Loop Harness Design (루프 하네스 설계)

대부분의 팀은 **단일 패스**(fan-out/pipeline 1회)다. 그러나 "조건이 충족될 때까지 반복"이 필요하면 **루프 하네스**로 설계한다 — 이것이 루프 엔지니어링의 본체다.

**판단:** Phase 2에서 아래 중 하나라도 참이면 루프 하네스를 고려한다.
- 완료가 1회 실행으로 보장되지 않음 (예: "테스트 전부 통과까지", "이슈 0건까지")
- 작업량이 미상이거나 점진적 (백로그 소진, 발견 수렴)
- 스케줄로 스스로 깨어나야 함 (야간 점검, CI 실패 대응)

루프 하네스는 4요소를 **반드시** 명시한다. 하나라도 빠지면 무한 루프·비용 폭주 위험이 있다.

| 요소 | 선택지 | 기본 권장 |
|------|--------|----------|
| **① 루프 엔진** | Stop훅 재주입 / headless `claude -p` 셸 루프 / Workflow 도구 / 스케줄(`/loop`·Routines·Cron) | 세션 내 자기반복=Stop훅, 무인 배치=headless, 결정론적 다단계=Workflow |
| **② 정지 조건** | 결정론적 게이트(테스트·린터·타입체크) + 회의적 Evaluator(자기평가 ❌) + completion promise(`<promise>DONE</promise>`) | 셋 결합. **완료 판정은 모델이 아니라 하네스가 한다** |
| **③ 메모리** | `.planning/{harness}-{id}.md`(계획·진행) + git history(상태) | `.planning/` 단일 표준 + 재개 프로토콜 |
| **④ 가드레일** | max iterations · no-progress 감지 · 비용/시간 상한 | 셋 다 필수. 기본 max 10 / no-progress 2회 / 비용 상한 명시 |

> 5대 프리미티브 매핑: ①=Automations, 병렬 변경 시 worktree 격리, 지식=Skills, 외부도구=MCP(Connectors), ②의 Evaluator=maker/checker sub-agent 분리, ③=Memory.

상세 엔진별 레시피(Ralph / 2-Phase / PRD-driven)와 Stop훅 구현·재개 프로토콜: [references/loop-harness-guide.md](references/loop-harness-guide.md)
재사용 템플릿: flow-scaffolding `templates/loop-stop-hook.sh`, `templates/loop-hooks.json`

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

**Drift Detection (3자 대조):** 아래 셋의 일치 여부를 확인하고 불일치를 플래그한다.

| 대조축 | 확인 대상 |
|--------|----------|
| 파일 실재 | `agents/`·`skills/` 실제 파일 |
| 등록 기록 | CLAUDE.md 하네스 트리거 + 변경 이력 |
| 오케스트레이터 | 오케스트레이터 SKILL의 Agent Roster·참조 목록 |

- 파일은 있는데 CLAUDE.md/오케스트레이터에 없음 → **미등록** 플래그
- 기록엔 있는데 파일 없음 → **유령 참조** 플래그
- 버전·설명 불일치(plugin.json ↔ README ↔ CLAUDE.md) → **버전 드리프트** 플래그

드리프트 발견 시, 신규 작업에 앞서 정합화를 우선 제안한다.

### Phase 1: Domain Analysis (도메인 분석)
- 작업 유형과 역할 분해
- 기존 에이전트/스킬과의 충돌 탐지
- 사용자 기술 수준 파악
- 코드베이스 탐색 (기술 스택, 데이터 모델, 모듈 구조)

### Phase 2: Team Architecture Design (팀 설계)
0. **단일 패스 vs 루프 판정**: 반복이 필요하면 [Loop Harness Design](#loop-harness-design-루프-하네스-설계)의 4요소를 함께 설계
1. 실행 모드 선택 (Team → Sub → Hybrid 우선순위)
2. 패턴 선택 (6종 중 택일 또는 복합)
3. 4축 분리 기준 적용:
   - **전문성**: 도메인이 다른가?
   - **병렬성**: 독립 실행 가능한가?
   - **컨텍스트 범위**: 컨텍스트 부하가 높은가?
   - **재사용성**: 다른 팀/세션에서 재사용 가능한가?

### Phase 3: Component Generation (생성 — create-flow 위임)

**재사용 우선 게이트 (생성 전 필수):** 새 컴포넌트를 만들기 전에 Phase 0 감사 목록과 대조해 판정한다.

| 판정 | 조건 | 동작 |
|------|------|------|
| **재사용** | 기존 에이전트/스킬이 역할을 이미 커버 | 신규 생성 금지, 기존 참조 |
| **확장** | 기존과 대부분 겹치나 일부 부족 | 기존 정의 수정·보강 (신규 ❌) |
| **신규** | distinct domain — 기존으로 커버 불가 | 신규 생성 진행 |

> 원칙: **"distinct domain일 때만 신규 생성."** 중복 에이전트/스킬은 트리거 충돌과 유지보수 부채를 만든다. 판정 근거를 한 줄로 남긴다.

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
