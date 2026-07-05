---
name: mvp-loop-protocol
description: |
  MVP 개발 루프(Stage 4) 운영 프로토콜. 매 반복 표준 사이클(스토리 선택→메인 세션 구현→
  mvp-verifier 반증→verified 마커→passes:true→progress 갱신→일괄 커밋), /mvp-run 재개 프로토콜
  4단계, 정지조건 3결합(결정론 게이트+verified 마커+completion promise), 환경변수 튜닝
  (LOOP_TEST_CMD·LOOP_PROMISE·LOOP_MAX_ITER·LOOP_MAX_MINUTES), loop-active 플래그 수명주기,
  가드레일 5종, BLOCKED.md 에스컬레이션을 정의한다. /mvp-run으로 루프를 시작·재개할 때,
  중단된 루프를 복구할 때, 가드레일 기본값을 조정할 때, BLOCKED 상태를 처리할 때 참조.
  Operating protocol for the MVP dev loop (Stage 4): the per-iteration cycle, the /mvp-run
  resume protocol, stop conditions, env-var tuning (LOOP_TEST_CMD, LOOP_PROMISE,
  LOOP_MAX_ITER, LOOP_MAX_MINUTES), loop-active flag lifecycle, 5 guardrails, and BLOCKED.md
  escalation. Use when: starting or resuming via /mvp-run, recovering an interrupted loop,
  tuning guardrails, or handling BLOCKED state.
---

# MVP Loop Protocol

mvp-orchestrator의 Stage 4(개발 루프)를 운영하는 단일 규약. 루프 엔진은 Stop훅
(`${CLAUDE_PLUGIN_ROOT}/hooks/mvp-loop-stop-hook.sh`)이며, 완료 판정의 주체는 모델이 아니라
훅이다("Completion lives outside the model"). 이 스킬은 매 반복의 행동 순서, 중단·재개 절차,
정지조건과 가드레일의 동작·튜닝법을 규정한다.

## When to Apply

다음 상황에서 이 프로토콜을 참조한다:
- `/mvp-run`으로 개발 루프를 시작하거나, 중단된 루프를 재개할 때 (재개 프로토콜 4단계)
- 루프가 가드레일(max-iter·no-progress·시간 상한)로 멈췄거나 `status: paused`에서 복구할 때
- `LOOP_MAX_ITER`·`LOOP_MAX_MINUTES` 등 가드레일 기본값을 프로젝트 규모에 맞게 튜닝할 때
- 스토리가 BLOCKED 처리되어 에스컬레이션(스코프 재협상 vs 구조 재설계)을 판단할 때
- `loop-active` 플래그가 잔존하여 세션 종료가 비정상적으로 차단될 때 (수동 해제)
- prd-guard·test-guard 훅이 작업을 차단(exit 2)한 이유를 해석할 때

## .planning/ 메모리 레이아웃

상태는 컨텍스트가 아니라 디스크에 둔다. 모든 경로는 프로젝트 루트 기준 상대경로다.

```
.planning/
├── mvp-{id}.md       # 마스터: ## Goal(불변) / ## Stage / ## Gates(승인 스탬프) / ## Checklist
│                     #        / ## Iteration / ## Feedback + status: in_progress|paused|blocked|done
├── prd.md            # G1 승인본
├── prd.json          # {"stories":[{"id":"S-01","title":...,"acceptance":[...],"passes":false}]}
├── design-spec.md    # [story: S-xx] 태그
├── stack-decision.md # G2 기록(후보·트레이드오프·선택·근거)
├── gate-cmd          # 결정론 게이트(단위/통합) 명령 1줄(tech-architect 기록, 훅이 로드)
├── e2e-gate-cmd      # (선택) E2E 수용 게이트 명령 1줄 — 있으면 all-passes 도달 시 1회 실행, 없으면 미적용
├── progress.md       # 반복 로그 1줄/회 + <promise>MVP_COMPLETE</promise>
├── loop-state.json   # {iteration, last_fail_sig, started_at(epoch 초), max_iter, max_minutes}
├── loop-active       # 루프 가동 플래그(빈 파일) — /mvp-run 생성, 훅 종료 경로에서 삭제
├── verified/         # mvp-verifier 승인 마커 S-01, S-02 ...
└── BLOCKED.md        # 시도·차단 원인·권장 다음 행동
```

