---
name: mvp-orchestrator
description: |
  신규 사업/서비스 MVP 루프 엔지니어링 하네스 오케스트레이터. 아이디어 한 줄을 기획(PRD)→디자인 스펙→스택 선택·스캐폴딩→PRD-driven 개발 루프의 게이트 기반 상태기계로 자율 완주시킨다. "MVP 만들어줘", "신규 서비스 프로토타입", "아이디어를 동작하는 제품으로" 요청과 그린필드 신규 서비스 구축(빈 레포에서 기획부터 시작)에 자동 트리거. /mvp-new·/mvp-run 커맨드 실행 시에도 적용. 기존 코드베이스의 단일 기능 추가·수정·리뷰에는 발동하지 않음 — 해당 작업은 스택별 플러그인(kotlin-spring/python-fastapi/go-mux/nextjs/search)으로 위임한다.
  Orchestrator of the MVP loop-engineering harness: drives a one-line idea through PRD → design spec → stack selection/scaffolding → PRD-driven dev loop as a gate-based state machine, auto-triggering on greenfield builds and on /mvp-new, /mvp-run. Use when: "build me an MVP", "prototype a new service", "turn an idea into a working product"; not for single-feature work in existing codebases.
---

# MVP Orchestrator

아이디어 한 줄을 동작하는 MVP로 완주시키는 오케스트레이터. Stage 0~4 순차 파이프라인을 게이트 기반 상태기계로 관리하고, 각 Stage의 maker/checker를 전문 에이전트에게 위임하며, Stage 4는 Stop훅 루프 엔진으로 자율 반복한다.

핵심 명제: **"완료 판정은 모델이 아니라 하네스가 한다(Completion lives outside the model)."**

## When to Apply

**발동:**
- "MVP 만들어줘", "최소 기능 제품으로 만들어줘" 요청
- "신규 서비스 프로토타입", "새 서비스 빠르게 띄워줘" 요청
- "아이디어를 동작하는 제품으로", 아이디어 한 줄 + 구현까지 의뢰
- 그린필드 신규 서비스 구축 — 빈/신규 레포에서 기획·디자인·개발 전 과정이 필요할 때
- `/mvp-new`(시작), `/mvp-run`(재개) 커맨드 실행 시

**미발동 (위임 경계):**
- 기존 코드베이스 내 단일 기능 추가·수정·리뷰 → 스택별 플러그인(kotlin-spring / python-fastapi / go-mux / nextjs / search)
- 레거시 버전업·완전 전환 → 해당 스택 플러그인의 마이그레이션 가이드 사용
- 기획 문서만/디자인 스펙만 단건 작성 → prd-authoring / mvp-design-spec 스킬 직접 사용

## Architecture

- **패턴**: Sequential Pipeline(매크로 상태기계) + Producer-Reviewer(단계 내부 maker/checker) + PRD-Driven Loop(Stage 4 내장)
- **실행 모드**: Sub-agents — 메인 세션이 오케스트레이터이며 PS/UX/TA/MV를 `Agent` 도구로 디스패치. **Stage 4의 maker 작업은 메인 세션이 `mvp-builder` 규율을 체화해 직접 수행**한다(Stop훅 루프 엔진이 메인 세션 종료를 가로채는 구조라 루프 주체 = 메인 세션이어야 훅과 맞물림).
- **메모리**: `.planning/` 디렉토리 + git history = 상태. 매 세션 아티팩트에서 이해를 재생성(compaction 의존 금지).
- **보조 엔진**: 무인/야간 실행은 [references/headless-recipe.md](references/headless-recipe.md)의 `while + claude -p` 루프 — 동일 `.planning`·동일 게이트를 공유하므로 엔진을 바꿔도 정지조건은 불변.

## Team Members

