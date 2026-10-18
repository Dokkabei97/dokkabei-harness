# Team Examples — 프로덕션 팀 구성 예시 (v2)

각 예시는 작업에 맞는 실행 모드를 고르는 기준과 v2 문법의 기본 형태를 보여 준다. 모드 정의는 [execution-modes.md](execution-modes.md), 워크플로 스크립트 작성법은 [workflow-recipes.md](workflow-recipes.md), 오케스트레이터 골격은 [orchestrator-template.md](orchestrator-template.md)에서 확인한다.

| # | 예시 | 패턴 | 실행 모드 |
|---|------|------|----------|
| 1 | 종합 리서치 팀 | Fan-out/Fan-in + 적대적 검증 | A 워크플로 조율 |
| 2 | SF 소설 집필 팀 | Pipeline + Producer-Reviewer | 혼합(B 중심) |
| 3 | 종합 코드 리뷰 | Fan-out/Fan-in + 적대적 검증 | A 워크플로 조율 |
| 4 | 대규모 코드 마이그레이션 | Fan-out 또는 Supervisor | A 또는 B |
| 5 | 웹툰 제작 | Producer-Reviewer | 혼합(B 생성자 + C 검토자) |

---

## Example 1: 리서치 팀 (Fan-out/Fan-in, A 워크플로 조율)

**선택 이유:** 조사할 관점을 미리 나열할 수 있고, 주장마다 검증하는 절차를 코드로 정할 수 있다.

```
[메인] 사전 조사: 조사 관점 확정(공식 자료·언론·커뮤니티·배경)
     → Workflow(script, args: {axes, topic, ws})
         phase '조사': pipeline(axes, axis => agent(..., {schema: FINDINGS}))
         phase '검증': 주장별 적대적 검증 에이전트 실행 → 과반이 confirmed로 판정한 주장만 통과
         phase '종합': 누락 검토자 1명 실행 → 빠진 관점이 있으면 추가 조사
     → 메인이 반환된 구조화 결과로 종합 보고서 작성
```

### Team Members
| Name | Agent (`agentType`) | Role | 모델(이유) | Output (`schema`) |
|------|------------------|------|-----------|------------------|
| research-{axis} | `agents/researcher.md` | member — 축별 조사: 공식 문서/블로그 · 미디어/투자 · 커뮤니티/SNS · 배경/경쟁/학술 (`args.axes` 1회씩) | sonnet — 정형 수집 | `FINDINGS` → `_workspace/01_research_{axis}.json` |
| fact-check | `agents/fact-checker.md` | checker — 주장별 반박 검증 | opus — 교차 검증 | `VERDICT` |
| (메인) | — | leader — 통합 보고서 | — | 종합보고서.md |

조사 원칙과 구조화 출력 형식은 `agents/researcher.md`에, 반박을 우선하는 검증 원칙은 `agents/fact-checker.md`에 정의한다. 축마다 별도 에이전트 파일을 만들지 않고 한 유형을 축 프롬프트로 재사용한다. 상충 정보는 한쪽을 임의로 버리지 않고 반환 스키마에 출처와 함께 담는다.

> 조사자끼리 발견을 실시간으로 공유·반박해야 하는 2~4명 규모라면 B 지속형으로 바꿀 수 있다. 그때도 전체 전송 없이 리더가 필요한 상대에게만 이름으로 중계한다.

---

## Example 2: SF 소설 집필 팀 (Pipeline + Producer-Reviewer, 혼합 — B 중심)

**선택 이유:** 세계관·인물·줄거리가 어긋나지 않도록 실시간 조정이 필요하므로 각 전문가가 대화 맥락을 기억해야 한다(B). 검토자는 서로 독립된 관점으로 결과만 전달하면 되므로 서브에이전트로 충분하다(C).

```
Phase 1 (B 지속형): Agent(name: "worldbuilder") + Agent(name: "character-designer")
               + Agent(name: "plot-architect") 병렬 실행
               → TaskCreate(세계관·인물·줄거리, 서로의 의존 관계 명시)
               → 리더가 중계: worldbuilder가 사회 구조 확정
                 → SendMessage({to: "character-designer"})로 전달
                 → 인물의 직업군이 세계관과 충돌하면 SendMessage({to: "worldbuilder"})로 조정 요청
                 맥락이 남아 있으므로 "아까 정한 계급 구조에서 상인 계층만 수정"처럼 일부만 지시 가능
               → 단계 경계에서 산출물 동결
Phase 2 (B 지속형): Agent(name: "prose-stylist") → _workspace/의 산출물 3개를 Read하여 집필
               → _workspace/02_prose_draft.md
Phase 3 (C 병렬): science-consultant + continuity-manager가 각각 독립 검토
Phase 4 (B 지속형): SendMessage({to: "prose-stylist"})로 검토 결과 반영 지시
```