## 매 반복 표준 사이클

한 반복 = 스토리 정확히 1개. 단계와 산출 파일을 건너뛰거나 순서를 바꾸지 않는다.

| # | 단계 | 수행 주체 | 명령·파일 |
|---|------|----------|-----------|
| 1 | 스토리 선택 | 메인 세션 | `jq -r '[.stories[] \| select(.passes == false)][0].id' .planning/prd.json` — 미완(passes:false) 최우선 스토리 **1개만** |
| 2 | 구현 | 메인 세션(`mvp-builder` 규율 체화) | 테스트 먼저 → 최소 구현 → `.planning/gate-cmd`의 명령으로 게이트 그린 확인. **passes 직접 마킹 금지**. 예외: 병렬 feature 구현 시에만 `mvp-builder`를 worktree 격리 서브에이전트로 디스패치(코드 작성까지만 — 커밋·마킹은 메인 세션 통합 시) |
| 3 | 반증 | `mvp-verifier` 디스패치 | AC 반증 시도: 엣지케이스 직접 실행, 테스트가 AC를 실제 검증하는지, assertion 약화·skip·삭제 사기 적발, gate-cmd 독립 재실행 |
| 4 | verified 마커 | `mvp-verifier` | 반증 **실패 시에만** `.planning/verified/{story-id}` 생성(내용 = 반증 시도 요약). 반증 성공 시 마커 없이 지적 사항 반환 → 2단계로 회귀 |
| 5 | passes:true | 메인 세션 | 마커 확인 후 `.planning/prd.json`의 해당 스토리 `passes`를 true로 갱신. prd-guard 훅(PostToolUse)이 마커 존재를 재검사 — 없으면 jq로 false 되돌림 + exit 2 |
| 6 | progress 갱신 | 메인 세션 | `.planning/progress.md`에 1줄 추가: `iter N \| S-xx verified \| passes n/m`. 마스터 파일 Checklist·Iteration·Feedback도 동기 갱신 |
| 7 | 커밋 | 메인 세션 | `git add -A && git commit -m "feat(mvp): S-xx <변경 요지>"` — **커밋 1회에 구현+prd.json+progress.md 일괄 포함**, descriptive 커밋, 스토리 id 필수 |

전 스토리 `passes:true` 도달 시 **(E2E 수용 게이트 적용 프로젝트)**: promise 기록 전에 먼저
`.planning/e2e-gate-cmd`(또는 `/e2e`)를 직접 실행해 전체 유저플로우가 동작하는지 확인한다.
- E2E 그린 → progress.md 마지막 줄에 `<promise>MVP_COMPLETE</promise>`를 정확히 기록(앞뒤 변형 금지)하고 마스터 `status: done`으로 전환 → Stop훅이 정지조건(① ∧ ②ᴱ ∧ ③)을 재검사하고 종료를 허용한다.
- E2E 레드 → promise를 기록하지 않는다. 깨진 플로우를 커버하는 스토리를 보완(필요 시 PS에 E2E 스토리 추가 요청)해 다시 단위 그린 → E2E 그린을 만든다. 성급히 promise를 적어도 Stop훅이 E2E 재검사로 종료를 차단한다.

E2E 게이트 미적용(`e2e-gate-cmd` 없음) 프로젝트는 전 스토리 `passes:true` 도달 즉시 promise를
기록하면 된다(기존 동작과 동일). promise 정확 기록 + 마스터 `status: done` 후 Stop훅이 종료를 허용한다.

## 재개 프로토콜 (4단계)

루프가 어떤 이유로든 끊긴 뒤(`/mvp-run` 재실행, 새 세션, SessionStart 훅의 재개 안내),
compaction된 기억에 의존하지 말고 매번 아티팩트에서 이해를 재생성한다:

