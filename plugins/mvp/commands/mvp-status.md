---
name: mvp-status
description: "MVP 진행 현황 읽기 전용 조회 — 스토리 passes n/m, iteration/상한, 경과 시간, verified 마커, BLOCKED 여부, loop-active 상태와 수동 해제법을 1화면 보고. 어떤 상태도 변경하지 않음"
category: utility
complexity: basic
mcp-servers: []
personas: []
---

# /mvp-status - MVP 진행 현황 조회 (읽기 전용)

`.planning/` 아티팩트만 판독해 MVP 하네스의 현재 상태를 1화면으로 보고한다.
**읽기 전용** — 마스터 파일·prd.json·loop-active 등 어떤 파일도 생성/수정/삭제하지 않는다.

## Triggers
- 루프가 지금 어디까지 왔는지(스토리 n/m, 반복 수, 경과 시간) 확인하고 싶을 때
- 루프 중단 후 재개(`/mvp-run`) 전에 BLOCKED·미완 스토리·핸드오프 상태를 점검할 때
- 세션 비정상 종료 등으로 `loop-active`가 잔존하는지 의심될 때 (Stop matcher `*` 부수효과 점검)
- verified 마커와 prd.json passes의 정합(마커 없는 passes:true 등)을 검사하고 싶을 때

## Usage
```
/mvp-status

옵션 없음 — 항상 .planning/ 전체 현황을 출력한다. 상태 변경 동작이 없으므로 언제든 안전하게 호출 가능.
```

## Behavioral Flow

### Phase 1: 아티팩트 수집
1. **마스터 판독**: `.planning/mvp-*.md`에서 status(in_progress/paused/blocked/done)·Stage·Gates 스탬프·Iteration·Feedback 추출 (미존재 시 "MVP 없음 — `/mvp-new`로 시작" 안내 후 종료)
2. **루프 상태 판독**: loop-state.json(iteration·started_at·last_fail_sig)과 `loop-active` 파일 존재 여부 확인
3. **스토리 판독**: prd.json에서 passes true/false 집계, `verified/` 디렉토리의 마커 목록 수집, BLOCKED.md 유무·요약 확인

### Phase 2: 집계·정합 검사 (판독만, 수정 없음)
1. **진행률 계산**: passes n/m, iteration/LOOP_MAX_ITER(기본 24), started_at 대비 경과 분/LOOP_MAX_MINUTES(기본 120)
2. **정합 검사**: passes:true인데 `verified/{id}` 마커가 없는 스토리, 마커는 있는데 passes:false인 스토리를 플래그 (수정은 하지 않고 보고만 — 교정은 prd-guard 훅과 루프가 담당)
3. **잔존 감지**: status가 paused/done인데 `loop-active`가 남아 있으면 잔존으로 판정

### Phase 3: 보고
1. **현황표 출력**: status·Stage·스토리 n/m·iteration·경과 시간·verified 마커·BLOCKED 요약·loop-active 상태를 표로 제시
2. **다음 행동 안내**: 미완이면 `/mvp-run` 재개, BLOCKED이면 에스컬레이션(스코프 재협상=PS / 구조 재설계=TA), `loop-active` 잔존이면 수동 해제법 — `rm .planning/loop-active` (이후 종료가 훅에 막히지 않음)

## Tool Coordination
- **Glob**: `.planning/mvp-*.md`·`verified/*` 마커 탐색
- **Read**: 마스터·prd.json·loop-state.json·progress.md·BLOCKED.md 판독
- **Bash**: jq 집계(`[.stories[].passes]` 등)·경과 시간 계산 — 읽기 전용 질의만 (touch/rm/리다이렉션 미사용)
- **Grep**: progress.md의 `<promise>MVP_COMPLETE</promise>` 존재 확인 (grep -qF 동일 기준)

## Examples

### 루프 가동 중 현황
```
/mvp-status
# status: in_progress / Stage 4 / 스토리 4/7 passes / iteration 9/24 / 경과 41/120분
# verified: S-01 S-02 S-03 S-04 / BLOCKED: 없음 / loop-active: 가동 중
# 다음 행동: 루프 자율 진행 중 — 중단하려면 /mvp-stop
```

### 중단 후 점검 (loop-active 잔존 감지)
```
/mvp-status
# status: paused / 스토리 5/7 / loop-active: 잔존 ⚠️ (paused인데 플래그 존재)
# 수동 해제: rm .planning/loop-active  ← Stop matcher * 부수효과로 잔존 가능, 해제 전까지 종료가 재주입될 수 있음
# 재개: /mvp-run
```

### BLOCKED 상태 점검
```
/mvp-status
# status: blocked / 스토리 5/7 / BLOCKED.md: S-06 외부 OAuth 콜백 검증 불가 (시도 3회, circuit breaker)
# 정합 플래그: 없음
# 다음 행동: 스코프 재협상(product-strategist) 또는 구조 재설계(tech-architect) 후 /mvp-run
```

## Boundaries

**Will:**
- `.planning/` 아티팩트 기반으로 진행률·루프 상태·가드레일 잔여치를 1화면 보고
- passes ↔ verified 마커 정합 검사 결과를 플래그로 제시
- `loop-active` 잔존 감지와 수동 해제법(`rm .planning/loop-active`) 안내
- 상태별 다음 행동(`/mvp-run`·`/mvp-stop`·에스컬레이션) 안내

**Will Not:**
- 어떤 상태 변경도 수행하지 않음 — loop-active 삭제, status 전환, prd.json/마커 수정 일절 금지 (해제는 안내만)
- 루프 가동/중단 (→ `/mvp-run`, `/mvp-stop`)
- 게이트 스크립트 실행이나 checker 디스패치 (→ `/mvp-gate`)

## Related
- `/mvp-run` — 현황 확인 후 루프 재개
- `/mvp-stop` — 가동 중 루프의 안전 중단
- `/mvp-gate` — 게이트 판정이 필요할 때 (본 커맨드는 판독만)
- `mvp-loop-protocol` — loop-active 수명주기·env 표
