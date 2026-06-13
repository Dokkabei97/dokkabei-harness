---
name: floop-loop-protocol
description: |
  feature-loop 개발 루프(Stage C) 운영 프로토콜. 매 반복 표준 사이클(task 선택→메인 세션 구현→
  feature-verifier 반증→verified 마커→passes:true→progress 갱신→일괄 커밋), /floop-run 재개 프로토콜
  4단계, 정지조건 4결합(결정론 게이트+baseline 회귀+verified 마커+completion promise), 환경변수 튜닝
  (LOOP_TEST_CMD·LOOP_E2E_CMD·LOOP_PROMISE·LOOP_MAX_ITER·LOOP_MAX_MINUTES), loop-active 플래그 수명주기,
  가드레일 5종, BLOCKED.md 에스컬레이션을 정의한다. /floop-run으로 루프를 시작·재개할 때,
  중단된 루프를 복구할 때, 가드레일 기본값을 조정할 때, baseline 회귀 차단을 해석할 때, BLOCKED를 처리할 때 참조.
---

# Feature Loop Protocol (브라운필드 Stage C)

feature-loop-orchestrator의 Stage C(개발 루프)를 운영하는 단일 규약. 루프 엔진은 Stop훅
(`${CLAUDE_PLUGIN_ROOT}/hooks/floop-loop-stop-hook.sh`)이며, 완료 판정의 주체는 모델이 아니라 훅이다.
MVP 루프 프로토콜과 동일한 골격이되, **baseline 회귀 게이트(②ᴿ)**가 추가된 점이 핵심 차이다.

## When to Apply

- `/floop-run`으로 개발 루프를 시작하거나 중단된 루프를 재개할 때 (재개 프로토콜 4단계)
- 루프가 가드레일(max-iter·no-progress·시간 상한)로 멈췄거나 `status: paused`에서 복구할 때
- `LOOP_MAX_ITER`·`LOOP_MAX_MINUTES` 등 가드레일을 프로젝트 규모에 맞게 튜닝할 때
- **baseline 회귀(②ᴿ)로 종료가 차단**된 이유를 해석할 때
- task가 BLOCKED 처리되어 에스컬레이션(재분해 vs 구조 한계)을 판단할 때
- `loop-active`가 잔존해 세션 종료가 차단될 때 (수동 해제)
- tasks-guard·test-guard 훅이 작업을 차단(exit 2)한 이유를 해석할 때

## .planning/ 메모리 레이아웃

상태는 컨텍스트가 아니라 디스크에. 모든 경로는 프로젝트 루트 기준 상대경로.

```
.planning/
├── floop-{id}.md     # 마스터: ## Goal(불변) / ## Stage / ## Gates(승인 스탬프) / ## Checklist
│                     #        / ## Iteration / ## Feedback + status: in_progress|paused|blocked|done
├── request.md        # 원본 자연어 요청(불변)
├── tasks.json        # {"tasks":[{"id":"T-01","title":...,"acceptance":[...],"passes":false}]}
├── baseline.json     # {captured_at, gate_cmd, baseline_exit, fail_count} — 회귀 판정 기준선
├── gate-cmd          # 결정론 게이트(단위/통합) 명령 1줄 (스택 감지로 결정, 훅이 로드)
├── e2e-gate-cmd      # (선택) E2E 수용 게이트 명령 1줄
├── progress.md       # 반복 로그 1줄/회 + <promise>FEATURE_COMPLETE</promise>
├── loop-state.json   # {iteration, last_fail_sig, started_at(epoch 초), max_iter, max_minutes}
├── loop-active       # 루프 가동 플래그(빈 파일) — /floop-run 생성, 훅 종료 경로에서 삭제
├── verified/         # feature-verifier 승인 마커 T-01, T-02 ...
└── BLOCKED.md        # 시도·차단 원인·권장 다음 행동
```

## 매 반복 표준 사이클

한 반복 = task 정확히 1개. 단계·산출 파일을 건너뛰거나 순서를 바꾸지 않는다.