| ID | 에이전트 파일 | 역할 | 산출물 |
|----|--------------|------|--------|
| PS | `agents/product-strategist.md` | 기획 maker — 인테이크 정제 → PRD·스토리 초안. **Stage 2 checker 겸임**(디자인-PRD 커버리지 매트릭스 검증) | `.planning/prd.md`, `.planning/prd.json` 초안, 커버리지 검증 리포트 |
| UX | `agents/ux-designer.md` | 디자인 maker — IA·유저플로우·화면 명세·와이어프레임·디자인 토큰·4상태. 코드 생성 금지 | `.planning/design-spec.md` (`[story: S-xx]` 태그 의무) |
| TA | `agents/tech-architect.md` | 스택 선정 + 스캐폴딩 — 후보 비교 추천, 레포 골격·smoke 테스트·`.planning/` 초기화·초기 커밋. 루프 중 구조적 BLOCKED 시 단독 재투입 | `.planning/stack-decision.md`, 레포 골격, `.planning/gate-cmd`, 확정 `prd.json` |
| MB | `agents/mvp-builder.md` | 개발 루프 maker(메인 세션 체화) — 미완 스토리 1개씩 테스트 먼저 → 최소 구현 → 게이트 그린 → MV 검증 후 일괄 커밋. `passes` 직접 마킹 금지 | 스토리별 구현 + 테스트 + `feat(mvp): S-xx` 커밋, `progress.md` 갱신 |
| MV | `agents/mvp-verifier.md` | 회의적 checker(maker와 완전 분리) — Stage 1 PRD 반증, Stage 4 스토리 AC 반증. Edit 미보유로 코드 수정 원천 불가 | 반증 리포트, `.planning/verified/{story-id}` 마커(반증 실패 시에만) |

## Orchestration Phases

### Stage 0: 인테이크

