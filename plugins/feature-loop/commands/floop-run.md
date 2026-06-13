---
name: floop-run
description: "feature-loop 개발 루프(Stage C) 시작/재개 — 마스터 파일 status 기반 재개 프로토콜 수행 후 loop-active 플래그와 loop-state.json을 초기화하고 Stop훅 루프 엔진에 진입. 정지조건 4결합(결정론 게이트+baseline 회귀+verified 마커+completion promise)은 훅이 판정"
category: workflow
complexity: advanced
mcp-servers: []
personas: []
---

# /floop-run - 개발 루프 시작/재개

`/floop-new`가 만든 `.planning/` 산출물 위에서 회귀 안전 개발 루프(Stage C)를 가동한다.
완료 판정의 주체는 모델이 아니라 하네스 — Stop훅 루프 엔진(`floop-loop-stop-hook.sh`)이 매 반복마다
정지조건 4결합(① gate-cmd 그린 ∧ jq all-passes ②ᴿ baseline 회귀 0 ② verified 마커 ③ `<promise>FEATURE_COMPLETE</promise>`)을
검증하고, 미충족 시 exit 2 재주입으로 루프를 지속시킨다. 매 반복 사이클은 `floop-loop-protocol` 스킬을 따른다.

## Triggers
- `/floop-new` 완료 후 Stage C 개발 루프를 처음 가동할 때
- `/floop-stop`·가드레일(max-iter/no-progress/시간 상한)로 중단된 루프를 재개할 때
- 세션이 끊긴 feature-loop 작업을 `.planning/` 아티팩트 기반 재개 프로토콜로 이어갈 때
- 반복 수·시간 상한을 이번 가동에 한해 조정해 루프를 돌리고 싶을 때

## Usage
```
/floop-run [옵션]

Options:
  --max-iter <n>      이번 가동의 최대 반복 수 — loop-state.json max_iter 필드에 기록 (기본 24, 권장: task 수×3)
  --max-minutes <n>   이번 가동의 시간 상한(분) — loop-state.json max_minutes 필드에 기록 (기본 120, started_at(epoch 초) 대비)
```

## Behavioral Flow

### Phase 1: 마스터 파일 status 분기
1. **감지**: `.planning/floop-*.md` Glob — **미존재 시 루프를 만들지 않고 `/floop-new` 진입을 안내하고 종료**
2. **분기**:
   - `status: done` → 완료 상태 보고 후 종료 (재가동 없음)
   - `status: blocked` 또는 **BLOCKED.md 존재(status 무관 blocked로 간주)** → BLOCKED.md(시도·차단 원인·권장 다음 행동) 요약 제시, 사용자 결정(재분해=task-planner / 구조 한계=스택 가이드 / 그대로 재개)으로 해소 확인 후 진행
   - `status: paused` 또는 `in_progress` → Phase 2 재개 프로토콜
3. **사전 산출물 확인**: `.planning/tasks.json`·`gate-cmd` 미존재(분해 미완)면 `/floop-new`로 Stage A~B를 먼저 끝내도록 안내. `baseline.json` 미존재면 회귀 게이트 미적용 경고 + capture-baseline 1회 실행 권고

### Phase 2: 재개 프로토콜 (compaction 의존 금지 — 아티팩트에서 이해 재생성)
1. **마스터 읽기**: Goal·Stage·Gates·Checklist·Iteration·Feedback 복구 (in_progress → 복구 모드)
2. **이력 확인**: `git log --oneline -10` + progress.md 반복 로그로 마지막 작업 지점 파악
3. **대상 확정**: tasks.json에서 미완(`passes:false`) 최우선 task **1개** 식별, verified/ 마커와 대조

### Phase 3: 루프 가동 준비
1. **플래그 생성**: `touch .planning/loop-active` — Stop훅 안전핀 해제(이 파일이 있어야만 훅이 동작)
2. **상태 초기화**: loop-state.json 기록 — 신규 가동 시 `{"iteration":0,"last_fail_sig":"","started_at":<date +%s>,"max_iter":24,"max_minutes":120}` (`started_at`은 epoch 초), 재가동 시 `started_at` 갱신
3. **옵션 반영**: `--max-iter`/`--max-minutes`를 loop-state.json의 `max_iter`/`max_minutes`에 기록 (미지정 시 기본 24/120 — Stop훅은 env > loop-state.json > 기본값 순 로드)

