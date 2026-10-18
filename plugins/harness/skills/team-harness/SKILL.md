---
name: team-harness
description: |
  멀티 에이전트 하네스(팀) 설계 메타 스킬 v2 — 도메인 분석, 실행 모드 3종(워크플로 조율·지속형
  에이전트 협업·서브에이전트 위임) 선택, 6가지 팀 패턴과 검증 패턴 조합, 업무 기반 모델 티어
  (fable/opus/sonnet), 에이전트·스킬·오케스트레이터 설계, v1(TeamCreate) 하네스의 v2 전환을 수행한다.
  생성은 /create-flow, 검증은 /verify-flow에 위임. 하네스 점검·감사·동기화 같은 운영 요청도 담당한다.
  실행 결과 회고·피드백 반영은 harness:evolve, 현재 세션의 교정 회고는 workflow:retro 소관.
  Use when: "하네스 구성해줘", "하네스 설계", "팀 설계해줘", "에이전트 팀 만들어줘", "하네스 점검",
  "에이전트/스킬 동기화", "v1 하네스 마이그레이션", 2명 이상 에이전트 협업이 필요한 복합 작업.
  Multi-agent harness design meta-skill v2: domain analysis, three execution modes (Workflow orchestration, persistent named-agent collaboration, sub-agent delegation), six team patterns plus verification patterns, task-based model tiers, agent/skill/orchestrator design, and v1→v2 migration; delegates generation to /create-flow and validation to /verify-flow. Use when: building, extending, auditing, or migrating a harness or agent team — retrospectives go to harness:evolve.
metadata:
  version: 2.0.0
  category: workflow
  origin: revfactory/harness v2.1.0 (Apache-2.0)
---

# Team Harness v2 — 멀티 에이전트 팀 설계 메타 스킬

도메인/프로젝트에 맞는 에이전트 팀을 설계하고, 전문 에이전트를 정의하며, 에이전트가 사용할 스킬과 이를 묶는 오케스트레이터를 만든다.

## When to Apply

- 2명 이상의 에이전트가 협업해야 하는 복합 작업 설계 시
- 기존 하네스에 에이전트·스킬을 추가하거나 구조·실행 모드를 바꿀 때
- 기존 하네스를 점검·감사·동기화할 때 (Phase 7 운영 절차)
- 오케스트레이터에 `TeamCreate`/`TeamDelete`가 남은 v1 하네스를 v2로 옮길 때

**발동하지 않음:** 실행 결과 회고·피드백 반영 → `harness:evolve` / 현재 세션의 교정·교훈 정리 → `workflow:retro`

## Core Principles

1. **에이전트-스킬 분리**: 에이전트는 누가(Who), 스킬은 어떻게(How) 수행하는지 정의한다
2. **제어 흐름으로 실행 모드 선택**: 팀 크기가 아니라 "순서·반복 조건을 코드로 정할 수 있는가"로 고른다
3. **업무 기반 모델 티어**: 에이전트의 위상이 아니라 업무 성격으로 모델을 고르고 이유를 남긴다
4. **위임 아키텍처**: 컴포넌트 생성은 `/create-flow --team`, 검증은 `/verify-flow --target team`에 위임한다
5. **CLAUDE.md는 트리거만, 변경 이력은 git**: 프로젝트 `CLAUDE.md`에는 오케스트레이터 호출 조건만 둔다. 무엇을 왜 바꿨는지는 Conventional Commits 커밋 본문이 원장이다
6. **살아있는 시스템**: 실행 결과의 회고·반영은 `harness:evolve`가 맡는다
7. **산출물 언어**: 생성물은 사용자가 대화에 쓰는 언어로 쓴다. 기존 하네스를 확장하면 기존 파일의 언어를 따른다. 이 스킬이 한국어라는 이유로 한국어로 쓰지 않는다

## Execution Modes

