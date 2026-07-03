---
name: feature-loop-orchestrator
description: "기존(브라운필드) 코드베이스용 루프 엔지니어링 하네스 오케스트레이터. 자연어 기능 요청 한 줄을 코드베이스 분석 기반 작업 분해(tasks.json)→baseline 캡처→회귀 안전 개발 루프의 게이트 상태기계로 자율 완주시킨다. \"이 기능 추가해줘\", \"X 리팩토링\", \"이 코드베이스에 Y 붙여줘\" 등 이미 개발 중/완료된 프로젝트의 기능 추가·수정 요청과 /floop-new·/floop-run 커맨드 실행 시 적용. MVP의 검증된 루프 인프라(Stop훅 엔진·maker/checker 반증·가드레일·.planning 메모리)를 재사용하되 입력은 작업 분해, 게이트는 baseline 회귀 방지. 루프 안에서 스택 플러그인·analyze·test·workflow를 호출. 빈/신규 레포의 기획부터 시작하는 그린필드 신규 서비스에는 발동하지 않음 — mvp 플러그인으로 위임한다."
---

# Feature Loop Orchestrator (브라운필드)

자연어 기능 요청 한 줄을 **기존 코드베이스 위에서** 회귀 없이 완주시키는 오케스트레이터. Stage A~C 파이프라인을 게이트 기반 상태기계로 관리하고, 각 Stage의 maker/checker를 전문 에이전트에게 위임하며, Stage C는 Stop훅 루프 엔진으로 자율 반복한다.

핵심 명제: **"완료 판정은 모델이 아니라 하네스가 한다."** 브라운필드 추가 명제: **"회귀 없음도 하네스가 baseline 대비로 판정한다."**

## When to Apply

**발동:**
- "이 기능 추가해줘", "X 리팩토링해줘", "이 코드베이스에 Y 붙여줘" — 이미 코드가 있는 프로젝트의 기능 추가·수정·리팩토링
- 자연어 요청 + 여러 task로 분해해 반복 구현이 필요할 때
- `/floop-new`(시작), `/floop-run`(재개) 커맨드 실행 시

**미발동 (위임 경계):**
- 빈/신규 레포에서 기획(PRD)부터 시작하는 그린필드 신규 서비스 → **mvp 플러그인**
- 단일 파일 1줄 수정·즉답 가능한 작업 → 루프 불필요, 직접 수행
- 기획 문서/디자인만 단건 작성 → 해당 플러그인 스킬 직접 사용

## Architecture

- **패턴**: Sequential Pipeline(A~C 상태기계) + Producer-Reviewer(maker/checker) + Regression-Safe Loop(Stage C)
- **실행 모드**: Sub-agents — 메인 세션이 오케스트레이터로 TP/FV를 `Agent` 디스패치. **Stage C의 maker(FB)는 메인 세션이 규율을 체화해 직접 수행**(Stop훅이 메인 세션 종료를 가로채는 구조).
- **메모리**: `.planning/` + git history = 상태. 매 세션 아티팩트에서 이해 재생성.
- **MVP 대비 차이**: 생성 단계(PRD·디자인·스캐폴딩) 제거. 대신 **코드베이스 분석 기반 분해 + baseline 캡처**가 입력. 게이트 방향이 "생성 검증"에서 "회귀 방지"로 전환.

## Team Members

| ID | 에이전트 파일 | 역할 | 산출물 |
|----|--------------|------|--------|
| TP | `agents/task-planner.md` | 작업 분해 maker — 코드베이스 분석 → tasks.json. **Stage B checker 겸 아님**(분해 반증은 FV). BLOCKED 재분해 | `.planning/tasks.json` 초안 |
| FB | `agents/feature-builder.md` | 개발 루프 maker(메인 세션 체화) — 미완 task 1개씩 테스트 먼저 → 최소 구현 → 게이트 그린+회귀 0 → FV 검증 후 일괄 커밋 | task별 구현+테스트+`feat: T-xx` 커밋, progress 갱신 |
| FV | `agents/feature-verifier.md` | 회의적 checker — task AC 반증 + **회귀 반증**(baseline 대조) + 사기 적발 + (선택)analyze 렌즈. Edit 미보유 | 반증 리포트, `.planning/verified/{task-id}` 마커 |