### Phase 4: 루프 진입 안내 및 첫 반복 착수
1. **가동 보고**: 대상 task·잔여 n/m·baseline 상태(green/red fail_count)·가드레일 설정(max-iter/시간 상한/no-progress 2회/circuit breaker 3회/킬스위치 `/floop-stop`)을 1화면 보고
2. **사이클 시작**: `floop-loop-protocol` 표준 사이클로 진입 — task 선택 → 테스트 먼저 → 최소 구현(스택 플러그인 활용, 여기까지 메인 세션이 feature-builder 규율 체화) → 게이트 그린+회귀 0 → `feature-verifier` 반증(통과까지 수정 반복) → verified 마커 → passes:true 갱신(메인 세션) → **커밋 1회**(구현+tasks.json+progress.md 일괄, `feat: T-xx ...`) — 이후 종료 시도마다 Stop훅이 정지조건을 판정

## Tool Coordination
- **Glob/Read**: `.planning/floop-*.md`·tasks.json·baseline.json·progress.md·BLOCKED.md·verified/ 판독 (재개 프로토콜)
- **Bash**: `touch .planning/loop-active`, `git log --oneline -10`, jq로 미완 task 질의
- **Write**: loop-state.json 초기화/갱신
- **Task**: feature-verifier(반증)만 매 task 디스패치 — 구현은 메인 세션이 feature-builder 규율 체화(서브에이전트 디스패치는 병렬 worktree 시에만)
- **Skill**: `floop-loop-protocol` — 반복 사이클·재개 프로토콜·env 표의 기준 문서

## Examples

### 최초 가동
```
/floop-run
# .planning/floop-signup.md status: in_progress, tasks.json 존재 → 재개 프로토콜
# loop-active 생성, loop-state.json {"iteration":0,...,"started_at":1781224200,"max_iter":24,"max_minutes":120}
# 대상: T-01 (passes:false 최우선) — baseline: green / 가드레일: 24회 / 120분
# 루프 진입: 이후 종료 시도는 Stop훅이 정지조건 4결합으로 판정
```

### 중단된 루프 재개 (상한 조정)
```
/floop-run --max-iter 12 --max-minutes 60
# status: paused → 핸드오프(progress.md)와 git log로 마지막 지점 복구
# started_at 갱신, max_iter=12 / max_minutes=60 기록
# 미완 task T-03부터 사이클 재개
```

### 산출물 없는 레포에서 호출
```
/floop-run
# .planning/floop-*.md 미존재 → 루프 미가동
# "/floop-new \"<기능 요청>\"로 Stage A~B를 먼저 완료하세요" 안내 후 종료
```

## Boundaries

**Will:**
- 마스터 파일 status(미존재/done/blocked/paused/in_progress)별로 정확히 분기
- 재개 프로토콜로 아티팩트에서 작업 맥락을 재생성한 뒤에만 루프 가동
- loop-active·loop-state.json을 초기화하고 가드레일·baseline 상태를 보고한 뒤 표준 사이클 진입
- 미완(passes:false) 최우선 task 1개만 대상으로 반복 (한 반복 = 한 task)

**Will Not:**
- `.planning/` 산출물(tasks.json·gate-cmd) 없이 루프 가동 (→ `/floop-new` 안내)
- 정지조건·완료 판정을 모델 스스로 수행 (판정 주체는 Stop훅 루프 엔진)
- passes 직접 마킹(verified 마커 선행 필수 — tasks-guard 훅 차단), 테스트 삭제·약화
- status: done인 작업의 재가동

## Related
- `floop-loop-protocol` — 반복 사이클·재개 프로토콜·env 표·BLOCKED 에스컬레이션
- `feature-loop-orchestrator` — Stage 상태기계·Guardrails·Error Handling
- `/floop-stop` — 수동 킬스위치 (loop-active 삭제 + 핸드오프 + paused)
- `/floop-status` — 가동 전 현황 확인 (읽기 전용)