| 모드 | 사용 기능 | 알맞은 작업 |
|------|----------|-----------|
| **A. 워크플로 조율** | `Workflow` 스크립트: `agent()`·`pipeline()`·`parallel()`·`phase()`, `schema`, `budget`, `resumeFromRunId` | 처리 목록·검증 절차·반복 횟수를 코드로 정할 수 있음. 스키마 결과가 필요하거나 `Agent`를 수십 번 호출 |
| **B. 지속형 에이전트 협업** | `Agent(name:)` + `SendMessage({to: "<name>"})` + `TaskCreate`/`TaskUpdate` | 이름 있는 전문가가 맥락을 유지하며 피드백·협상·공동 편집을 반복 |
| **C. 서브에이전트 위임** | `Agent` 1회 호출 (병렬은 한 메시지에 N개) | 에이전트끼리 대화 불필요, 결과만 한 번 받음 |

**결정 순서:** ① 제어 흐름을 코드로 표현 가능 → A (같은 입력에 같은 구조로 재실행 가능) ② 대화·맥락 유지가 필요 → B ③ 결과만 필요 → C ④ 단계마다 성격이 다르면 혼합하고 각 단계 위에 `**실행 모드:**`를 적는다 (예: A로 수집 → B로 합의, B로 초안 → A로 적대적 검증).

- `TeamCreate`/`TeamDelete`/`team_name`, `to: "all"` 브로드캐스트, `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`는 **현행 런타임에 없다**. 이름 붙여 실행한 에이전트는 세션의 암묵 협업 그룹에 자동으로 속하고 "세션당 1팀" 제약도 없다
- `Workflow`는 사용자의 명시적 동의가 필요하다(직접 요청했거나, `Workflow` 호출을 지시하는 오케스트레이터 스킬을 사용자가 불렀을 때). 기본 규모는 작게, "철저히"·"전수" 요청 시에만 확대

상세(동시 실행 상한·스키마·예산·재개·v1→v2 전환 표): [references/execution-modes.md](references/execution-modes.md), 스크립트 스켈레톤과 함정: [references/workflow-recipes.md](references/workflow-recipes.md)

## 6 Architecture Patterns

| 패턴 | 핵심 | 권장 실행 모드 |
|------|------|--------------|
| **Pipeline** | 순차 핸드오프 | A `pipeline()` |
| **Fan-out/Fan-in** | 병렬 분석 → 통합 | A `pipeline()`, 전체 결과가 필요할 때만 `parallel()` |
| **Expert Pool** | 입력에 맞는 전문가만 호출 | C 또는 B |
| **Producer-Reviewer** | 생성-검증 루프 | A 적대적 검증 또는 B 한 쌍 |
| **Supervisor** | 진행 상황 보고 동적 재배분 | B + 공유 작업 목록 |
| **Hierarchical** | 재귀적 분해 | 2레벨 제한, 워크플로 중첩은 1단계 |

에이전트 분리 4축: **전문성**(도메인이 다른가) · **병렬성**(독립 실행 가능한가) · **컨텍스트 범위**(유지할 맥락이 큰가) · **재사용성**(다른 팀/세션에서 쓰는가). 상세: [references/team-patterns.md](references/team-patterns.md)

### 검증·루프 보강 패턴

에이전트의 자기평가는 신뢰하지 않는다 — 검증은 모델 밖에 둔다. 6패턴 위에 선택적으로 결합한다.

| 보강 패턴 | 핵심 | 주의 |
|----------|------|------|
| **Adversarial Verify** | 발견 1건마다 N명의 독립 검증자가 반증 시도, 과반 `confirmed`만 통과 | `refuted`·`uncertain`은 통과로 세지 않음 |
| **Judge Panel** | N개 시안을 따로 만들고 병렬 심사 → 최선안 기반 최종본 | 시안 생성자와 심사자 분리 |
| **Loop-until-dry** | 새 발견이 K회 연속 0건일 때까지 반복(고정 횟수 ❌) | 도메인이 고정·소수면 과잉 |
| **Multi-axis Sweep** | 컨테이너·내용·개체·시간 등 다른 기준으로 병렬 탐색 | 축끼리 중복 제거 필요 |
| **Completeness Critic** | 마지막 에이전트는 빠진 것만 찾는다 | 기존 발견 재검토 금지 |
| **Verification Gate** | 테스트·린터·타입체커 등 결정론적 게이트가 종료 조건 | LLM 자기평가에 맡기지 말 것 |
| **Guardrails** | circuit breaker·no-progress·토큰 예산(`budget.remaining()`) | 모든 장기 실행에 필수 |

