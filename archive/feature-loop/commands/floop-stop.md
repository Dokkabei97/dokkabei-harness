---
name: floop-stop
description: |
  feature-loop 루프 안전 중단(킬스위치) — loop-active 삭제로 Stop훅 루프 엔진을 즉시 무력화하고, 현 task 상태를 progress.md에 핸드오프 기록한 뒤 마스터 status를 paused로 전환. 가드레일과 별개의 수동 중단 수단
  Kill switch for the feature-loop loop: deletes loop-active to instantly disarm the Stop-hook loop engine, records the current task state to progress.md as a handoff, then flips the master status to paused. Use when: stopping, pausing, or cancelling a running feature loop safely — a manual stop mechanism independent of the automatic guardrails.
category: workflow
complexity: basic
mcp-servers: []
personas: []
---

# /floop-stop - 루프 안전 중단 (킬스위치)

가동 중인 Stage C 개발 루프를 사용자 주도로 안전하게 멈춘다. 이 커맨드는 **가드레일과 별개의 수동
킬스위치**다 — max-iter(24)·no-progress(2회)·시간 상한(120분)은 루프 엔진이 자동으로 거는 안전장치이고,
`/floop-stop`은 그와 무관하게 사용자가 언제든 즉시 내릴 수 있는 중단 수단이다. `loop-active`가 삭제되면
Stop훅 최상단 안전핀이 작동해 이후 세션 종료가 더 이상 재주입되지 않는다.

## Triggers
- 가동 중인 루프를 지금 즉시 멈추고 싶을 때 (회의·퇴근·방향 전환 등 사유 불문)
- 루프가 의도와 다른 방향으로 진행되어 가드레일 발동을 기다리지 않고 개입해야 할 때
- 재분해·구조 재검토 등 루프 밖 의사결정을 먼저 하고 싶을 때
- 비정상 종료 후 잔존한 `loop-active`를 정리하고 상태를 paused로 정돈할 때

## Usage
```
/floop-stop

옵션 없음 — 호출 즉시 킬스위치·핸드오프·paused 전환을 수행한다. 멱등 동작(이미 중단 상태면 정돈만 수행).
```

## Behavioral Flow

### Phase 1: 가동 상태 확인
1. **감지**: `.planning/floop-*.md`와 `loop-active` 존재 확인 (마스터 미존재 시 "중단할 feature-loop 없음" 보고 후 종료)
2. **현 지점 파악**: tasks.json·progress.md·loop-state.json에서 작업 중이던 task(T-xx)·iteration·마지막 게이트/회귀 결과를 수집 — 핸드오프 재료

### Phase 2: 킬스위치 — loop-active 삭제
1. **플래그 삭제**: `rm .planning/loop-active` — Stop훅 안전핀(`[ -f .planning/loop-active ] || exit 0`)에 의해 루프 엔진 즉시 무력화
2. **멱등 처리**: `loop-active`가 이미 없으면 "루프 미가동" 1줄 보고 후 Phase 3~4 정돈만 계속

### Phase 3: 핸드오프 기록
1. **progress.md 기록**: 현 task 상태를 핸드오프로 남김 — task id·진행 정도(테스트 작성/구현/검증 중)·마지막 gate-cmd 결과·baseline 회귀 여부·verified 마커 여부·권장 다음 행동 1줄
2. **미커밋 변경 안내**: `git status`로 미커밋 변경이 있으면 그대로 보존하고 핸드오프에 명시 (커밋·되돌리기 어느 쪽도 임의 수행하지 않음)

### Phase 4: 상태 전환과 보고
1. **마스터 갱신**: `status: paused` 전환, `## Iteration`에 중단 시점 기록
2. **재개 안내**: 중단 요약(task n/m·iteration·핸드오프 위치)과 재개 방법(`/floop-run`) 보고

## Tool Coordination
- **Glob/Read**: 마스터·tasks.json·progress.md·loop-state.json 판독 (현 지점 파악)
- **Bash**: `rm .planning/loop-active` (단일 파일 삭제만), `git status` 미커밋 변경 확인
- **Edit**: 마스터 파일 `status: paused` 전환·Iteration 기록
- **Write**: progress.md 핸드오프 라인 추가

## Examples

### 가동 중 루프 즉시 중단
```
/floop-stop
# loop-active 삭제 → Stop훅 즉시 무력화
# 핸드오프: "T-03 구현 중(테스트 2/3 그린), gate-cmd 마지막 실행 ⚠️ 회귀 1건, verified 마커 없음 — 다음: 회귀 테스트 1건 수정"
# 마스터 status: paused / 재개: /floop-run
```

### 이미 중단된 상태에서 호출 (멱등)
```
/floop-stop
# loop-active 없음 → "루프 미가동" 1줄 보고
# status가 in_progress로 남아 있으면 paused로 정돈 + 핸드오프 보강
```

## Boundaries

**Will:**
- `loop-active` 삭제로 루프 엔진을 즉시 무력화 (가드레일 자동 종료와 별개의 수동 킬스위치)
- 현 task 상태·마지막 게이트/회귀 결과·다음 행동을 progress.md에 핸드오프 기록
- 마스터 `status: paused` 전환과 재개 방법 보고
- 멱등 동작 — 이미 중단된 상태에서도 안전하게 정돈만 수행

**Will Not:**
- 코드·테스트·tasks.json·verified 마커 변경 (중단은 보존이지 되돌리기가 아님)
- 미커밋 변경의 임의 커밋 또는 폐기 (보존 후 핸드오프에 명시만)
- `.planning/` 산출물 삭제 — 삭제 대상은 `loop-active` 단일 플래그 파일뿐

## Related
- `/floop-run` — 재개 (재개 프로토콜이 핸드오프에서 맥락 복구)
- `/floop-status` — 중단 후 현황·잔존물 점검 (읽기 전용)
- `floop-loop-protocol` — loop-active 수명주기·BLOCKED 에스컬레이션