수정 요청을 다시 보낼 가능성이 있는 에이전트(prose-stylist)에는 **처음 실행할 때부터** `name`을 붙인다. `name` 없이 한 번만 호출한 에이전트에는 SendMessage를 보낼 수 없고 맥락도 이어지지 않는다.

### Team Members
| Name | Agent | Role | Skills | 모델(이유) | Output |
|------|-------|------|--------|-----------|--------|
| worldbuilder | `agents/worldbuilder.md` | member — 세계관 구축 (B) | world-setting | opus — 설정 일관성 추론 | `_workspace/01_worldbuilder_setting.md` |
| character-designer | `agents/character-designer.md` | member — 캐릭터 설계 (B) | character-profile | sonnet — 세계관 제약 안의 프로필 작성, 범위가 명확 | `_workspace/01_character-designer_profiles.md` |
| plot-architect | `agents/plot-architect.md` | member — 플롯 구조 (B) | outline | fable — 전체 서사를 계획하고 여러 단계에 걸쳐 조정 | `_workspace/01_plot-architect_outline.md` |
| prose-stylist | `agents/prose-stylist.md` | member — 집필/수정 (B) | write-scene, review-chapter | opus — 창작 | `_workspace/02_prose_draft.md` |
| science-consultant | `agents/science-consultant.md` | checker — 과학 검증 (C) | science-check | opus — 교차 검증 | `_workspace/03_science-consultant_review.md` |
| continuity-manager | `agents/continuity-manager.md` | checker — 일관성 검증 (C) | consistency-check | sonnet — 대조 위주 정형 검사 | `_workspace/03_continuity-manager_review.md` |

### Agent File Example: `agents/worldbuilder.md`
```markdown
---
name: worldbuilder
description: "SF 소설의 세계관을 구축하는 전문가. 물리 법칙, 사회 구조, 기술 수준, 역사를 설계한다."
tools: ["Read", "Write", "Edit", "WebSearch"]   # 산출물을 고치므로 Edit 포함
model: opus                                    # 설정 간 모순 추론 — 깊은 창작 판단
team: novel-team          # 저장소 관례 필드 — 이 에이전트를 `## Team Members` 표에 올린 오케스트레이터의 팀 식별자
teamRole: member
reportsTo: orchestrator
---

# Worldbuilder — SF 세계관 설계 전문가

당신은 SF 소설의 세계관 설계 전문가다.

## 핵심 역할 (Core Responsibilities)
1. 물리 법칙과 기술 수준 정의
2. 사회 구조·정치 체계·경제 시스템 설계
3. 역사적 맥락과 현재 갈등 구조 수립

## 작업 원칙 (Work Principles)
- 내적 일관성 최우선 — 설정 간 모순이 생기면 이야기 전체가 무너진다
- 이야기에 봉사하는 세계관 — 플롯을 방해하는 과도한 설정은 지양

## 입력/출력 프로토콜 (I/O Protocol)
- 입력: 사용자의 세계관 컨셉 (`_workspace/00_input/`)
- 출력: `_workspace/01_worldbuilder_setting.md` (섹션: 물리/사회/기술/역사/장소)

## Team Communication Protocol
- 첫 보고: 실제 사용 가능 도구 목록을 리더에게 알린다
- SendMessage 대상: character-designer(사회 구조·계급·직업군), plot-architect(주요 갈등·위기 요소)
- 수신: science-consultant 검토 결과(리더 경유) → 설정 수정
- 세계관 변경 시 영향받는 팀원에게만 이름으로 각각 알린다(전체 전송 없음)
- 동결 이후 수정은 `_v2` 새 파일로 쓰고 리더에게 알린다