1. **마스터 읽기** — `.planning/mvp-{id}.md`를 읽어 `status: in_progress`면 복구 모드 진입.
   `paused`면 `/mvp-stop` 이력 확인 후 사용자 의사 확인(단 `/mvp-run` 명시 호출은 재개 의사로
   간주, 별도 확인 생략), `blocked`면 BLOCKED.md부터 읽는다. `BLOCKED.md`가 존재하면 status와
   무관하게 blocked로 간주 — 요약을 제시하고 해소를 확인한 뒤 진행한다.
2. **이력 파악** — `git log --oneline -10` + `.planning/progress.md`로 직전 진행 지점과
   마지막 커밋 스토리를 파악한다 (git history = 상태).
3. **미완 스토리 1개 선택** — 표준 사이클 1단계와 동일한 jq 질의. 한 번에 하나만.
4. **작업·갱신** — 표준 사이클 2~7단계 수행: 작업→검증→마커→커밋→progress·Checklist·Feedback
   갱신. 다음 세션을 위한 깨끗한 핸드오프를 남긴다.

## 정지조건 3결합 (판정 주체 = Stop훅)

| # | 조건 | 검사 방식 |
|---|------|-----------|
| ① | 결정론 게이트 | `.planning/gate-cmd` 파일에서 명령 동적 로드(`LOOP_TEST_CMD` env가 있으면 그것이 우선) → **exit code 우선 판정**(출력의 `grep -Ei 'fail\|error'`는 보조 시그널 — exit 0인데 grep만 매칭되면 오탐 방지를 위해 통과로 본다) **AND** `jq -e '[.stories[].passes] \| all' .planning/prd.json`. all-passes 확인 시 passes==true인 각 id의 `.planning/verified/{id}` 마커 존재까지 재검사 — 마커 없는 passes:true 발견 시 미충족(exit 2)으로 해당 id와 "mvp-verifier 반증을 통과시켜 마커를 생성하라" 안내를 재주입(prd-guard가 못 잡는 Bash 리다이렉션 우회의 최종 방어선) |
| ② | 회의적 Evaluator | passes:true 전환은 mvp-verifier의 `.planning/verified/{story-id}` 마커가 선행 필수. PostToolUse 훅 `prd-guard.sh`가 마커 없는 마킹을 exit 2로 차단하고 jq로 false 되돌림. **Evaluator의 확률적 판정을 파일 마커로 물화해 결정론 검사로 변환**한 것이 이 설계의 핵심 |
| ②ᴱ | E2E 수용 게이트(선택) | `.planning/e2e-gate-cmd`(또는 `LOOP_E2E_CMD` env)가 있으면 **all-passes 도달 시점에만 1회** 실행 → exit 0 그린 필수. 파일 없으면 미적용(통과 간주, 회귀 0). 전체 유저플로우의 최종 동작 보증 — 단위 게이트가 못 잡는 통합 실패를 끝물에 차단 |
| ③ | Completion promise | `.planning/progress.md`에 `<promise>MVP_COMPLETE</promise>` 정확 문자열 존재 — `grep -qF` 검사(정규식 금지) |

종료 허용 = **① ∧ ②ᴱ ∧ ③**. ②(마커)는 별도 평가 항목이 아니라 ①의 all-passes 검사에 전제로
인입된다(passes:true가 되려면 마커가 반드시 선행하므로). ②ᴱ는 e2e-gate-cmd가 없으면 자동 통과라
기존 동작에 영향이 없다. 하나라도 미충족이면 훅이 exit 2로 종료를 차단하고 stderr로 미충족
사유·테스트/E2E 출력 tail을 재주입한다.

## 환경변수