| # | 단계 | 수행 주체 | 명령·파일 |
|---|------|----------|-----------|
| 1 | task 선택 | 메인 세션 | `jq -r '[.tasks[] \| select(.passes == false)][0].id' .planning/tasks.json` — 미완 최우선 1개 |
| 2 | 구현 | 메인 세션(`feature-builder` 규율) | 테스트 먼저 → 최소 구현(스택 플러그인 활용) → `.planning/gate-cmd`로 게이트 그린 확인. **기존 테스트 삭제·약화 금지**. 병렬 구현 시에만 worktree 격리 서브에이전트 |
| 3 | 반증 | `feature-verifier` 디스패치 | AC 반증 + **회귀 반증**(baseline.json 대조 + 인접 테스트) + 사기 적발(기존 역수정 포함) + gate-cmd 독립 재실행 |
| 4 | verified 마커 | `feature-verifier` | 반증 **실패 시에만** `.planning/verified/{task-id}` 생성. 반증 성공 시 마커 없이 지적 반환 → 2단계 회귀 |
| 5 | passes:true | 메인 세션 | 마커 확인 후 `tasks.json` 해당 task `passes` true 갱신. tasks-guard 훅이 마커 재검사 |
| 6 | progress 갱신 | 메인 세션 | `progress.md`에 1줄: `iter N \| T-xx verified \| passes n/m`. 마스터 Checklist·Iteration·Feedback 동기 갱신 |
| 7 | 커밋 | 메인 세션 | `git add -A && git commit -m "feat: T-xx <요지>"` — 구현+tasks.json+progress.md **1커밋 일괄**, task id 필수 |

전 task `passes:true` 도달 시 **(E2E 수용 게이트 적용 프로젝트)**: promise 기록 전에 먼저
`.planning/e2e-gate-cmd`를 실행해 전체 유저플로우 동작을 확인한다.
- E2E 그린 → progress.md 마지막 줄에 `<promise>FEATURE_COMPLETE</promise>`를 정확히 기록하고 마스터 `status: done` → Stop훅이 정지조건(① ∧ ②ᴿ ∧ ②ᴱ ∧ ③) 재검사 후 종료 허용.
- E2E 레드 → promise 기록 금지. 깨진 플로우 커버 task를 보완해 다시 그린.

E2E 미적용 프로젝트는 전 task `passes:true` 도달 + 회귀 0 즉시 promise 기록. promise 정확 기록 + `status: done` 후 Stop훅이 종료 허용.

## 재개 프로토콜 (4단계)

루프가 끊긴 뒤(`/floop-run` 재실행, 새 세션, SessionStart 훅 안내) compaction 기억에 의존하지 말고 매번 아티팩트에서 재생성:

1. **마스터 읽기** — `.planning/floop-{id}.md`. `status: in_progress`면 복구 모드. `paused`면 `/floop-stop` 이력 확인 후 의사 확인(단 `/floop-run` 명시 호출은 재개 의사로 간주), `blocked`면 BLOCKED.md부터. `BLOCKED.md` 존재 시 status 무관하게 blocked 간주.
2. **이력 파악** — `git log --oneline -10` + `progress.md`로 직전 진행 지점·마지막 커밋 task 파악.
3. **미완 task 1개 선택** — 표준 사이클 1단계 jq 질의. 한 번에 하나.
4. **작업·갱신** — 표준 사이클 2~7단계. 깨끗한 핸드오프를 남긴다.

> **baseline 재확인**: 재개 시 `baseline.json`이 존재하는지 확인한다. 없으면(직접 실행·구버전) 회귀 게이트가 미적용되므로, 정확한 회귀 추적을 원하면 `/floop-new` 없이도 `hooks/gates/capture-baseline.sh`를 1회 실행해 기준선을 만들 수 있다(단 현재 코드 상태가 기준선이 됨에 유의 — 가능하면 작업 착수 전 캡처).

