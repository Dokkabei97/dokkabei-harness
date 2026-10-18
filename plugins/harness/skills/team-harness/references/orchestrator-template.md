# Orchestrator Skill Templates (v2)

오케스트레이터는 팀 전체를 조율하는 상위 스킬이다. 실행 모드별 3가지 템플릿과 단계별 모드 조합(혼합 모드)을 제공한다. 모드 정의는 [execution-modes.md](execution-modes.md), 패턴별 권장 모드는 [team-patterns.md](team-patterns.md)를 본다.

- **Template A: 워크플로 조율** — 제어 흐름이 미리 정해진 대규모 분산 실행·반복 검증
- **Template B: 지속형 에이전트 협업** — 에이전트가 대화 맥락을 유지해야 하는 반복 피드백·협상·장기 협업
- **Template C: 서브에이전트 위임** — 독립 작업을 한 번씩 병렬로 맡기고 결과만 수집
- **Hybrid: 혼합 모드** — 단계마다 알맞은 모드를 조합

모든 템플릿은 Phase 0에서 기존 작업을 확인하고, `_workspace/` 파일 규칙·오류 처리·테스트 시나리오를 반드시 포함한다.

---

## 목차

1. [공통 골격 (모든 템플릿)](#1-공통-골격-모든-템플릿)
2. [Template A: Workflow (워크플로 조율)](#2-template-a-workflow-워크플로-조율)
3. [Template B: Persistent Agents (지속형 에이전트 협업)](#3-template-b-persistent-agents-지속형-에이전트-협업)
4. [Template C: Sub-agent Delegation (서브에이전트 위임)](#4-template-c-sub-agent-delegation-서브에이전트-위임)
5. [Hybrid Mode (혼합 모드)](#5-hybrid-mode-혼합-모드)
6. [Description Keywords (후속 작업 지원)](#6-description-keywords-후속-작업-지원)
7. [Hook Integration — TaskCompleted 훅 등록 예시](#7-hook-integration--taskcompleted-훅-등록-예시)
8. [Registration (등록과 변경 이력)](#8-registration-등록과-변경-이력)
9. [Writing Principles (작성 원칙)](#9-writing-principles-작성-원칙)

---

## 1. 공통 골격 (모든 템플릿)

세 템플릿은 아래 골격을 공유한다. `## Team Members`·`## Orchestration Phases`는 하위 오케스트레이터(mvp·feature-loop·wiki-ops·scaleup)도 쓰는 헤딩이고 `/verify-flow` 규칙이 그대로 참조하므로 바꾸지 않는다. 실행 모드는 헤딩 대신 `**실행 모드:**` 줄로 써도 ORC-011이 동등하게 인정한다.

| 헤딩 | 역할 |
|------|------|
| `## 실행 모드: {A/B/C/혼합}` + `**Pattern:**` | 문서 맨 위에서 모드와 패턴(`pipeline`·`fan-out-fan-in`·`expert-pool`·`producer-reviewer`·`supervisor`·`hierarchical`)을 밝힌다 |
| `## Team Members` | 팀 정의(roster) 표 — 팀 객체가 없는 v2에서 **이 표가 곧 팀 정의**다 |
| `## Orchestration Phases` | Phase 0~N 절차(`## Workflow Phases`도 동등 인정). Phase마다 담당·입력·산출물 명시 |
| `## Error Handling` | 상황별 대응 표 |
| `## Test Scenarios` | 정상 흐름 1 + 오류 흐름 1 이상 |

### Frontmatter

```yaml
---
name: {domain}-orchestrator
description: |
  {domain} 오케스트레이터. {초기 키워드}, {후속 작업 키워드}.
  재실행/업데이트/수정/보완, "{도메인}의 {부분}만 다시",
  "이전 결과 기반으로", "결과 개선" 시에도 사용.
---
```

### `## Team Members` 표

| Name | Agent | Role | Skills | Output |
|------|-------|------|--------|--------|
| {teammate-1} | `agents/{teammate-1}.md` 또는 `general-purpose` | member — {역할} | {skill} | `_workspace/{phase}_{teammate-1}_{artifact}.md` |
| {teammate-2} | `agents/{teammate-2}.md` | checker — {역할} | {skill} | `_workspace/{phase}_{teammate-2}_{artifact}.md` |

- **Name**은 B 모드에서 `Agent(name:)`·`SendMessage({to: "<name>"})`의 주소다 — 표 안에서 유일해야 한다. A 모드는 `agent()`의 `label`, C 모드는 호출 식별명을 적는다.
- **Agent**는 에이전트 파일(`agents/{name}.md` / `.claude/agents/{name}.md`) 또는 기본 제공 유형. A 모드의 `agentType`, B·C 모드의 `subagent_type` 값이다.
- **Role**은 `leader` / `member`(maker) / `specialist` / `checker`(reviewer) 키워드로 시작하고 뒤에 설명을 붙인다.
- 기존 오케스트레이터의 `ID`·`에이전트 파일`·`역할`·`산출물` 열 이름도 동등하게 인정된다(`/verify-flow` TEAM 규칙).
- 모델은 각 에이전트 정의의 `model:`(A 모드는 `opts.model`)에 업무 티어 + 이유 주석으로 지정한다([model-selection-guide.md](model-selection-guide.md)). 전원 일괄 지정 금지.

### Phase 0: 기존 작업 확인 (Context Check)

1. `_workspace/` 존재 여부 확인
   - 없음 → 초기 실행. Phase 1로 진행
   - 있음 + 부분 수정 요청 → 부분 재실행. 해당 에이전트만 재호출하고 수정 대상만 덮어쓴다
   - 있음 + 새 입력 → 새 실행. 기존 `_workspace/`를 `_workspace_{YYYYMMDD_HHMMSS}/`로 이동한 뒤 Phase 1
2. 부분 재실행 시 이전 산출물 경로를 에이전트 프롬프트에 포함해 기존 결과를 읽고 피드백을 반영하게 한다.
3. (A 모드) 직전 실행의 `runId`가 `_workspace/run_meta.json`에 있으면 바뀐 단계만 고쳐 `resumeFromRunId`로 재개한다.

---

## 2. Template A: Workflow (워크플로 조율)

```markdown
---
name: {domain}-orchestrator
description: "{도메인} 워크플로를 조율한다. 사용자가 {초기 실행 키워드} 중 하나로 요청하면 사용하며, {도메인} 결과 수정, 부분 재실행, 업데이트, 보완, 다시 실행, 이전 결과 개선 같은 후속 작업에도 사용한다."
---

# {Domain} 오케스트레이터

## 실행 모드: A 워크플로 조율

**Pattern:** fan-out-fan-in

이 스킬은 Workflow 도구로 제어 흐름이 미리 정해진 작업을 조율한다. 사용자가 이 스킬을 불러오면
Workflow 사용에 동의한 것으로 본다. 기본 에이전트 수는 {N}명으로 제한한다. 사용자가
"철저히", "전수", "모두"를 요청한 경우에만 에이전트 수를 늘린다.

## Team Members

| Name | Agent (`agentType`) | Role | Skills | Output (`schema` 요약) |
|------|------------------|------|--------|---------------------|
| collect | {collector — 커스텀 또는 기본} | member — 수집 maker (`opts.model: 'sonnet'` 반복 수집) | {skill} | {findings: [...]} |
| verify | {verifier — 커스텀 또는 기본} | checker — 적대적 검증 (`opts.model: 'opus'` 교차 검증) | {skill} | {status, reason} |

## Orchestration Phases

### Phase 0: 기존 작업 확인
공통 골격의 Phase 0. 새로 실행하면 새 `runId`를 `_workspace/run_meta.json`에 기록한다.

### Phase 1: 작업 목록 확정 (메인 에이전트 직접 수행)
워크플로 시작 전에 {파일 목록 / 조사 축 / 검토 대상}을 간단히 살펴 배열로 정리하고 `args`로 전달한다.

### Phase 2: 워크플로 실행
Workflow 도구에 스크립트를 전달한다(예시: team-harness `references/workflow-recipes.md`).
- `meta`: `name` '{domain}-run', `phases` [{수집}, {검증}, {종합}]
- 수집(collect): pipeline(args.items, item => agent(..., {label: 'collect', schema: COLLECT}))
- 검증(verify): 찾은 항목마다 적대적 검증 → .filter(Boolean) → 통과 항목만 다음 단계로
- 종합: 구조화 결과를 return

호출 후 완료 알림을 기다린다. 알림 전에 결과를 단정하지 않는다.

### Phase 3: 결과 정리 및 보고
1. 워크플로 반환값을 받는다.
2. 제외·누락 항목이 있으면 보고서에 반드시 밝힌다.
3. 최종 산출물을 `{output-path}/{filename}`에 만든다.
4. 중간 산출물과 `run_meta.json`은 `_workspace/`에 보존한다.

## Error Handling

| 상황 | 대응 |
|------|------|
| 개별 `agent()` 실패(`null`) | `.filter(Boolean)`으로 제외, 제외 수를 `log()`로 기록, 보고서에 누락 명시 |
| 워크플로 전체 실패 | `journal`에서 실제 반환값 확인 → 실패 단계만 수정 → `resumeFromRunId`로 재개 |
| 재시도 무의미한 실패(사용량 한도·인증 만료·권한 거부) | 원인이 풀리기 전엔 재시도·재개하지 않는다. `journal`과 부분 산출물로 실제 진행 범위를 확인해 누락 내용을 `_workspace/`에 기록하고 사용자에게 보고(한도면 해제 시각 포함). 메인은 직접 확인한 사실만 반영하고 에이전트의 판단은 추측해 채우지 않는다 |
| 결과가 비어 있음 | 성공으로 오판하지 않는다. `journal`에서 각 에이전트의 실제 반환값 확인 |
| 데이터 충돌 | 삭제하지 않고 출처와 함께 병기 |

## Test Scenarios

### 정상 흐름
1. 사용자가 {입력} 제공 → Phase 1에서 항목 {M}건 확정
2. 워크플로가 {M}건 수집, {K}건 검증 통과 → 결과 정리
3. 예상 결과: `{output-path}/{filename}` 생성, `run_meta.json` 기록

### 오류 흐름
1. 수집 단계에서 2건이 `null` 반환
2. `.filter(Boolean)`으로 제외, `log()`로 "2건 제외" 고지
3. 최종 보고서에 "{항목명} 2건 수집 실패" 명시
```

---

## 3. Template B: Persistent Agents (지속형 에이전트 협업)

```markdown
---
name: {domain}-orchestrator
description: "{도메인} 에이전트의 협업을 조율한다. 사용자가 {초기 실행 키워드} 중 하나로 요청하면 사용하며, 수정, 부분 재실행, 업데이트, 보완, 다시 실행, 이전 결과 개선 같은 후속 작업에도 사용한다."
---

# {Domain} 오케스트레이터

## 실행 모드: B 지속형 에이전트 협업

**Pattern:** producer-reviewer

명시적인 팀 객체를 만들지 않는다. 세션에서 이름(`name`)을 붙여 실행한 에이전트는 자동으로
구성되는 하나의 협업 그룹에 속한다. 리더는 메인 에이전트다.

## Team Members

| Name | Agent | Role | Skills | Output |
|------|-------|------|--------|--------|
| {teammate-1} | `agents/{teammate-1}.md` | member — {역할} | {skill} | `_workspace/{phase}_{teammate-1}_{artifact}.md` |
| {teammate-2} | `agents/{teammate-2}.md` | checker — {역할} | {skill} | `_workspace/{phase}_{teammate-2}_{artifact}.md` |

<!-- 모델은 각 에이전트 정의의 model:에 업무 티어 + 이유 주석 (예: teammate-1 opus — 설계 판단 / teammate-2 sonnet — 정형 검토) -->

## Orchestration Phases

### Phase 0: 기존 작업 확인
공통 골격의 Phase 0.

### Phase 1: 준비
1. 사용자 입력을 분석해 {무엇을 파악하는지} 확인
2. `_workspace/` 생성, 입력을 `_workspace/00_input/`에 저장

### Phase 2: 에이전트 실행 및 작업 등록
1. 한 메시지에서 에이전트를 병렬 실행한다. `name`은 필수(SendMessage 주소).
   - Agent(name: "{teammate-1}", subagent_type: "{type}", prompt: "{역할 + 작업 지시 + 산출 경로}")
   - Agent(name: "{teammate-2}", subagent_type: "{type}", prompt: "...")
2. 각 에이전트의 첫 보고에서 실제 사용 가능 도구 목록을 확인한다. 빠진 도구(예: TaskUpdate)는 리더가 대신 처리한다.
3. 공유 작업 목록 등록:
   - TaskCreate({title: "{작업1}", assignee: "{teammate-1}"})
   - TaskCreate({title: "{작업3}", depends_on: [작업1]})
   > 팀원당 3~6개 작업이 적정. 의존 관계는 `depends_on`으로 명시.

### Phase 3: 협업 조율
- 완료·대기 알림을 받으며 진행한다. 전체 진행은 TaskList로 확인한다.
- SendMessage({to: "{teammate-2}"}, "{teammate-1}의 _workspace/01_... 초안을 검토하고 고칠 부분을 알려라")로
  검토를 요청하고, 답변은 {teammate-1}에게 전달해 수정하게 한다. 맥락이 유지되므로
  "아까 그 초안의 2절만"처럼 범위를 좁혀 지시할 수 있다.
- 팀원 간 논의가 필요하면 필요한 상대에게만 이름으로 보낸다(전체 전송 없음). 산출물은 항상 파일로 남긴다.

**팀원 간 통신 규칙:**
- {teammate-1} → {teammate-2}: {어떤 정보}를 SendMessage로 전달
- {teammate-2}: 완료 시 결과를 파일로 저장하고 리더에게 알림
- 다른 팀원의 결과가 필요하면 SendMessage로 요청

### Phase 4: 산출물 동결
이름 있는 에이전트는 완료 보고 뒤에도 메시지를 받는다. 뒤늦은 질문에 답하다 이미 넘긴 산출물을
고치면 다음 단계가 바뀌기 전 내용을 읽게 된다. 교차 확인 메시지는 막지 않고, 단계 경계마다 동결한다.
1. TaskList와 완료 알림으로 직전 단계 담당 전원의 완료를 확인
2. 해당 팀원에게 SendMessage로 동결 고지: "이후 수정은 기존 파일이 아니라
   `{phase}_{teammate}_{artifact}_v2.md` 새 파일로 쓰고 리더에게 알려라"
3. 해시 기록: `shasum _workspace/{phase}_* > _workspace/freeze_{phase}.sha`
4. 다음 단계 에이전트 프롬프트에 산출물 경로와 해시 파일 경로를 함께 전달

### Phase 5: 통합
1. TaskList로 전체 완료 확인
2. Read로 산출물 수집 → {통합/검증 로직}
3. 최종 산출 직전 `shasum -c _workspace/freeze_{phase}.sha`로 동결 산출물 불변 확인.
   불일치·새 버전 파일이 있으면 변경 내용을 보고 해당 단계 재실행 여부를 정한다
4. 최종 산출물 `{output-path}/{filename}` 생성

### Phase 6: 마무리
1. `_workspace/` 보존 (사후 검증·감사 추적)
2. 결과 요약 보고. 팀 해체 절차는 없다 — 에이전트는 작업이 끝나면 자연 종료하며, 필요하면 TaskStop으로 중지한다.

## Error Handling

| 상황 | 대응 |
|------|------|
| 팀원 무응답·중지 | SendMessage로 상태 확인 후 재지시. 재실패 시 같은 유형을 새 이름으로 실행하고 작업 맥락을 프롬프트로 전달 |
| 중지 원인이 사용량 한도·인증 만료·권한 거부 | 재지시·대체 실행하지 않는다. 부분 산출물로 실제 진행 범위를 확인해 누락을 `_workspace/`에 기록하고 보고(한도면 해제 시각 포함). 에이전트의 판단은 추측해 채우지 않는다 |
| 과반 실패 | 사용자에게 알리고 진행 여부 확인 |
| 타임아웃 | 받은 결과로 진행, 미완료 영역을 보고서에 명시 |
| 데이터 충돌 | 삭제하지 않고 출처와 함께 병기 |
| 작업 상태 지연 | TaskList로 확인 후 리더가 TaskUpdate로 직접 갱신 |

## Test Scenarios

### 정상 흐름
1. 사용자가 {입력} 제공 → Phase 2에서 에이전트 {N}명 실행, 작업 {M}건 등록
2. Phase 3에서 피드백 {K}회 교환 → Phase 4 동결 → Phase 5 통합
3. 예상 결과: `{output-path}/{filename}` 생성

### 오류 흐름
1. Phase 3에서 {teammate-2} 무응답
2. SendMessage로 상태 확인 후 재지시 → 재실패 시 "{teammate-2}b"로 대체 실행, 기존 산출물 경로 전달
3. 최종 보고서에 "{teammate-2} 영역 일부 재작업" 명시
```

---

## 4. Template C: Sub-agent Delegation (서브에이전트 위임)

```markdown
---
name: {domain}-orchestrator
description: "{도메인}의 독립 작업을 서브에이전트에 위임한다. 사용자가 {초기 실행 키워드} 중 하나로 요청하면 사용하며, 결과 수정, 부분 재실행, 업데이트, 보완, 다시 실행, 이전 결과 개선 같은 후속 작업에도 사용한다."
---

# {Domain} 오케스트레이터

## 실행 모드: C 서브에이전트 위임

**Pattern:** expert-pool

## Team Members

| Name | Agent (`subagent_type`) | Role | Skills | Output |
|------|----------------------|------|--------|--------|
| {agent-1} | `agents/{agent-1}.md` 또는 기본 유형 | specialist — {역할}, 입력 {소스} | {skill} | `_workspace/{phase}_{agent-1}_{artifact}.md` |
| {agent-2} | `agents/{agent-2}.md` 또는 기본 유형 | checker — {역할}, 입력 {소스} | {skill} | `_workspace/{phase}_{agent-2}_{artifact}.md` |

<!-- 모델은 에이전트 정의 model: 또는 Agent 호출의 model 매개변수에 업무 티어 + 이유 (예: agent-1 sonnet — 단발 수집 / agent-2 opus — 독립 검증) -->

## Orchestration Phases

### Phase 0: 기존 작업 확인
공통 골격의 Phase 0.

### Phase 1: 준비
입력 분석, `_workspace/` 생성.

### Phase 2: 병렬 실행
한 메시지에서 Agent 도구를 N번 동시 호출한다(기본 백그라운드). `name` 없는 단발 호출이다.
- Agent(subagent_type: "{agent-1}", prompt: "{작업 지시 + 산출 경로}")
- Agent(subagent_type: "{agent-2}", prompt: "...")

완료 알림을 기다리며, 메인은 이미 맡긴 검색을 다시 수행하지 않는다.

### Phase 3: 통합
반환값 + Read로 파일 산출물 수집 → 통합 → 최종 산출물.

### Phase 4: 마무리
`_workspace/` 보존, 결과 요약 보고.

## Error Handling
- 에이전트 1개 실패: 1회 재시도, 재실패 시 누락 명시 후 진행
- 사용량 한도·인증 만료·권한 거부: 재시도하지 않는다. 부분 산출물로 실제 진행 범위 확인 → 누락을 `_workspace/`에 기록 → 보고(한도면 해제 시각 포함). 에이전트의 판단은 추측해 채우지 않는다
- 과반 실패: 사용자에게 알리고 진행 여부 확인
- 타임아웃: 부분 결과 사용

## Test Scenarios
- 정상: {N}개 병렬 호출 → 전원 반환 → `{output-path}/{filename}` 생성
- 오류: 1개 실패 → 1회 재시도 실패 → 보고서에 "{agent} 영역 누락" 명시
```

---

## 5. Hybrid Mode (혼합 모드)

단계마다 알맞은 모드를 쓴다. 각 Phase 맨 위에 `**실행 모드:**`를 표기한다.

```markdown
## 실행 모드: 혼합

| Phase | 실행 모드 | 이유 |
|-------|----------|------|
| Phase 1 (사전 확인) | 메인 직접 또는 C 서브에이전트 | 작업 목록 확정 |
| Phase 2 (대량 수집·검증) | A 워크플로 조율 | 미리 정한 목록을 분산 처리하고 적대적 검증 |
| Phase 3 (합의·통합) | B 지속형 에이전트 협업 | 상충 데이터를 논의해 합의 |
| Phase 4 (독립 검증) | C 서브에이전트 위임 | QA 1명이 객관 검증 |

### Phase 3: 합의 기반 통합
**실행 모드:** B 지속형 에이전트 협업

1. Agent(name: "editor"), Agent(name: "fact-checker"), Agent(name: "synthesizer") 병렬 실행 —
   모두 Phase 2가 저장한 `_workspace/02_*` 파일을 Read
2. TaskCreate로 작업 분배, 상충 데이터는 SendMessage로 논의해 파일 기반 합의안 도출
3. `_workspace/03_integrated.md` 생성 후 동결(Template B Phase 4)
```

### Mode Transition Rules (모드 전환 규칙)
- **A → B**: 워크플로 반환 구조화 데이터를 `_workspace/`에 저장하고, 지속형 에이전트 프롬프트에 파일 경로를 적는다.
- **B → A**: 팀 산출물을 동결(Template B Phase 4)한 뒤 파일 경로 목록을 `args`로 스크립트에 넣는다.
- **C → B / C → A**: 서브에이전트의 파일 산출물 경로를 다음 단계 프롬프트 또는 `args`로 전달한다.
- 모드가 바뀌는 지점마다 데이터 전달 경로를 적어 이전 단계 결과를 잃지 않게 한다. 팀 해체·재생성 절차는 없다 — 다음 단계에 필요한 에이전트를 새 이름으로 실행하면 된다.

---

## 6. Description Keywords (후속 작업 지원)

오케스트레이터 description에 반드시 포함:
- 재실행/다시 실행/업데이트/수정/보완
- "{도메인}의 {부분}만 다시"
- "이전 결과 기반으로", "결과 개선"
- 도메인 일상 요청(예: 출시 전략 하네스라면 "런치", "홍보", "트렌딩")

> 후속 키워드가 없으면 첫 실행 후 하네스가 죽은 코드가 된다. 이 저장소의 컴포넌트 description은 이중언어(한국어 원문 → 영어 요약 + `Use when: …`, 총 ≤ 1,400자)다.

---

## 7. Hook Integration — TaskCompleted 훅 등록 예시

공유 작업 목록(Template B의 `TaskCreate`/`TaskUpdate`)의 라이프사이클에 훅을 연결해 관찰성과 완료 게이트를 확보한다. `TaskCompleted`·`TeammateIdle`은 유효한 훅 이벤트다(`/verify-flow` 훅 이벤트 목록).

`hooks/hooks.json` (플러그인) — matcher 그룹에는 `matcher`/`hooks`만 둔다. `description` 같은 스키마 외 키는 세션마다 경고만 내고 무시되므로, 설명은 스크립트 헤더 주석에 적는다. 두 이벤트는 도구 이벤트가 아니므로 도구명 matcher를 생략한다.

```json
{
  "hooks": {
    "TaskCompleted": [
      {
        "hooks": [
          { "type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/hooks/task-completed-gate.sh", "timeout": 10 }
        ]
      }
    ],
    "TeammateIdle": [
      {
        "hooks": [
          { "type": "command", "command": "echo 'Teammate idle: check progress' >&2" }
        ]
      }
    ]
  }
}
```

`hooks/task-completed-gate.sh` — verified 마커 없는 완료 주장 차단 스케치:

```bash
#!/usr/bin/env bash
# TaskCompleted 게이트: 작업 제목의 T-xx ID에 대응하는 .planning/verified/{id} 마커가 없으면 완료를 차단한다.
# 실험용 — stdin JSON 필드명과 exit 2의 차단 의미는 실측(스파이크)으로 확인한 뒤 프로덕션 루프에 연결한다.
set -euo pipefail
input=$(cat)
subject=$(printf '%s' "$input" | jq -r '.task_subject // .task_id // empty')
id=$(printf '%s' "$subject" | grep -oE 'T-[0-9]{2}' | head -1 || true)
[ -z "$id" ] && exit 0                       # 루프 task가 아니면 통과
if [ ! -f ".planning/verified/$id" ]; then
  echo "verified 마커 없음: $id — checker 반증 통과 후 완료 처리하라" >&2
  exit 2                                     # 차단 (exit 1은 비차단 경고)
fi
exit 0
```

- 훅을 바꾸면 `tests/hooks/*.bats` 회귀 테스트를 함께 갱신한다. hooks.json은 `jq .`로 검증한다.
- feature-loop worktree 레인 stage③(병렬 레인 완료 게이트)이 이 예시를 참조한다 — 선행 조건은 "마커 없는 완료 주장이 훅에 100% 차단됨"의 별도 스파이크 확인이다.
- `TeammateIdle`이 B 모드 이름 있는 에이전트에서 발화하는지는 환경별로 실측한다. 관찰용으로만 쓰고 게이트로 의존하지 않는다.

---

## 8. Registration (등록과 변경 이력)

- 프로젝트 `CLAUDE.md`에는 하네스 **호출 조건(트리거)**만 등록한다(`## Harness: {Domain}` 항목 — 언제 이 오케스트레이터를 쓰는지). 변경 이력 표는 두지 않는다.
- 변경 이력의 원장은 **git**이다. 오케스트레이터·에이전트를 고칠 때마다 Conventional Commits로 커밋하고 본문에 "왜 바꿨는지"를 남긴다. 이후 진화·퇴행 분석은 `git log`와 커밋 본문으로 수행한다.

---

## 9. Writing Principles (작성 원칙)

1. **실행 모드를 먼저 명시** — 문서 맨 위에 A/B/C/혼합. 혼합이면 Phase별 모드 표 필수.
2. **A 모드는 스크립트 구조를 구체적으로** — `phases`, `schema` 요약, `args`에 넣을 항목 명시. Workflow 사용은 사용자 동의 전제, 기본 규모는 작게.
3. **B 모드는 `name`·SendMessage·TaskCreate 사용법을 구체적으로** — 실행할 에이전트 목록, 이름 지정 통신 규칙, 작업 의존 관계, 단계 경계의 산출물 동결 절차.
4. **C 모드는 Agent 매개변수를 빠짐없이** — `name` 없는 단발 실행임을 밝히고 `subagent_type`, `prompt`, 출력 경로, 필요 시 `model`을 명시.
5. **파일 경로는 명확하게** — `_workspace/` 기준, `{phase}_{agent}_{artifact}.{ext}` 규칙.
6. **Phase 간 의존성 명시** — 모드 전환 지점의 데이터 전달을 특히 자세히.
7. **에러 핸들링은 현실적으로** — "모든 것이 성공한다" 가정 금지. 재시도 무의미한 실패를 구분.
8. **테스트 시나리오 필수** — 정상 1 + 오류 1 이상.
9. **v1 유물 금지** — 팀 생성·해체 도구, 팀 이름 매개변수, 전체 전송, 실험 플래그, 전원 고성능 모델 강제를 참조했다면 잘못 작성한 것이다(감지 규칙: [execution-modes.md](execution-modes.md)의 v1→v2 전환 절).