| 변수 | 기본값 | 용도 | 오버라이드 방법 |
|------|--------|------|-----------------|
| `LOOP_TEST_CMD` | 미설정 (`.planning/gate-cmd` 사용) | 결정론 게이트(단위/통합) 명령을 일시적으로 강제 지정 (예: 부분 테스트로 빠른 반복) | 세션 시작 전 셸에서 `export LOOP_TEST_CMD="pytest -q tests/unit"`. 영구 변경은 env가 아니라 gate-cmd 파일 수정 |
| `LOOP_E2E_CMD` | 미설정 (`.planning/e2e-gate-cmd` 사용, 없으면 E2E 미적용) | E2E 수용 게이트 명령 지정 — all-passes 도달 시 1회 실행. 비대화형·exit code 필수 | `export LOOP_E2E_CMD="npx playwright test"`. 영구 적용은 `.planning/e2e-gate-cmd` 파일에 1줄 기록 |
| `LOOP_PROMISE` | `<promise>MVP_COMPLETE</promise>` | 완료 약속문(정확 문자열 일치 대상) | `export LOOP_PROMISE=...` — 변경 시 progress.md 기록 문자열도 반드시 일치시킬 것 |
| `LOOP_MAX_ITER` | `24` (권장: 스토리 수 × 3) | 반복 상한 — 무한 spin 차단 | `/mvp-run --max-iter <n>`(`loop-state.json`의 `max_iter` 필드에 기록) 또는 `export LOOP_MAX_ITER=<n>`. 훅 로드 순서: env > loop-state.json 필드 > 기본값 |
| `LOOP_MAX_MINUTES` | `120` | 시간 상한 — `loop-state.json`의 `started_at`(epoch 초) 대비 경과 분 | `/mvp-run --max-minutes <n>`(`loop-state.json`의 `max_minutes` 필드에 기록) 또는 `export LOOP_MAX_MINUTES=<n>`. 훅 로드 순서: env > loop-state.json 필드 > 기본값 |

튜닝 지침: 스토리 8개 MVP라면 `--max-iter 24`(기본)가 적정. 스토리 10개 이상 대형 MVP는
단일 세션 컨텍스트 비대를 피해 headless 레시피(mvp-orchestrator의
`references/headless-recipe.md`) 전환을 권장 — 동일 게이트·동일 `.planning/`을 공유하므로
엔진을 바꿔도 정지조건은 불변이다.

## loop-active 플래그 수명주기

`.planning/loop-active`(빈 파일)는 "루프 가동 중"의 유일한 스위치다.

1. **생성**: `/mvp-run`만 생성한다. 훅·에이전트가 임의 생성하지 않는다.
2. **안전핀**: Stop훅 최상단 `[ -f "$PROJ/.planning/loop-active" ] || exit 0` — 루프 미가동
   세션의 종료를 절대 방해하지 않는다(무한 재주입으로 인한 $3600/day 과금 사고 대응).
3. **삭제**: 모든 종료 경로에서 훅이 삭제한다 — 정지조건 충족·max-iter 도달·no-progress 감지·
   시간 상한 초과. `/mvp-stop`(킬스위치)도 즉시 삭제한다.
4. **잔존 시 수동 해제**: 훅 타임아웃·강제 종료 등으로 플래그가 남으면 다음 세션에서 종료가
   계속 차단될 수 있다. `/mvp-status`가 잔존 여부를 보여주며, 해제는
   `rm .planning/loop-active` 한 줄이다. 삭제해도 진행 상태(prd.json·progress.md)는 보존된다.

## 가드레일 5종

| 가드 | 기본값/트리거 | 동작 |
|------|--------------|------|
| max iterations | `LOOP_MAX_ITER=24` (권장: 스토리 수×3) | 도달 시 exit 0 + 미완 상태 보고. promise만으론 부족(과제가 어려우면 무한 spin) |
| no-progress | 실패 시그니처(fail/error 라인에서 숫자 토큰 제거 정규화 후 md5) 연속 2회 동일 — 소요시간 등 숫자 비결정 출력에 대응하되, 그 외 비결정 문자열이 섞이면 max-iter가 backstop | exit 0 + BLOCKED.md에 iteration·시그니처·테스트 출력 tail 기록 |
| 시간 상한 | `LOOP_MAX_MINUTES=120` (`loop-state.json` `started_at` 대비) | 초과 시 현 반복 완료 후 exit 0 + 재개 방법(`/mvp-run`) 보고 |
| 킬스위치 | `/mvp-stop` (사용자 수동) | loop-active 삭제 → 훅 즉시 무력화, 핸드오프 기록, 마스터 `status: paused` |
| circuit breaker | 동일 스토리 연속 3회 실패 (훅이 아닌 오케스트레이터 정책 — progress.md 로그로 감지) | 해당 스토리 skip + BLOCKED.md 기록 후 다음 미완 스토리로 진행 |