## 정지조건 4결합 (판정 주체 = Stop훅)

| # | 조건 | 검사 방식 |
|---|------|-----------|
| ① | 결정론 게이트 | `.planning/gate-cmd` 동적 로드(`LOOP_TEST_CMD` 우선) → **exit code 우선**(grep 보조) **AND** `jq -e '[.tasks[].passes]|all'`. all-passes 시 passes==true 각 id의 `verified/{id}` 마커 재검사 |
| ②ᴿ | **baseline 회귀 게이트** | `baseline.json` 로드. baseline_exit==0이면 gate green이 곧 회귀 0. baseline_exit!=0이면 현재 fail_count 추출 후 **fail_count ≤ 기준선**일 때만 통과(증가=회귀 차단, 파싱 불가=보수 차단). 파일 부재 시 미적용(회귀 0 간주) |
| ② | 회의적 Evaluator | passes:true 전환은 verified 마커 선행 필수. `tasks-guard.sh`(PostToolUse)가 마커 없는 마킹 exit 2 차단 + false 되돌림 |
| ②ᴱ | E2E 수용 게이트(선택) | `.planning/e2e-gate-cmd`(또는 `LOOP_E2E_CMD`) 있으면 all-passes 도달 시 1회 실행 → exit 0 필수. 부재 시 미적용 |
| ③ | Completion promise | `progress.md`에 `<promise>FEATURE_COMPLETE</promise>` 정확 문자열 — `grep -qF`(정규식 금지) |

종료 허용 = **① ∧ ②ᴿ ∧ ②ᴱ ∧ ③**. 하나라도 미충족이면 훅이 exit 2로 차단하고 stderr로 미충족 사유·출력 tail을 재주입한다.

## 환경변수

| 변수 | 기본값 | 용도 |
|------|--------|------|
| `LOOP_TEST_CMD` | 미설정(`.planning/gate-cmd` 사용) | 결정론 게이트 명령 일시 강제(부분 테스트로 빠른 반복). 영구 변경은 gate-cmd 파일 |
| `LOOP_E2E_CMD` | 미설정(`.planning/e2e-gate-cmd` 사용) | E2E 게이트 명령 — all-passes 도달 시 1회. 영구 적용은 `.planning/e2e-gate-cmd` |
| `LOOP_PROMISE` | `<promise>FEATURE_COMPLETE</promise>` | 완료 약속문(정확 일치 대상). 변경 시 progress.md 기록 문자열도 일치시킬 것 |
| `LOOP_MAX_ITER` | `24` (권장: task 수 × 3) | 반복 상한. `/floop-run --max-iter <n>` 또는 env. 로드 순서: env > loop-state.json > 기본값 |
| `LOOP_MAX_MINUTES` | `120` | 시간 상한(`loop-state.json` `started_at` 대비). `/floop-run --max-minutes <n>` 또는 env |

> baseline 회귀 게이트는 별도 env가 없다 — `baseline.json` 파일이 곧 스위치다(있으면 적용, 없으면 미적용).

## loop-active 플래그 수명주기

`.planning/loop-active`(빈 파일)는 "루프 가동 중"의 유일한 스위치다.

1. **생성**: `/floop-run`만 생성. 훅·에이전트는 임의 생성 금지.
2. **안전핀**: Stop훅 최상단 `[ -f "$PLAN/loop-active" ] || exit 0` — 루프 미가동 세션 종료를 절대 방해하지 않는다($3600/day 과금 사고 대응).
3. **삭제**: 모든 종료 경로에서 훅이 삭제 — 정지조건 충족·max-iter·no-progress·시간 상한. `/floop-stop`도 즉시 삭제.
4. **잔존 시 수동 해제**: `/floop-status`가 잔존 여부 표시, 해제는 `rm .planning/loop-active` 한 줄. 진행 상태(tasks.json·progress.md)는 보존.

## 가드레일 5종