- **Assigned to**: 메인 세션(오케스트레이터) — 질문 설계는 PS 디스패치(질문 패키지 리포트 반환), 사용자 제시·답변 수집은 메인 세션
- **Input**: 사용자 아이디어 한 줄 (+ `/mvp-new` 인자: `--auto`, `--stack`, `--stories-max`)
- **Output**: `.planning/mvp-{id}.md` 마스터 파일(## Goal 불변 기록) + 인테이크 노트(질문·답변 또는 기본값 채택 기록)
- **게이트**: 사용자 질문 **최대 3개 + 각 질문에 추천 기본값** 제시. `--auto`면 기본값 자동 채택 후 마스터에 기록.

타깃 사용자·핵심 문제·성공 기준 중 불명확한 것만 묻는다. 3개를 넘기지 않는다.

### Stage 1: 기획 (PRD)

- **Assigned to**: PS(maker) → MV(checker, Producer-Reviewer max 2라운드)
- **Input**: Stage 0의 마스터 ## Goal + 인테이크 노트
- **Output**: `.planning/prd.md`(G1 승인본) + `.planning/prd.json`(`{"stories":[{"id","title","acceptance":[],"passes":false}]}`)
- **결정론 게이트**: `gates/gate-prd.sh --initial` — prd.md 필수 헤딩 grep + prd.json jq 스키마 + 스토리 수 3~10(상한 `MVP_STORIES_MAX` 치환 가능). `--initial`은 최초 작성 검증 전용(passes 전건 false 확인) — 스코프 재협상 후 재검증은 인자 없이 호출
- **사용자 게이트**: **★G1 MVP 스코프 승인** (항상. `--auto`면 추천안 자동 채택·기록)

PS가 WebSearch로 유사 서비스 1-pass 조사 후 PRD 작성 → MV가 "이 스코프가 틀렸다면 왜?"로 반증(범위 비대·검증 불가 AC·측정 불가 지표·페르소나-스토리 불일치) → 근거 있는 반증은 PS가 수정. PRD 표준은 prd-authoring 스킬 참조.

### Stage 2: 디자인 스펙

- **Assigned to**: UX(maker) → PS(checker, 교차검증 max 2라운드)
- **Input**: Stage 1의 G1 승인된 prd.md + prd.json
- **Output**: `.planning/design-spec.md` — IA, Mermaid 유저플로우, 화면 명세(각 화면 `[story: S-xx]` 매핑 태그 의무), 텍스트/ASCII 와이어프레임, 디자인 토큰, 빈/로딩/에러/성공 4상태
- **결정론 게이트**: `gates/gate-design.sh` — prd.json의 전 story id가 design-spec.md에 `[story: S-xx]`로 등장
- **사용자 게이트**: 없음 — 자율 통과 + 1줄 보고 (디자인 승인 게이트는 의도적 기각: 텍스트 와이어프레임 승인은 형식적 클릭이 됨)

PS가 디자인-PRD 커버리지 매트릭스로 누락·왜곡을 검증한다. 스펙 표준은 mvp-design-spec 스킬 참조.

### Stage 3: 스택 선택·스캐폴딩

- **Assigned to**: TA
- **Input**: Stage 2의 design-spec.md + prd.json + [references/stack-presets.md](references/stack-presets.md)의 4스택 프리셋·결정 트리
- **Output**: `.planning/stack-decision.md`(후보·트레이드오프·선택·근거), 레포 골격 + smoke 테스트, `.planning/gate-cmd`(결정론 게이트 명령 1줄), 확정 prd.json, `.planning/` 잔여 파일 초기화, 초기 커밋
- **결정론 게이트**: `gates/gate-scaffold.sh` — gate-cmd 그린 + git 초기 커밋 존재 + `.planning` 필수 파일 존재
- **사용자 게이트**: **★G2 스택 선택** (항상. `--auto`면 추천 1순위, `--stack <preset>`이면 생략)

표준 4스택(Kotlin/Spring·Python/FastAPI·React/Next.js·Go/stdlib mux) 중 후보 2~3개를 비교 추천한다. 강제 금지 — 비표준 스택 제안 시 근거 필수. 빈 프로젝트에서 게이트 그린을 확인한 뒤 다음 Stage로 넘긴다.

### Stage 4: PRD-driven 개발 루프

- **Assigned to**: MB(메인 세션 체화) → MV(매 스토리 Agent 디스패치)
- **Input**: Stage 3의 확정 prd.json + design-spec.md + gate-cmd + 게이트 그린 상태의 레포 골격
- **Output**: 전 스토리 `passes:true` + `.planning/verified/` 마커 전건 + `progress.md`의 `<promise>MVP_COMPLETE</promise>` + 스토리별 커밋
- **게이트**: Stop훅 루프 엔진(`hooks/mvp-loop-stop-hook.sh`)이 매 반복 정지조건 3결합을 판정. 사용자 게이트 없음 — 자율 진행, BLOCKED 시만 보고.

Stage 4 진입은 직접 트리거 경로를 포함해 항상 `/mvp-run` 절차(`loop-active` 생성·`loop-state.json` 초기화)를 경유한다.

매 반복 표준 사이클: 미완(passes:false) 최우선 스토리 **1개만** 선택 → 테스트 먼저 → 최소 구현 → 게이트 그린 → MV 반증(통과까지 수정 반복) → verified 마커 → passes:true(메인 세션) → 커밋 1회(구현+prd.json+progress.md 일괄, `feat(mvp): S-xx`). 상세 운영(재개 프로토콜·BLOCKED 에스컬레이션)은 mvp-loop-protocol 스킬 참조.

#### MV 디스패치 규약 — verify-round 상태 파일

스토리 AC 반증(모드 ②) 디스패치의 오케스트레이터 의무 3가지 — SubagentStop 훅이 이 규약을 결정론 집행한다(마커 없는 verifier 종료를 exit 2 차단, round>=2는 최대 2라운드 규약으로 통과 허용).

1. **디스패치 직전**: `.planning/verify-round/{story-id}`에 `round=1`(maker 수정 후 재검이면 `round=2`) 기록
2. **결과 규약**: 반증 실패(통과) → MV가 `verified/{story-id}` 생성(기존 규약) / 반증 성공 → `refuted/{story-id}`에 구체 근거(파일:라인·실행 출력·재현 명령) 기록
3. **결과 처리 후**: `refuted`를 maker 수정 라운드 입력으로 소비하고 `verify-round/{story-id}`를 정리(삭제)한다

훅은 동일 pending 차단을 2회로 제한하고(`blocked=N` 카운터), 초과 시 스테일로 간주해 `verify-round/{story-id}`를 자동 정리한다 — verifier 재디스패치 필요.

#### --cross-check 교차 모델 반증 (opt-in, 기본 off)

`/mvp-run --cross-check` 지정 시 MV 1라운드 반증 실패 후 **verified 마커 생성 전에** 외부 CLI 교차 반증을 삽입한다 — **외부 반증도 실패해야 마커가 생성**된다(마커 사후 제거·refuted 병기 경로 원천 배제).

- **실행**: 오케스트레이터가 MV 디스패치 프롬프트에 cross-check 지시를 포함 — MV가 마커 생성 직전 etc:with 라우팅 규약(`which` 기반 가용성 감지, Codex `codex exec` / Antigravity `agy -p`)으로 스토리 AC + diff를 외부 CLI에 전달해 독립 반증시킨다. 마커 생성 전 실행이라 SubagentStop 집행과 순서 충돌이 없다.
- **외부 반증 성공 시**: 마커 미생성 + `refuted/{story-id}`에 외부 근거 기록 → maker 수정 후 round=2 재검. 외부 반증에도 '구체 근거 없는 FAIL 금지' 규약이 동일 적용된다(오반증 방지).
- **폴백**: 외부 CLI 미설치(`which` 전건 실패) 시 기존 동일 모델 max 2라운드 규약으로 graceful 폴백(1줄 고지).

## Gate Policy (자율 통과 + 실패 시만 보고)

| 결과 | 동작 |
|------|------|
| **통과** | 사용자 확인 없이 다음 Stage 자동 진행. 완료를 1줄로 보고. |
| **실패** | 진행 중단. 실패 Stage·원인·시도한 해결·남은 옵션을 보고. |
| **모호** (판정 불가) | 진행 중단. 무엇이 불명확한지 + 권장안을 보고. |

**사용자 게이트는 정확히 2개** (자율 통과 금지):
- **G1 — MVP 스코프 승인** (Stage 1 종료): PRD 요약 + 스토리 목록 + Out of Scope를 제시하고 승인을 받는다.
- **G2 — 스택 선택** (Stage 3 진입): 후보 2~3개 비교표 + 추천 1순위를 제시하고 선택을 받는다.

**`--auto` 동작**: G1·G2를 추천 1순위로 자동 채택하고 마스터 `## Gates`에 `auto 채택` 스탬프를 남긴다. 스코프·스택 판단을 LLM 추천에 위임하므로 **해커톤/실험용**임을 시작 시 1줄 고지한다. 완료 시 최종 보고는 게이트가 아니라 보고다.

## Producer-Reviewer 규약

| Stage | maker | checker | 검증 관점 |
|-------|-------|---------|----------|
| 1 | PS | MV | PRD 반증 — "이 스코프가 틀렸다면 왜?" |
| 2 | UX | PS | 디자인-PRD 커버리지 매트릭스(누락 스토리·왜곡된 AC) |
| 4 | MB | MV | 스토리 AC 반증 — 엣지케이스 직접 실행, 테스트 사기(assertion 약화/skip/삭제) 적발, gate-cmd 독립 재실행 |

- **비평가 재사용**: 새 에이전트를 만들지 않고 기존 팀원을 checker로 배치한다.
- **자기발견 제외**: checker는 자신이 만든 산출물을 검증하지 않는다(maker/checker 완전 분리 — MV는 Edit 미보유로 코드 수정 원천 불가).
- **반증 실패 시 통과**: 기본값은 통과. 반증에는 구체적 근거를 요구해 과잉 강등을 방지한다.
- **max 2라운드**: 같은 산출물에 대한 maker 수정→checker 재검은 2라운드 상한. 미해결 이슈는 잔여 리스크로 사용자 게이트/보고에 첨부한다. (Stage 4는 루프 자체가 반복이므로 라운드 상한 대신 circuit breaker가 상한.)

## Agent Dispatch

각 에이전트는 `Agent` 도구로 호출한다. 서브에이전트는 **이전 대화를 모른다.**

```
Agent({
  description: "{에이전트명} — {Stage 요약}",
  subagent_type: "{agent-id}",
  prompt: "{읽어야 할 .planning 파일 경로(프로젝트 루트 기준), 이전 Stage 산출물 위치,
           산출물 작성 경로, 통과해야 할 게이트 기준(gates/*.sh 판정 항목)을 명시.
           출력 형식(파일 + 200자 이내 요약)을 지정.}"
})
```

**프롬프트 작성 원칙:**
- `.planning/prd.md`·`prd.json`·`design-spec.md` 등 입력 파일 경로를 항상 명시
- 게이트 기준을 그대로 전달 — 에이전트가 스스로 게이트를 만족하는 산출물을 내도록 ([references/gate-policy.md](references/gate-policy.md) 판정 기준 인용)
- checker 디스패치에는 "반증 실패 시 통과, 반증에는 구체 근거" 원칙을 포함

## Loop Control (Stage 4)

**정지조건 3결합** — 판정 주체는 모델이 아니라 훅:

| # | 조건 | 메커니즘 |
|---|------|---------|
| ① | 결정론 게이트 | `.planning/gate-cmd` 동적 로드(`LOOP_TEST_CMD` env 우선) → **exit code 우선 판정** AND `jq -e '[.stories[].passes] | all'` |
| ② | 회의적 Evaluator | `passes:true` 전환은 MV의 `.planning/verified/{story-id}` 마커 선행 필수 — `prd-guard.sh` 훅이 마커 없는 마킹을 exit 2 차단 + false 되돌림. **Evaluator 판정을 파일 마커로 물화해 결정론 검사로 변환** |
| ②ᴱ | E2E 수용 게이트(선택) | `.planning/e2e-gate-cmd`(또는 `LOOP_E2E_CMD` env) 존재 시 **all-passes 도달 시점에만 1회** 실행 → exit 0 그린 필수. 파일 없으면 미적용(통과 간주, 회귀 0). 전체 유저플로우의 최종 동작을 보증해 단위 게이트가 못 잡는 통합 실패를 차단 |
| ③ | Completion promise | `progress.md`에 `<promise>MVP_COMPLETE</promise>` 정확 문자열(grep -qF) |

종료 허용 = ① ∧ ②ᴱ ∧ ③ (②는 Stop훅이 verified 마커 재검사로 ①에 인입 — prd-guard 1차 차단의 최종 방어선. ②ᴱ는 e2e-gate-cmd 없으면 자동 통과).

**가드레일 5종 요약:**

| 가드 | 기본값 | 동작 |
|------|--------|------|
| max iterations | `LOOP_MAX_ITER=24` (권장: 스토리 수×3) | 도달 시 종료 허용 + 미완 보고 |
| no-progress | 실패 시그니처(md5) 연속 2회 동일 | 종료 + `BLOCKED.md` 기록 |
| 시간 상한 | `LOOP_MAX_MINUTES=120` | 초과 시 현 반복 완료 후 종료 + 재개 방법 보고 |
| 킬스위치 | `/mvp-stop` | `loop-active` 삭제 → 훅 즉시 무력화, 핸드오프 기록 |
| circuit breaker | 동일 스토리 연속 3회 실패(오케스트레이터 정책) | 해당 스토리 skip + BLOCKED 기록 후 다음 스토리 |

**안전핀**: `loop-active` 파일이 없으면 Stop훅은 무동작(exit 0) — 루프 미가동 세션의 종료를 절대 방해하지 않는다. 모든 종료 경로에서 `loop-active`를 삭제한다.

> 게이트 스크립트 판정 기준·훅 동작·환경변수 상세는 [references/gate-policy.md](references/gate-policy.md), 매 반복 사이클·재개 프로토콜·env 표 운영은 mvp-loop-protocol 스킬에 위임.

## Completion Criteria

전부 충족해야 완료로 판정한다:

- [ ] `prd.json` 전 스토리 `passes:true` (`jq` all-passes 그린)
- [ ] 모든 `passes:true` 스토리에 `.planning/verified/{story-id}` 마커 존재
- [ ] `gate-cmd` 최종 1회 독립 재실행 exit 0 (그린)
- [ ] (E2E 적용 시) `e2e-gate-cmd` 최종 1회 독립 재실행 exit 0 — 전체 유저플로우 그린
- [ ] `progress.md`에 `<promise>MVP_COMPLETE</promise>` 정확 문자열 존재
- [ ] 스토리별 `feat(mvp): S-xx` 커밋이 git log에 존재
- [ ] 마스터 `mvp-{id}.md`가 `status: done` + ## Gates에 G1·G2 승인 스탬프
- [ ] `loop-active` 삭제 확인 (잔존 시 `/mvp-status`의 수동 해제 절차 안내)
- [ ] 최종 보고 전달: 완료 스토리 n/m, 핵심 커밋, 로컬 실행 방법, 잔여 리스크

## Error Handling

| 상황 | 대응 |
|------|------|
| 게이트 실패 (`gates/*.sh` exit≠0) | 해당 Stage 중단. 실패 항목·원인·시도·옵션 보고. maker 수정 후 `/mvp-gate`로 재판정 |
| no-progress (동일 실패 연속 2회) | 루프 종료 + `BLOCKED.md`에 iteration·실패 시그니처·테스트 출력 tail 기록 후 보고 |
| 시간 상한 초과 (`LOOP_MAX_MINUTES`) | 현 반복 완료 후 종료. 진행률 + `/mvp-run` 재개 방법 보고 |
| circuit breaker (동일 스토리 3연속 실패) | 해당 스토리 skip + BLOCKED 기록, 다음 미완 스토리로 진행. 전 스토리 소진 시 보고 |
| BLOCKED 에스컬레이션 | 원인 분류 후 재투입: **스코프 문제(AC 자체가 무리) → PS 재협상** / **구조 문제(골격·의존성 한계) → TA 단독 재투입**. 판단 불가면 사용자 보고 |
| 에이전트 실패/타임아웃 | 부분 산출물 보존, 원인 보고 후 재디스패치(1회) 또는 중단 결정 |
| `loop-active` 잔존 (비정상 종료) | `/mvp-status`가 감지·수동 해제법 안내. 새 루프 시작 전 정리 필수 |
| 테스트 삭제 시도 | `test-guard.sh` 훅이 exit 2 차단. 정당한 삭제 필요 시 BLOCKED 경유로 사용자 승인 |

## Re-run Support

- **Stage 단위 재실행**: 마스터 `## Stage`를 대상 단계로 되돌리고 해당 maker를 재디스패치한다. 이전 산출물은 `.planning/`에 보존되어 입력으로 재사용된다(이미 통과한 Stage의 산출물은 갱신 요청이 없는 한 재생성하지 않음).
- **게이트만 재실행**: `/mvp-gate` — 현 Stage의 `gates/*.sh` + 해당 checker 디스패치를 다시 수행.
- **루프 재개**: `/mvp-run` — 마스터 `status` 기반 재개 프로토콜(① 마스터 읽기 ② `git log --oneline -10` ③ 미완 스토리 1개 ④ 작업→검증→마커→passes→일괄 커밋)로 어느 시점에서든 이어서 실행. `--max-iter`·`--max-minutes`로 가드 조정.
- **상태 복구 원천**: `.planning/` + git history. 세션이 끊겨도 아티팩트에서 이해를 재생성하므로 컨텍스트 손실은 진행 손실이 아니다.

## References

| 문서 | 내용 |
|------|------|
| [references/stack-presets.md](references/stack-presets.md) | 4스택(Kotlin/Spring·Python/FastAPI·React/Next.js·Go/stdlib mux) 골격 레이아웃·smoke 테스트·gate-cmd·선택 결정 트리 |
| [references/headless-recipe.md](references/headless-recipe.md) | 무인/야간용 `while + claude -p` 루프 레시피(컨텍스트 리셋형, 동일 게이트 공유) |
| [references/gate-policy.md](references/gate-policy.md) | gates/*.sh 판정 기준 명세 + Stop훅 정지조건 3결합 상세 + 가드레일 환경변수 표 |

**관련 스킬**: prd-authoring(Stage 1 표준) / mvp-design-spec(Stage 2 표준) / mvp-loop-protocol(Stage 4 운영)

## Boundaries

**Will:**
- Stage 0~4 상태기계 관리, 게이트 판정 위임·결과 보고
- maker/checker 에이전트 디스패치와 Producer-Reviewer 라운드 관리
- Stage 4 루프 가동·가드레일 집행·BLOCKED 에스컬레이션 라우팅
- `.planning/` 메모리·재개 프로토콜 유지

**Will Not:**
- 게이트 검증 없이 다음 Stage 진행
- 사용자 게이트(G1 스코프·G2 스택)를 `--auto` 없이 자율 통과
- MV의 verified 마커 없이 `passes:true` 마킹(prd-guard 훅이 차단)
- 기존 코드베이스 기능 작업(각 팀 오케스트레이터 위임)·실제 운영 배포·인프라 프로비저닝