> 적용 예: search 오케스트레이터(Expert Pool + Adversarial Verify + Loop-until-dry), wiki-ops 오케스트레이터(Pipeline + Verification Gate + Guardrails).

## Cross-Harness Orchestration (하네스 간 협업)

하네스는 단독 특화로 끝나지 않는다 — 필요할 때 **기존 하네스를 유동적으로 호출**하는 것이 최종 형태다.
오케스트레이터 설계 시 다음 4가지를 포함한다:

1. **협업 호출 규약 표** (표준 표기 `| 시점 | 호출 대상 | 용도 |`): 루프/Stage 안에서 언제 어떤 타 하네스
   스킬·에이전트를 부르는지 명시. 정본 예: wiki-ops-orchestrator·search-team-orchestrator
2. **위임 경계**: 발동하지 않는 도메인과 그 소관 하네스를 description·When to Apply에 명시
   (예: hr→legal 강제 에스컬레이션, finance→legal 형사 신호 위임, wiki-ops→deep-research)
3. **재사용 vs 복제 구분**: 루프 엔진은 **재사용이 기본**(wiki-ops→harness generic, `requires` 선언 + XRF-016
   3소스 일치). 정지조건이 도메인 고유(verified 마커·baseline)일 때만 패턴 복제(자체 훅 + bats 의무)
4. **네이티브 프리미티브 경계**: 같은 층 이중 소유 금지 — 판정은 Stop훅 하나, 트리거(`/loop`·`/schedule`)는
   감싸기 허용. 상세 라우팅 규약: [loop-harness-guide](references/loop-harness-guide.md)

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

> Stop훅은 연속 8회 블록 후 Claude Code가 턴을 강제 종료한다(실측) — 세션 내 Stop훅 루프의 실질 상한은 8회다. 더 긴 반복은 headless 엔진으로 설계한다.

상세 엔진별 레시피(Ralph / 2-Phase / PRD-driven)와 Stop훅 구현·재개 프로토콜: [references/loop-harness-guide.md](references/loop-harness-guide.md)
재사용 템플릿: flow-scaffolding `templates/loop-stop-hook.sh`, `templates/loop-hooks.json`

## Workflow (8 Phases)

### Phase 0: Audit (현재 상태 점검)

```
Glob: agents/*.md, plugins/*/agents/*.md                 → 기존 에이전트
Glob: skills/*/SKILL.md, plugins/*/skills/*/SKILL.md     → 기존 스킬
Read: CLAUDE.md                                          → 하네스 트리거 등록
Bash: git log --oneline -- <하네스 경로>                  → 변경 이력
```

1. 상태에 따라 분기한다 — **신규 구축**(디렉터리 없음/비어 있음): Phase 1부터 전부 / **확장**: 아래 표의 필요한 Phase만 / **운영·유지보수**: Phase 7로 이동

   | 변경 내용 | P1 분석 | P2 설계 | P3 에이전트 | P4 스킬 | P5 통합 | P6 등록 | P7 검증 |
   |----------|--------|--------|-----------|--------|--------|--------|--------|
   | 에이전트 추가 | 생략 | 모드·단계 배치만 | 필수 | 전용 스킬 필요 시 | 오케스트레이터 수정 | 트리거 변경 시 | 필수 |
   | 스킬 추가·수정 | 생략 | 생략 | 생략 | 필수 | 연결이 바뀔 때 | 생략 | 필수 |
   | 구조·실행 모드 변경 | 생략 | 필수 | 영향받는 것만 | 영향받는 것만 | 필수 | 트리거 변경 시 | 필수 |

