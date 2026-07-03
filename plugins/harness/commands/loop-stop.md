---
name: loop-stop
description: "generic 경량 루프 안전 중단(킬스위치) — loop-active(engine=generic) 삭제로 Stop훅 루프 엔진을 즉시 무력화하고, 목표·iteration·마지막 게이트 결과를 progress.md에 핸드오프 기록. 타 엔진(mvp/floop) 소유 loop-active는 건드리지 않고 해당 킬스위치를 안내. 가드레일과 별개의 수동 중단 수단"
category: workflow
complexity: basic
mcp-servers: []
personas: []
---

# /loop-stop - 경량 루프 안전 중단 (킬스위치)

`/loop-run`으로 가동한 generic 루프를 사용자 주도로 안전하게 멈춘다. 이 커맨드는 **가드레일과 별개의
수동 킬스위치**다 — max-iter(12)·no-progress(2회)·시간 상한(60분)은 루프 엔진이 자동으로 거는
안전장치이고, `/loop-stop`은 그와 무관하게 사용자가 언제든 즉시 내릴 수 있는 중단 수단이다.
`loop-active`가 삭제되면 Stop훅 최상단 안전핀이 작동해 이후 세션 종료가 더 이상 재주입되지 않는다.
engine 스코프 공유 계약에 따라 **engine=generic인 loop-active만 삭제**한다 — mvp/floop 루프는
각자의 킬스위치(`/mvp-stop`·`/floop-stop`)로만 해제한다.

## Triggers
- 가동 중인 generic 루프를 지금 즉시 멈추고 싶을 때 (사유 불문)
- 루프가 의도와 다른 방향으로 진행되어 가드레일 발동을 기다리지 않고 개입해야 할 때
- 단발 반복으로 시작한 작업이 커져 `/floop-new`(작업 분해)로 승격하기 전 정리할 때
- 비정상 종료 후 잔존한 `engine=generic` loop-active를 정리할 때

## Usage
```
/loop-stop

옵션 없음 — 호출 즉시 킬스위치·핸드오프 기록을 수행한다. 멱등 동작(이미 중단 상태면 정돈만 수행).
```

## Behavioral Flow

### Phase 1: 가동 상태와 소유권 확인
1. **감지**: `.planning/loop-active` 존재 확인 — 없으면 "루프 미가동" 1줄 보고 후 Phase 3 정돈만 계속
2. **engine 판독**: loop-active의 engine 줄 확인 —
   - `engine=generic`: 본 커맨드 소유 — Phase 2 진행
   - `engine=mvp`/`engine=floop` 또는 engine 줄 없음(레거시 = mvp/floop 소유): **삭제하지 않고** `/mvp-stop`·`/floop-stop` 안내 후 종료
3. **현 지점 파악**: loop-goal.md·loop-state.json·progress.md에서 목표·iteration·마지막 게이트 결과(gate-cmd)를 수집 — 핸드오프 기록의 재료

### Phase 2: 킬스위치 — loop-active 삭제
1. **플래그 삭제**: `rm .planning/loop-active` — Stop훅 안전핀(`[ -f .planning/loop-active ] || exit 0`)에 의해 루프 엔진 즉시 무력화, 이후 세션 종료가 방해받지 않음
2. **멱등 처리**: 이미 없으면(가드레일 종료·이전 중단) 삭제 없이 다음 단계 계속

### Phase 3: 핸드오프 기록과 보고
1. **progress.md 기록**: 중단 핸드오프를 남김 — 목표(loop-goal.md 1행)·iteration/max_iter·마지막 게이트(gate-cmd) 결과·권장 다음 행동 1줄
2. **미커밋 변경 안내**: `git status`로 미커밋 변경이 있으면 그대로 보존하고 핸드오프에 명시 (커밋·되돌리기 어느 쪽도 임의 수행하지 않음)
3. **재가동 안내**: 재개는 `/loop-run "<목표>" --gate-cmd "<명령>"` 재호출 — loop-state.json이 남아 있으면 iteration이 이어진다. 작업이 구조적이면 `/floop-new` 승격을 함께 안내

## Tool Coordination
- **Read**: loop-active(engine 줄)·loop-goal.md·loop-state.json·progress.md 판독 (소유권·현 지점 파악)
- **Bash**: `rm .planning/loop-active` (engine=generic일 때 단일 파일 삭제만), `git status` 미커밋 변경 확인
- **Write**: progress.md 핸드오프 라인 추가

## Examples

### 가동 중 generic 루프 즉시 중단
```
/loop-stop
# loop-active 내용 engine=generic 확인 → 삭제 → Stop훅 즉시 무력화
# 핸드오프: "목표 'ESLint 에러 0', iteration 4/12, gate-cmd 마지막 실행 red(에러 3건) — 다음: no-unused-vars 3건 수정"
# 재가동: /loop-run "<목표>" --gate-cmd "<명령>"
```

### 타 엔진 루프에서 호출 (비침범)
```
/loop-stop
# loop-active 내용: engine=floop → 삭제하지 않음
# "feature-loop 루프 가동 중 — 해제는 /floop-stop" 안내 후 종료
```

### 이미 중단된 상태에서 호출 (멱등)
```
/loop-stop
# loop-active 없음 → "루프 미가동" 1줄 보고
# loop-state.json 잔존 시 현황(마지막 iteration)만 요약, 잔존물 삭제 없이 종료
```

## Boundaries

**Will:**
- `engine=generic` loop-active 삭제로 generic 루프 엔진을 즉시 무력화 (가드레일과 별개의 수동 킬스위치)
- 목표·iteration·마지막 게이트 결과·다음 행동을 progress.md에 핸드오프 기록
- 멱등 동작 — 이미 중단된 상태에서도 안전하게 정돈만 수행
- 작업이 커진 경우 `/floop-new` 승격 안내

**Will Not:**
- 타 엔진(engine=mvp/floop/레거시) 소유 loop-active 삭제 (해제는 `/mvp-stop`·`/floop-stop` 몫)
- 코드·테스트·gate-cmd 변경 (중단은 보존이지 되돌리기가 아님)
- 미커밋 변경의 임의 커밋 또는 폐기 (보존 후 핸드오프에 명시만)
- `.planning/` 산출물 삭제 — 삭제 대상은 `loop-active` 단일 플래그 파일뿐

## Related
- `/loop-run` — 경량 루프 가동/재가동 (engine=generic 기록)
- `/mvp-stop`·`/floop-stop` — 타 엔진 루프의 킬스위치 (engine 스코프 공유 계약)
- `skills/flow-validation/references/loop-rules.md` — LOOP-005 (가드레일 3종+킬스위치 해제 경로)