| 가드 | 기본값/트리거 | 동작 |
|------|--------------|------|
| max iterations | `LOOP_MAX_ITER=24` | 도달 시 exit 0 + 미완 보고 |
| no-progress | 실패 시그니처(숫자 토큰 제거 정규화 후 md5) 연속 2회 동일 | exit 0 + BLOCKED.md 기록 |
| 시간 상한 | `LOOP_MAX_MINUTES=120` | 초과 시 현 반복 완료 후 exit 0 + 재개 방법 보고 |
| 킬스위치 | `/floop-stop` (수동) | loop-active 삭제 → 훅 무력화, 핸드오프, 마스터 `status: paused` |
| circuit breaker | 동일 task 연속 3회 실패(오케스트레이터 정책 — progress.md 감지) | task skip + BLOCKED 기록 후 다음 |

발동 순서: 동일 실패 반복이면 no-progress(2회)가 max-iter보다 먼저 멈춘다. **회귀 실패(②ᴿ)도 fail_sig에 포함**되어 동일 회귀가 반복되면 no-progress가 작동한다.

## BLOCKED.md 양식과 에스컬레이션

```markdown
## [2026-06-13 14:30] T-03 차단
- 유형: no-progress | circuit-breaker | 회귀 | 테스트 정합성 | 스코프 결함 | 구조 한계
- iteration: 11 / 24
- 시도한 것: 시도별 접근과 결과 (각 1줄)
- 차단 원인: 실패 시그니처 또는 에러 요약 + 테스트 출력 tail
- 권장 다음 행동: 에스컬레이션 대상과 구체 제안
```

**에스컬레이션 분기:**

| 원인 유형 | 판단 신호 | 처치 |
|-----------|----------|------|
| 스코프 결함 | AC가 검증 불가, task 범위 비대(1반복 초과), 분해 오류 | **재분해 = `task-planner` 재투입** — tasks.json 수정. G1 승인 사항이므로 변경 요지 1줄 보고 |
| 구조 한계 | 기존 스택·레이어·의존성이 구현을 원천 차단, gate-cmd 부적합 | **스택 플러그인 가이드 참조**(kotlin-spring-guide 등) + 판단 불가 시 사용자 보고 |
| 회귀 고착 | 내 변경이 기존 동작을 깨는데 구현 수정으로 해소 불가 | 변경 범위 축소 재분해(TP) 또는 기존 코드 의존성 사용자 확인 |

빌더 재시도로 해결될 문제(단순 버그·플레이크)는 circuit breaker 이전까지 표준 사이클 안에서 해소한다.

## 테스트 삭제·약화 금지 (test-guard 훅 연계)

브라운필드에서 게이트 신뢰는 **기존 테스트 보존**이 전제다.

- **삭제 차단(결정론)**: PreToolUse `test-guard.sh`가 loop-active 존재 시 `rm` 대상의 test/spec 패턴을 exit 2 차단.
- **약화·역수정 적발(검증자)**: assertion 제거·skip·**기존 테스트 기대값 역수정**(회귀 은폐)은 `feature-verifier`가 반증 단계에서 적발 — 적발 시 마커 미생성.
- **정당한 수정 경로**: 테스트 자체가 잘못된 경우 삭제·우회가 아니라 BLOCKED.md에 사유 기록 후 feature-verifier 반증으로 "수정본이 여전히 AC를 검증함 + baseline 정합"을 확인받고 진행.

## References

- 루프 운영 개념 원전: harness 플러그인 `team-harness` 스킬의 `references/loop-harness-guide.md`
- Stage 전체 흐름·게이트 정책: 같은 플러그인 `feature-loop-orchestrator` 스킬
- 분해 표준: 같은 플러그인 `task-decomposition` 스킬
- 루프 엔진 구현: `${CLAUDE_PLUGIN_ROOT}/hooks/floop-loop-stop-hook.sh` (정지조건 4결합·가드레일)
- 가드 훅: `tasks-guard.sh`(마커 강제), `test-guard.sh`(테스트 삭제 차단), `gates/capture-baseline.sh`(기준선)