2. **v1 산출물 감지**: 오케스트레이터에 `TeamCreate`·`TeamDelete`·`team_name`·`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`가 있으면 v1이다. v1 오케스트레이터는 이 API를 호출하다 단일 에이전트 실행으로 조용히 퇴화한다 — v2 전환을 먼저 제안한다(`references/execution-modes.md` 「v1에서 v2로 전환」).
3. **Drift Detection (3자 대조)** — 불일치를 플래그하고, 발견 시 신규 작업에 앞서 정합화를 우선 제안한다.

   | 대조축 | 확인 대상 | 불일치 플래그 |
   |--------|----------|-------------|
   | 파일 실재 | `agents/`·`skills/` 실제 파일 | 기록에만 있음 → **유령 참조** |
   | 등록 기록 | `CLAUDE.md` 하네스 트리거 | 파일에만 있음 → **미등록** |
   | 오케스트레이터 | `## Team Members` 표·참조 목록 | 버전·설명 불일치(plugin.json ↔ README ↔ CLAUDE.md) → **버전 드리프트** |

4. `_workspace/`가 있으면 재실행으로 판단한다. 점검 결과와 실행 계획을 사용자에게 알리고 확인받는다.

### Phase 1: Domain Analysis (도메인 분석)

- 분야·목표를 파악하고 작업 종류(생성·검증·편집·분석)를 나눈다
- 실행 모드 판단용 질문: 처리 목록을 미리 나열할 수 있는가? 검증-재작업 반복이 필요한가? 에이전트끼리 의견을 주고받아야 결과가 좋아지는가? 같은 전문가와 계속 대화해야 하는가?
- 기존 에이전트/스킬과의 충돌 탐지, 코드베이스 탐색(기술 스택·데이터 모델·모듈 구조)
- 사용자 기술 수준 파악 — 코딩 경험이 적으면 assertion·JSON Schema 같은 용어를 설명 없이 쓰지 않는다

### Phase 2: Team Architecture Design (팀 설계)