## 에러 핸들링 (Error Handling)
- 컨셉이 모호하면 3가지 방향을 제안하고 선택 요청
- 과학적 오류 지적 시 대안을 함께 제시
```

---

## Example 3: 코드 리뷰 팀 (Fan-out/Fan-in + 적대적 검증, A 워크플로 조율)

**선택 이유:** 보안·성능·구조·테스트처럼 검토 관점을 미리 정할 수 있고, 찾은 항목을 각각 다시 검증하는 절차도 코드로 표현할 수 있다.

```javascript
// 관점별 검토 → 찾은 항목마다 적대적 검증
// 전체 검토를 기다리지 않는다. 보안 검토가 끝나면 성능 검토가 진행 중이어도
// 보안 영역에서 찾은 문제를 바로 검증한다.
const FINDINGS = { type: 'object', required: ['findings'], properties: {
  findings: { type: 'array', items: { type: 'object',
    required: ['title', 'file', 'evidence'], properties: {
      title: { type: 'string' }, file: { type: 'string' }, evidence: { type: 'string' } } } } } }
const VERDICT = { type: 'object', required: ['status', 'reason'], properties: {
  status: { type: 'string', enum: ['confirmed', 'refuted', 'uncertain'] },
  reason: { type: 'string' } } }
const results = await pipeline(
  [
    { key: 'security', prompt: '보안 관점에서 검토하라.' },
    { key: 'perf', prompt: '성능 관점에서 검토하라.' },
    { key: 'arch', prompt: '구조 관점에서 검토하라.' },
    { key: 'test', prompt: '테스트 관점에서 검토하라.' },
  ],
  d => agent(d.prompt, { phase: '검토', schema: FINDINGS }),
  r => parallel((r?.findings ?? []).map(f => () =>
    agent(`다음 발견을 검증하라. 근거가 충분하면 confirmed, 명백히 반박되면 refuted, 판단하기 어려우면 uncertain으로 판정하라: ${JSON.stringify(f)}`,
      { phase: '검증', schema: VERDICT })
      .then(verdict => ({ ...f, verdict }))))
)
const confirmed = results.flat().filter(Boolean)
  .filter(f => f.verdict?.status === 'confirmed')
```

### 교차 영역 이슈 (Cross-domain Findings)
리뷰의 가치는 영역을 넘는 이슈를 잡는 데 있다:
```
security → performance  ("SQL 주입 가능, 성능 측면도 확인 필요")
performance → test      ("N+1 쿼리 발견, 관련 테스트 있나?")
test → security         ("인증 모듈 테스트 없음, 보안 우선순위?")
```
- 발견 한 건의 근거만으로 검증할 수 있으면 위 스크립트처럼 근거를 프롬프트에 담아 곧바로 검증한다.
- 다른 관점의 발견과 **비교**해야 하면 전체 검토 결과를 모은 뒤 `parallel()` 동기화 장벽을 두고 교차 검증 단계를 추가한다.
- 설계 방향을 두고 실시간 토론이 꼭 필요할 때만 B 지속형 리뷰어를 쓰고, 위 메시지는 리더가 이름 지정 SendMessage로 중계한다.

---

## Example 4: 코드 마이그레이션 팀 (Fan-out 또는 Supervisor, A 또는 B)

**선택 기준:** 작업 묶음을 미리 나눌 수 있는지에 따라 모드를 고른다.

### 4-A. 미리 나눌 수 있으면 — 워크플로

```javascript
const MIGRATION_RESULT = { type: 'object', required: ['worktreePath', 'changedFiles'], properties: {
  worktreePath: { type: 'string', minLength: 1 },
  changedFiles: { type: 'array', minItems: 1, uniqueItems: true,
    items: { type: 'string', minLength: 1 } } } }
const MIGRATION_VERDICT = { type: 'object', required: ['status', 'reason'], properties: {
  status: { type: 'string', enum: ['confirmed', 'refuted', 'uncertain'] },
  reason: { type: 'string' } } }
const migrated = await pipeline(args.batches,   // 사전 조사로 복잡도를 추정한 뒤 작업 묶음을 확정한다
  b => agent(`다음 작업 묶음을 마이그레이션하고, 격리 작업 트리의 절대 경로와 실제 변경 파일 목록을 반환하라: ${b.files.join(', ')}`,
    { agentType: 'migrator', isolation: 'worktree', schema: MIGRATION_RESULT }),
  (r, b) => r && agent(
    `격리 작업 트리 ${r.worktreePath}에서 마이그레이션 대상과 실제 변경 파일을 대조해 누락과 오류를 검증하라. 원래 대상: ${b.files.join(', ')}. 실제 변경: ${r.changedFiles.join(', ')}`,
    { agentType: 'qa-inspector', schema: MIGRATION_VERDICT })
    .then(verdict => ({ ...r, verdict })))