발동 순서: 실패가 **동일하게** 반복되면 no-progress(2회)가 max-iter보다 먼저 멈춘다.
실패 양상이 매번 달라지는 경우에만 max-iter가 backstop으로 작동한다. 둘 다 있어야
"stuck"과 "느린 진전" 양쪽을 막는다.

## BLOCKED.md 양식과 에스컬레이션

차단이 발생하면(no-progress·circuit breaker·test-guard 차단·구조적 한계) 아래 양식으로
`.planning/BLOCKED.md`에 누적 기록한다(기존 항목 삭제 금지):

```markdown
## [2026-06-12 14:30] S-03 차단
- 유형: no-progress | circuit-breaker | 테스트 정합성 | 스코프 결함 | 구조적 한계
- iteration: 11 / 24
- 시도한 것: 시도별 접근과 결과 요약 (각 1줄)
- 차단 원인: 실패 시그니처 또는 에러 요약 + 테스트 출력 tail
- 권장 다음 행동: 에스컬레이션 대상과 구체적 제안
```

**에스컬레이션 분기** — 차단의 근본 원인으로 판단한다:

| 원인 유형 | 판단 신호 | 처치 |
|-----------|----------|------|
| 스코프 결함 | AC가 검증 불가능, 스토리 범위 비대(1반복 초과), 페르소나-스토리 불일치 | **스코프 재협상 = `product-strategist` 재투입** — prd.md·prd.json 수정. 스코프는 G1 승인 사항이므로 변경 요지를 사용자에게 1줄 보고 후 반영 |
| 구조적 한계 | 스택·레포 골격·아키텍처가 스토리 구현을 원천 차단(의존성 충돌, 골격 결함, gate-cmd 부적합) | **구조 재설계 = `tech-architect` 단독 재투입** — 골격·gate-cmd 보수 후 게이트 그린 재확인, 루프 복귀 |

빌더 재시도로 해결될 문제(단순 버그·플레이크)는 에스컬레이션 대상이 아니다 — circuit breaker
이전까지는 표준 사이클 안에서 해소한다.

## 테스트 삭제·약화 금지 (test-guard 훅 연계)

루프의 결정론 게이트는 테스트가 신뢰할 수 있을 때만 의미가 있다. 게이트를 "통과시키기 위해"
테스트를 건드리는 것은 사기다.

- **삭제 차단(결정론)**: PreToolUse 훅 `test-guard.sh`가 loop-active 존재 시
  `rm` 대상에 비알파벳 경계의 `test|spec` 패턴(`tests/` 디렉토리, `.spec.` 파일 등)이 포함된
  Bash 명령을 exit 2로 차단한다. 경계 검사로 `latest.log` 류는 오탐하지 않으며, 그 외 오탐 시
  사유를 사용자에게 1줄 보고하고 확인 후 진행한다.
- **약화 적발(검증자)**: assertion 제거·완화, `skip`/`xit`/`@Disabled` 처리, 기대값을 구현
  출력에 맞춰 역수정하는 행위는 `mvp-verifier`가 반증 단계에서 적발하며, 적발 시 verified
  마커를 생성하지 않는다(passes 전환 불가).
- **정당한 테스트 수정 경로**: 테스트 자체가 잘못된 경우 삭제·우회가 아니라 BLOCKED.md에
  사유를 기록하고, 수정본이 여전히 해당 스토리의 AC를 검증함을 mvp-verifier 반증으로
  확인받은 뒤 진행한다.

## References

- 루프 운영 개념·레시피 원전: utils/harness `team-harness` 스킬의 `references/loop-harness-guide.md`
- Stage 전체 흐름·게이트 정책: 같은 플러그인의 `mvp-orchestrator` 스킬
- 루프 엔진 구현: `${CLAUDE_PLUGIN_ROOT}/hooks/mvp-loop-stop-hook.sh` (정지조건 3결합·가드레일)
- 가드 훅: `${CLAUDE_PLUGIN_ROOT}/hooks/prd-guard.sh` (마커 강제), `${CLAUDE_PLUGIN_ROOT}/hooks/test-guard.sh` (테스트 삭제 차단)