0. **단일 패스 vs 루프 판정**: 반복이 필요하면 [Loop Harness Design](#loop-harness-design-루프-하네스-설계)의 4요소를 함께 설계
1. 실행 모드 선택 (위 [결정 순서](#execution-modes))
2. 패턴 선택 (6종 중 택일 또는 복합) + 정확성이 중요하면 검증 보강 패턴 조합
3. 4축 분리 기준 적용

### Phase 3: Agent Definition (에이전트 정의)

**재사용 우선 게이트 (생성 전 필수):** Phase 0 감사 목록과 대조해 판정하고 근거를 한 줄로 남긴다. 에이전트만 추가할 때도 생략하지 않는다.

| 판정 | 조건 | 동작 |
|------|------|------|
| **재사용** | 기존 에이전트/스킬이 역할을 이미 커버 | 신규 생성 금지, 기존 참조 |
| **확장** | 기존과 대부분 겹치나 일부 부족 | 기존 정의 수정·보강 (신규 ❌) |
| **신규** | distinct domain — 기존으로 커버 불가 | 신규 생성 진행 |

> 원칙: **"distinct domain일 때만 신규 생성."** 중복은 트리거 충돌과 유지보수 부채를 만든다. 예외는 도메인을 의도적으로 특화한 경우뿐이다.

재사용할 전문가 역할은 `agents/{name}.md` 파일로 정의하고 `subagent_type: "{name}"`(Agent) / `agentType: "{name}"`(Workflow)으로 부른다. `general-purpose`·`Explore`·`Plan`을 그대로 쓰는 단발 작업에는 파일을 만들지 않는다.

**모델 티어** — 복잡도·작업 기간·자율성·응답 속도로 고르고, 이유를 정의 파일이나 오케스트레이터에 주석으로 남긴다.

| 모델 | 기준 | 대표 업무 |
|------|------|----------|
| **fable** | 스스로 계획하고 여러 단계를 이어 장기간 자율 실행하는 최고 난도 | 에이전트 조율, 장기 실행, 방대한 자료 통합, 막연한 아이디어 구체화 |
| **opus** | 범위는 분명하나 깊은 추론이 필요 | 설계·아키텍처, 코드 생성, 복잡한 분석, 교차 검증 |
| **sonnet** | 절차가 분명하고 속도가 중요 (애매하면 기본값) | 로그 분석, 형식 변환, 정적 검사, 단순 수집, 요약 |

중요한 에이전트라는 이유로 일괄 fable/opus를 지정하지 않는다. 상위 조율자가 fable이어도 하위 작업자는 업무별로 따로 고른다. 상세: [references/model-selection-guide.md](references/model-selection-guide.md)

**정의 파일 규약:**
- 프론트매터: `name`, `description` 필수, 필요 시 `tools`·`model`. 읽기 전용 검토·분석 에이전트는 `tools`에서 Edit/Write를 뺀다. 산출물을 고치는 에이전트에는 Write와 **Edit를 함께** 준다(Edit가 없으면 큰 산출물 수정을 포기하고 우회한다)
- 필수 섹션: flow-scaffolding `templates/team-agent.md` 구조를 따른다(AGT-004 `## Your Role`·AGT-005 `### Step`·AGT-008 `## Boundaries` 등) — 내용상 핵심 역할 · 작업 원칙 · 입력/출력 프로토콜 · 에러 핸들링 · 재호출 지침(이전 결과 파일이 있으면 읽고 피드백 부분만 수정)을 담는다
- 모드 B 에이전트(AGT-021 대상, 모드 A/C는 면제): `## Team Communication Protocol` — `SendMessage` 수신·발신 대상(이름 지정, 브로드캐스트 없음), 공유 작업 목록 사용법, **첫 보고에서 실제 사용 가능한 도구 목록 보고**(`tools`에 적은 도구가 주입되지 않은 사례가 있음)
- QA 에이전트: 검증 스크립트를 실행할 수 있는 유형 지정(`Explore`는 읽기 전용이라 불가), 파일 존재가 아니라 경계면(API 응답 ↔ 프런트 훅) 대조, 모듈 완성마다 즉시 검사 — [references/qa-agent-guide.md](references/qa-agent-guide.md)

생성 실행:
```
/create-flow --team --team-name {team-name}
```
- 각 멤버 agent → `agents/{name}.md` (team-agent 템플릿, Team Communication Protocol 포함)
- 오케스트레이터 → `skills/{team-name}-orchestrator/SKILL.md`
- 팀 훅 (선택) → `hooks/hooks.json` 엔트리

### Phase 4: Skill Writing (스킬 작성)

새 스킬 전에도 재사용 게이트를 적용한다(겹치면 기존 스킬을 연결·확장). 규약:
- `skills/{name}/SKILL.md` < 500줄(SKL-004 기준 5,000토큰 미만), 초과 시 `references/`로 분리. 300줄 넘는 참조 문서에는 목차
- 구조: `scripts/`(반복·결정론 작업 코드) · `references/`(필요 시 읽기) · `assets/`(산출물용 파일)
- Description을 "적극적으로": 하는 일 + 사용 상황 + 비슷하지만 쓰면 안 되는 경우. 이 레포 컴포넌트는 한국어 원문 + 영어 요약·`Use when:` 이중언어(≤1,400자)
- Why-first(규칙보다 이유), 원리로 일반화(사례별 규칙 금지), 지시문 어미 통일, 3회 이상 반복되는 코드는 `scripts/`에 번들
- 새 컴포넌트는 커맨드보다 스킬 형식을 우선한다

상세: [references/skill-writing-guide.md](references/skill-writing-guide.md)

### Phase 5: Integration (오케스트레이터 통합)

오케스트레이터도 스킬이다. 기존 하네스 확장 시 새로 만들지 말고 기존 파일을 고친다(에이전트 추가 → 구성·배정·데이터 순서·description 갱신). 모드별 전체 템플릿: [references/orchestrator-template.md](references/orchestrator-template.md), 예시: [references/team-examples.md](references/team-examples.md)

**데이터 전달:**

| 방법 | 구현 | 모드 | 사용할 때 |
|------|------|------|----------|
| **구조화 반환** | `agent(prompt, {schema})` → 검증된 JSON | A | 다음 단계가 결과를 코드로 처리 (v2 권장 기본) |
| **반환값** | `Agent` 반환 메시지 | C | 메인이 요약을 직접 모음 |
| **메시지** | `SendMessage({to: "<name>"})` | B | 실시간 조율·피드백 |
| **공유 작업 목록** | `TaskCreate`/`TaskUpdate` | B | 진행·의존·동적 배정 |
| **파일** | `_workspace/{phase}_{agent}_{artifact}.{ext}` | 전부 | 대용량·사후 감사 (최종 산출물만 사용자 지정 경로, `_workspace/`는 보존) |

모드 B에서 다음 단계로 넘어갈 때는 완료 보고를 모두 확인하고 **산출물 동결**을 알린 뒤 해시를 기록해 최종 검증에서 다시 대조한다(`SendMessage`로 깨운 에이전트가 이전 산출물을 고칠 수 있다).

**오류 처리:**
- 1회 재시도 후 실패하면 해당 결과 없이 진행하고 최종 보고에 누락을 명시한다. 충돌 데이터는 지우지 말고 출처와 함께 남긴다
- 사용량 한도·인증 만료·권한 거부처럼 **재시도해도 같은 실패는 재시도하지 않는다**. 부분 산출물을 직접 열어 진행 정도를 확인하고 누락을 파일로 기록해 보고한다(한도라면 해제 시각 포함)
- 멈춘 에이전트의 빈 곳은 직접 확인한 사실만 채운다. 에이전트의 판단을 추측으로 채우면 감사 기록을 위조하는 셈이다
- 워크플로의 실패한 `agent()`는 `null`, `parallel()`은 예외를 던지지 않는다 → `.filter(Boolean)` + 누락 수 `log()`
- 지속형 에이전트 무응답 → `SendMessage`로 상태 확인 후 재지시, 그래도 실패하면 같은 유형을 새 이름으로 실행하고 맥락을 프롬프트로 넘긴다

**작업 규모:** 소(작업 <10): 지속형 2~3명 / 워크플로 호출 2~5건 · 중(10~20): 3~5명 / 약 10건 · 대(>20): 감독자 + 작업자 3~5명 / 수십~수백 건(전체 상한 1,000). 기본은 작게, 사용자가 토큰 예산(`+500k` 등)을 주면 `budget.remaining()`으로 조절.

**후속 요청:** description에 `다시 실행`·`재실행`·`수정`·`보완`·`{부분 작업}만 다시`·`이전 결과를 바탕으로` 표현을 넣는다. 오케스트레이터 0단계에서 — `_workspace/` + 부분 수정 요청 → 해당 단계/에이전트만 재실행 / `_workspace/` + 새 입력 → 타임스탬프 디렉터리로 옮긴 뒤 새로 실행 / 없음 → 처음부터 / 직전 `runId`가 있으면 `resumeFromRunId`로 재개(바뀌지 않은 `agent()`는 캐시).

### Phase 6: Registration (등록)

프로젝트 `CLAUDE.md`에 최소 포인터만 등록한다. 에이전트 목록·디렉터리 구조·실행 규칙·변경 이력은 넣지 않는다(새 세션마다 읽히는 비용).

```markdown
## Harness: {Domain}
**Goal:** {핵심 목표 한 줄}
**Trigger:** {domain} 관련 작업 요청 시 `{orchestrator-skill}` 스킬을 사용한다. 단순 질문은 직접 답해도 된다.
```

변경 이력은 git이 원장이다 — 하네스 파일 변경은 Conventional Commits(`feat(harness-{domain}): …`)로 커밋하고, 본문에 **무엇을·왜**(피드백·근거)를 적는다. 추적: `git log -- <하네스 경로>`.

### Phase 7: Validation & Operations (검증·운영)

**검증 (`/verify-flow --target team` 위임):**
- TEAM-* (`## Team Members` 표 구조) · ORC-* (오케스트레이터: 실행 모드 선언, v1 유물 감지, 워크플로 스크립트 함정, 테스트 시나리오) · AGT-* (팀 에이전트: 통신 프로토콜, 모델 티어 근거) → Health Score + Team Assessment
- 호출 조건: should-trigger 10개(말투·명시 수준 다양) + near-miss 10개. 명백히 무관한 요청은 경계를 검증하지 못한다 — 표현은 비슷하지만 다른 스킬이 맞는 요청을 쓴다
- 실행 테스트: 스킬별 실제 요청 2~3개로 with-skill vs baseline 비교(반복 시 A/B 자체를 워크플로로), 정성 평가 + assertion. 문제는 원리 수준으로 고치고 효과가 줄 때까지 반복 — [references/skill-testing-guide.md](references/skill-testing-guide.md)
- 모의 실행: 단계 순서·데이터 경로·입출력 정합·대체 절차 실행 가능성
- 오케스트레이터에 `## 테스트 시나리오`(정상 1 + 오류 1 이상) 기록

**운영·유지보수 (이 스킬이 직접 처리):** 불일치 목록 작성 → 한 번에 한 항목씩 수정 → 즉시 검증 → 커밋(본문에 사유). 호출 조건에 영향이 있으면 트리거 테스트, 변경이 크면 실행 테스트·모의 실행까지.

**진화 (`harness:evolve` 위임):** 실행 결과 회고·피드백 반영은 evolve가 맡는다. 다음 신호가 보이면 evolve를 제안한다 — 같은 종류의 피드백 2회 이상 / 같은 원인의 반복 실패 / 사용자가 오케스트레이터를 우회해 수동 작업 반복.

## Output Checklist

- [ ] 재사용할 사용자 정의 유형은 모두 `agents/`에 파일로 있다 (단발 기본 유형은 제외)
- [ ] 생성 전 재사용 게이트 판정 근거를 남겼고, 이름·역할 충돌이 없다
- [ ] 실행 모드(A/B/C)를 적었고, 혼합 모드면 단계마다 표시했다
- [ ] 모델을 업무 티어로 골라 이유를 주석으로 남겼다 (일괄 고성능 지정 없음)
- [ ] `TeamCreate`·`TeamDelete`·`team_name`·브로드캐스트·실험 플래그가 남지 않았다
- [ ] 워크플로 스크립트: `meta` 리터럴만, `Date.now()`/`Math.random()` 없음, `.filter(Boolean)`, 꼭 필요할 때만 `parallel()`
- [ ] 오케스트레이터 1개에 데이터 전달·오류 처리·테스트 시나리오·후속 요청(재실행/재개) 분기가 있다
- [ ] 산출물이 사용자 언어(또는 기존 하네스 언어)로 쓰였다
- [ ] SKILL.md < 500줄, description에 호출 조건·경계·후속 요청 표현이 있다
- [ ] should-trigger / near-miss로 호출 조건을 검증했다
- [ ] `CLAUDE.md`에는 트리거만, 변경 사유는 커밋 본문에 있다

## Reference Files

- [execution-modes.md](references/execution-modes.md) — 실행 모드 3종 상세, 혼합 모드, v1→v2 전환
- [workflow-recipes.md](references/workflow-recipes.md) — 워크플로 스크립트 스켈레톤과 함정 체크리스트
- [model-selection-guide.md](references/model-selection-guide.md) — 모델 티어 기준과 적용 규칙
- [team-patterns.md](references/team-patterns.md) — 6패턴·품질 패턴 상세, 분리 기준, 에이전트 정의 구조, 재사용 설계
- [orchestrator-template.md](references/orchestrator-template.md) — 모드별(A/B/C) 오케스트레이터 템플릿
- [team-examples.md](references/team-examples.md) — 실전 팀 구성 예시
- [skill-writing-guide.md](references/skill-writing-guide.md) — 스킬 작성 원칙 및 트리거 메커니즘
- [skill-testing-guide.md](references/skill-testing-guide.md) — 이중 평가 프레임워크, A/B 테스트
- [qa-agent-guide.md](references/qa-agent-guide.md) — QA 에이전트 설계, 경계면 검증
- [loop-harness-guide.md](references/loop-harness-guide.md) — 루프 엔진 레시피, Stop훅, 하네스 간 라우팅