## Orchestration Phases

### Stage A: 인테이크 + baseline 캡처 (`/floop-new`)

- **Assigned to**: 메인 세션(오케스트레이터)
- **Input**: 자연어 요청 한 줄 (+ `--auto`, `--gate-cmd`, `--tasks-max`)
- **Output**: `.planning/request.md`(원본 불변) + 마스터 `floop-{id}.md`(## Goal 불변) + `.planning/gate-cmd` + `.planning/baseline.json`
- **동작**:
  1. `request.md` 기록 + 마스터 생성.
  2. **스택 자동 감지** → gate-cmd 결정 (`build.gradle*`→`./gradlew test`, `pyproject.toml`→`pytest -q`, `package.json`+next→`pnpm test`, `go.mod`→`go test ./...`). 모호 시 사용자 확인 또는 `--gate-cmd` 명시.
  3. **baseline 캡처** — `hooks/gates/capture-baseline.sh` 실행 → `baseline.json`. baseline red면 기존 실패 수를 1줄 경고(회귀 게이트가 fail_count ≤ N로 동작).
- **게이트**: gate-cmd 실행 가능 확인. 사용자 게이트 없음.

### Stage B: 작업 분해 (`task-planner` maker → `feature-verifier` checker)

- **Assigned to**: TP(Agent 디스패치) → FV(분해 반증) → 메인 세션 사용자 게이트
- **Input**: `request.md` + 코드베이스
- **Output**: `.planning/tasks.json` (`{"tasks":[{"id":"T-01","title","acceptance":[],"passes":false}]}`)
- **결정론 게이트**: `hooks/gates/gate-tasks.sh --initial` — jq 스키마 + 개수 2~`FLOOP_TASKS_MAX`(기본 10) + passes 전건 false
- **사용자 게이트 ★G1 — 작업 목록 승인**(항상; `--auto`면 자동 채택·스탬프): 분해 task 목록 + 영향 파일 + 회귀 위험을 제시하고 승인

TP가 코드베이스를 탐색해 수직 슬라이스로 분해 → FV가 "이 분해가 틀렸다면 왜?"로 반증(범위 비대·검증 불가 AC·회귀 보존 AC 누락) → 근거 있는 반증은 TP가 수정. 분해 표준은 `task-decomposition` 스킬 참조.

### Stage C: 회귀 안전 개발 루프 (`feature-builder` 체화 → `feature-verifier` 매 task)

- **Assigned to**: 메인 세션(FB 규율 체화) → FV(매 task Agent 디스패치)
- **Input**: 확정 tasks.json + gate-cmd + baseline.json + 게이트 그린 상태의 레포
- **Output**: 전 task `passes:true` + `.planning/verified/` 마커 전건 + `progress.md`의 `<promise>FEATURE_COMPLETE</promise>` + task별 커밋
- **게이트**: Stop훅 루프 엔진(`hooks/floop-loop-stop-hook.sh`)이 매 반복 정지조건 4결합 판정. 사용자 게이트 없음 — 자율, BLOCKED 시만 보고.

Stage C 진입은 항상 `/floop-run` 절차(`loop-active` 생성·`loop-state.json` 초기화)를 경유. 매 반복 표준 사이클: 미완 task 1개 → 테스트 먼저 → 최소 구현(스택 플러그인 활용) → 게이트 그린+회귀 0 → FV 반증 → verified 마커 → passes:true → 커밋 1회. 상세는 `floop-loop-protocol` 스킬 참조. **완료 후** `workflow:shipping-guide`로 배포 전 체크를 안내(루프 밖, 보고).

#### FV 디스패치 규약 — verify-round 상태 파일

task AC·회귀 반증(모드 ②) 디스패치의 오케스트레이터 의무 3가지 — SubagentStop 훅이 이 규약을 결정론 집행한다(마커 없는 verifier 종료를 exit 2 차단, round>=2는 최대 2라운드 규약으로 통과 허용).

1. **디스패치 직전**: `.planning/verify-round/{task-id}`에 `round=1`(maker 수정 후 재검이면 `round=2`) 기록
2. **결과 규약**: 반증 실패(통과) → FV가 `verified/{task-id}` 생성(기존 규약) / 반증 성공 → `refuted/{task-id}`에 구체 근거(파일:라인·실행 출력·재현 명령) 기록
3. **결과 처리 후**: `refuted`를 FB 수정 라운드 입력으로 소비하고 `verify-round/{task-id}`를 정리(삭제)한다

훅은 동일 pending 차단을 2회로 제한하고(`blocked=N` 카운터), 초과 시 스테일로 간주해 `verify-round/{task-id}`를 자동 정리한다 — verifier 재디스패치 필요.

#### --cross-check 교차 모델 반증 (opt-in, 기본 off)

`/floop-run --cross-check` 지정 시 FV 1라운드 반증 실패 후 **verified 마커 생성 전에** 외부 CLI 교차 반증을 삽입한다 — **외부 반증도 실패해야 마커가 생성**된다(마커 사후 제거·refuted 병기 경로 원천 배제).

- **실행**: 오케스트레이터가 FV 디스패치 프롬프트에 cross-check 지시를 포함 — FV가 마커 생성 직전 etc:with 라우팅 규약(`which` 기반 가용성 감지, Codex `codex exec` / Antigravity `agy -p`)으로 task AC + diff를 외부 CLI에 전달해 독립 반증시킨다. 마커 생성 전 실행이라 SubagentStop 집행과 순서 충돌이 없다.
- **외부 반증 성공 시**: 마커 미생성 + `refuted/{task-id}`에 외부 근거 기록 → FB 수정 후 round=2 재검. 외부 반증에도 '구체 근거 없는 FAIL 금지' 규약이 동일 적용된다(오반증 방지).
- **폴백**: 외부 CLI 미설치(`which` 전건 실패) 시 기존 동일 모델 max 2라운드 규약으로 graceful 폴백(1줄 고지).

## Loop Control (Stage C) — 정지조건 4결합

판정 주체는 모델이 아니라 Stop훅:

| # | 조건 | 메커니즘 |
|---|------|---------|
| ① | 결정론 게이트 | `.planning/gate-cmd` 동적 로드(`LOOP_TEST_CMD` 우선) → exit code 우선 AND `jq '[.tasks[].passes]|all'` |
| ②ᴿ | **baseline 회귀 게이트** | `.planning/baseline.json` 기준선 대비 신규 실패 0. baseline green→gate green이 곧 회귀 0 / baseline red→현재 fail_count ≤ 기준선. 부재 시 미적용(호환) |
| ② | 회의적 Evaluator | `passes:true` 전환은 FV의 `.planning/verified/{id}` 마커 선행 — `tasks-guard.sh`가 마커 없는 마킹 exit 2 차단 + Stop훅 재검사 |
| ②ᴱ | E2E 수용 게이트(선택) | `.planning/e2e-gate-cmd` 존재 시 all-passes 도달 시 1회 실행 |
| ③ | Completion promise | `progress.md`에 `<promise>FEATURE_COMPLETE</promise>` 정확 문자열(grep -qF) |

종료 허용 = **① ∧ ②ᴿ ∧ ②ᴱ ∧ ③** (②는 ①의 all-passes에 마커 재검사로 인입).

**가드레일 5종**: max iterations(`LOOP_MAX_ITER=24`) · no-progress(실패 시그니처 연속 2회) · 시간 상한(`LOOP_MAX_MINUTES=120`) · 킬스위치(`/floop-stop`) · circuit breaker(동일 task 3연속 실패 → skip+BLOCKED). **안전핀**: `loop-active` 없으면 Stop훅 무동작(exit 0).

## Gate Policy (자율 통과 + 실패 시만 보고)

| 결과 | 동작 |
|------|------|
| **통과** | 사용자 확인 없이 다음 Stage 자동 진행. 1줄 보고 |
| **실패** | 진행 중단. 실패 Stage·원인·시도·옵션 보고 |
| **모호** | 진행 중단. 불명확 지점 + 권장안 보고 |

**사용자 게이트는 정확히 1개**: **G1 — 작업 목록 승인**(Stage B 종료). `--auto`면 자동 채택·스탬프(해커톤/실험용 1줄 고지).

## 협업 호출 규약 (루프 안에서 기존 하네스 활용)

| 시점 | 호출 대상 | 용도 |
|------|----------|------|
| Stage B 분해 | `workflow:planning-guide`, `workflow:spec-driven-dev` | 수직 슬라이싱·task 사이징 |
| Stage C 구현(FB) | 스택 플러그인 `*-gen`/`*-guide`(kotlin-spring·python-fastapi·go-mux·nextjs), `test:tdd` | 스택 자동 감지 후 관용 구현·테스트 먼저 |
| Stage C 검증(FV) | `analyze:arch-reviewer`·`perf-reviewer`, `backend-shared:security-check` | 테스트가 못 잡는 구조·성능·보안 회귀 렌즈 |
| 완료 후 | `workflow:shipping-guide`, `workflow:review-mr` | 배포 전 체크·MR 리뷰 |

## Agent Dispatch

```
Agent({
  description: "{에이전트명} — {Stage 요약}",
  subagent_type: "{agent-id}",
  prompt: "{읽어야 할 .planning 파일 경로, 코드베이스 탐색 범위, 산출물 작성 경로,
           통과할 게이트 기준(gates/*.sh 판정 항목). checker에는 '반증 실패 시 통과,
           반증에는 구체 근거' + baseline.json 회귀 대조를 명시. 출력 형식 지정.}"
})
```

## Completion Criteria

- [ ] `tasks.json` 전 task `passes:true` (jq all-passes 그린)
- [ ] 모든 `passes:true` task에 `.planning/verified/{task-id}` 마커 존재
- [ ] `gate-cmd` 최종 1회 독립 재실행 exit 0
- [ ] **baseline 회귀 0** — 현재 실패 수 ≤ `baseline.json` 기준선
- [ ] (E2E 적용 시) `e2e-gate-cmd` 최종 exit 0
- [ ] `progress.md`에 `<promise>FEATURE_COMPLETE</promise>` 정확 문자열
- [ ] task별 `feat: T-xx` 커밋이 git log에 존재
- [ ] 마스터 `floop-{id}.md` `status: done` + ## Gates에 G1 승인 스탬프
- [ ] `loop-active` 삭제 확인
- [ ] 최종 보고: 완료 task n/m, 핵심 커밋, 회귀 0 확인, 잔여 리스크, 배포 전 체크 안내

## Error Handling

| 상황 | 대응 |
|------|------|
| 게이트 실패 (`gates/*.sh` exit≠0) | Stage 중단. 실패 항목·원인·옵션 보고. maker 수정 후 `/floop-gate` 재판정 |
| **회귀 감지** (②ᴿ exit 2) | 루프가 재주입 — FB가 신규 실패를 구현 수정으로 0 복구(기존 테스트 수정 금지) |
| no-progress (동일 실패 2회) | 루프 종료 + BLOCKED.md 기록 후 보고 |
| 시간 상한 초과 | 현 반복 완료 후 종료. `/floop-run` 재개 방법 보고 |
| circuit breaker (동일 task 3연속 실패) | skip + BLOCKED 기록, 다음 task |
| BLOCKED 에스컬레이션 | **스코프 결함 → TP 재분해** / **구조 한계 → 스택 플러그인 가이드 참조·사용자 보고** |
| `loop-active` 잔존 | `/floop-status`가 감지·수동 해제(`rm .planning/loop-active`) |
| 테스트 삭제 시도 | `test-guard.sh` exit 2 차단 |

## Boundaries

**Will:**
- Stage A~C 상태기계 관리, 게이트 판정 위임·결과 보고
- TP/FV 디스패치와 Producer-Reviewer 라운드 관리
- Stage C 루프 가동·가드레일 집행·BLOCKED 라우팅
- baseline 캡처·회귀 게이트 운영, `.planning/` 메모리·재개 프로토콜 유지
- 루프 안에서 스택 플러그인·analyze·test·workflow 협업 호출

**Will Not:**
- 게이트 검증 없이 다음 Stage 진행
- 사용자 게이트(G1 작업 목록)를 `--auto` 없이 자율 통과
- FV의 verified 마커 없이 `passes:true` 마킹(tasks-guard 차단)
- 그린필드 신규 서비스 기획(mvp 위임)·실제 운영 배포·인프라 프로비저닝