const confirmed = migrated.filter(Boolean)
  .filter(r => r.verdict?.status === 'confirmed')
return { confirmed }
```

검증 에이전트에는 결과가 있는 격리 작업 트리 경로를 반드시 전달한다. 워크플로가 끝나면 메인이 `confirmed` 결과의 `worktreePath`를 하나씩 확인해 기준 브랜치에 병합하거나 필요한 커밋만 선별 적용한다. 충돌은 다음 작업 트리를 합치기 전에 해결하고, 통합 테스트를 통과한 뒤에만 다음 변경을 적용한다. `refuted`·`uncertain`은 병합하지 않고 사유를 보고한다.

### 4-B. 진행 중 다시 나눠야 하면 — 지속형 감독자

```
[supervisor = 리더] → 파일 분석 → 배치 할당
    ├→ Agent(name: "migrator-1") (batch A)
    ├→ Agent(name: "migrator-2") (batch B)
    └→ Agent(name: "migrator-3") (batch C)
    ← 완료 알림 / TaskUpdate → 추가 배치 할당·재할당
```

**Dynamic Distribution Logic (동적 분배):**
1. 전체 대상 파일 목록 수집
2. 복잡도 추정 (파일 크기, import 수, 의존성)
3. `TaskCreate`로 파일 배치를 작업 등록 (`depends_on` 포함)
4. 작업자가 공유 작업 목록에서 작업을 요청(claim)해 수행 — 첫 보고에서 TaskUpdate가 없다고 하면 리더가 대신 갱신
5. 완료 알림 시: 성공 → 다음 작업 / 실패 → SendMessage로 원인 확인 후 `TaskUpdate`로 재할당
6. 모든 작업 완료 → 통합 테스트

---

## Example 5: 웹툰 제작 (Producer-Reviewer, 혼합 — B 생성자 + C 검토자)

**선택 이유:** 생성자 1명과 검토자 1명만 필요하고, 검토 결과를 생성자에게 최대 두 번 돌려보내면 된다.

```
Phase 1: Agent(name: "artist") → 패널 생성 → _workspace/panels/
Phase 2: Agent(subagent_type: "webtoon-reviewer", prompt: "패널을 검토하라") 단발 호출 → PASS/FIX/REDO
         → _workspace/review_report.md
Phase 3: REDO 판정 패널만 SendMessage({to: "artist"})로 재생성 지시 (최대 2회)
         artist가 맥락을 기억하므로 "3번 패널의 구도만 수정"처럼 범위를 좁혀 지시
재시도 방침: 2회 수정 후에도 통과 못 하면 미해결 상태와 원인을 사용자에게 보고.
             전체 패널의 50% 이상이 REDO이면 프롬프트 수정을 제안.
```

---

## Output Patterns Summary (산출물 패턴 요약)

### Agent Definition Files
- 위치: `agents/{agent-name}.md` (플러그인) / `.claude/agents/{agent-name}.md` (프로젝트)
- 필수: 핵심 역할, 작업 원칙, I/O 프로토콜, 재호출 방법, 에러 핸들링, 협업
- B 지속형 멤버: `## Team Communication Protocol` / A 워크플로 전용: 구조화 출력 형식
- 생성은 `/create-flow`, 검증은 `/verify-flow`에 위임

### Skill Files
- 위치: `skills/{name}/SKILL.md` (< 500줄)
- 초과 시 `references/`·`scripts/` 분리

### Orchestrator Skills
- 위치: `skills/{domain}-orchestrator/SKILL.md`
- 실행 모드 명시 필수, `## Team Members` 표 + `## Orchestration Phases`
- 후속 작업 키워드 포함 — [orchestrator-template.md](orchestrator-template.md)

### Workspace Artifacts
- 패턴: `_workspace/{phase}_{agent}_{artifact}.{ext}`
- 보존: 삭제하지 않음 (사후 검증·감사 추적용)
- 새 입력으로 재실행 시: `_workspace_{YYYYMMDD_HHMMSS}/`로 이동 (Phase 0 규칙)
