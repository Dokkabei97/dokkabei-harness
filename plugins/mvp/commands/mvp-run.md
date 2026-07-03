---
name: mvp-run
description: "MVP 개발 루프(Stage 4) 시작/재개 — 마스터 파일 status 기반 재개 프로토콜 수행 후 loop-active 플래그와 loop-state.json을 초기화하고 Stop훅 루프 엔진에 진입. 정지조건(결정론 게이트 그린+all-passes+verified 마커+E2E 게이트(선택)+completion promise)은 훅이 판정"
category: workflow
complexity: advanced
mcp-servers: []
personas: []
---

# /mvp-run - 개발 루프 시작/재개

`/mvp-new`가 만든 `.planning/` 산출물 위에서 PRD-driven 개발 루프(Stage 4)를 가동한다.
완료 판정의 주체는 모델이 아니라 하네스 — Stop훅 루프 엔진(`mvp-loop-stop-hook.sh`)이 매 반복마다
정지조건(① gate-cmd 그린(exit 0 + 실패 표지 보정) ∧ jq all-passes ② verified 마커 ②ᴱ E2E 수용 게이트
그린(e2e-gate-cmd 있을 때만) ③ `<promise>MVP_COMPLETE</promise>`)을
검증하고, 미충족 시 exit 2 재주입으로 루프를 지속시킨다. 매 반복 사이클은 `mvp-loop-protocol` 스킬을 따른다.

## Triggers
- `/mvp-new` 완료 후 Stage 4 개발 루프를 처음 가동할 때
- `/mvp-stop`·가드레일(max-iter/no-progress/시간 상한)로 중단된 루프를 재개할 때
- 세션이 끊긴 MVP 작업을 `.planning/` 아티팩트 기반 재개 프로토콜로 이어갈 때
- 반복 수·시간 상한을 이번 가동에 한해 조정해 루프를 돌리고 싶을 때
- 무인/야간 배치용 headless 러너 실행법을 안내받고 싶을 때 (`--headless`)

## Usage
```
/mvp-run [옵션]

Options:
  --max-iter <n>      이번 가동의 최대 반복 수 — loop-state.json max_iter 필드에 기록 (기본 24, 권장: 스토리 수×3)
  --max-minutes <n>   이번 가동의 시간 상한(분) — loop-state.json max_minutes 필드에 기록 (기본 120, started_at(epoch 초) 대비)
  --headless          루프를 이 세션에서 돌리지 않고 동봉 headless 러너(bin/mvp-headless.sh) 실행 안내만 출력 (loop-active·loop-state.json 미생성)
  --cross-check       교차 모델 반증 opt-in — MV가 verified 마커 생성 전 외부 CLI 교차 반증 수행, 외부 CLI 미설치 시 동일 모델 2라운드 규약으로 자동 폴백 (상세: mvp-orchestrator '--cross-check 교차 모델 반증' 절)
```

## Behavioral Flow

### Phase 1: 마스터 파일 status 분기
1. **감지**: `.planning/mvp-*.md` Glob — **미존재 시 루프를 만들지 않고 `/mvp-new` 진입을 안내하고 종료**
2. **분기**:
   - `status: done` → 완료 상태 보고 후 종료 (재가동 없음)
   - `status: blocked` 또는 **BLOCKED.md 존재(status 무관 blocked로 간주)** → BLOCKED.md(시도·차단 원인·권장 다음 행동) 요약 제시, 사용자 결정(스코프 재협상=PS / 구조 재설계=TA / 그대로 재개)으로 해소 확인 후 진행
   - `status: paused` 또는 `in_progress` → Phase 2 재개 프로토콜
3. **Stage 확인**: 마스터 `## Stage`가 4 미만(스캐폴딩 미완)이면 잔여 Stage를 먼저 끝내도록 `/mvp-new` 이어가기 안내

### Phase 2: 재개 프로토콜 (compaction 의존 금지 — 아티팩트에서 이해 재생성)
1. **마스터 읽기**: Goal·Stage·Gates·Checklist·Iteration·Feedback 복구 (in_progress → 복구 모드)
2. **이력 확인**: `git log --oneline -10` + progress.md 반복 로그로 마지막 작업 지점 파악
3. **대상 확정**: prd.json에서 미완(`passes:false`) 최우선 스토리 **1개** 식별, verified/ 마커와 대조

### Phase 3: 루프 가동 준비
1. **플래그 생성**: `printf 'engine=mvp\n' > .planning/loop-active` — Stop훅 안전핀 해제(이 파일이 있어야만 훅이 동작). `engine=mvp` 줄은 이 루프의 소유 엔진을 명시해 타 루프 엔진(floop/generic) 훅의 개입을 차단한다(줄 없는 기존 파일은 레거시 호환으로 mvp 소유 간주)
2. **상태 초기화**: loop-state.json 기록 — 신규 가동 시 `{"iteration":0,"last_fail_sig":"","started_at":<date +%s>,"max_iter":24,"max_minutes":120}` (`started_at`은 epoch 초), 재가동 시 `started_at` 갱신(시간 상한 기준점 재설정)
3. **옵션 반영**: `--max-iter`/`--max-minutes` 값을 loop-state.json의 `max_iter`/`max_minutes` 필드에 기록 (미지정 시 기본 24/120 — Stop훅은 env `LOOP_MAX_ITER`/`LOOP_MAX_MINUTES` > loop-state.json 필드 > 기본값 순으로 로드)

### Phase 4: 루프 진입 안내 및 첫 반복 착수
1. **가동 보고**: 대상 스토리·잔여 n/m·가드레일 설정(max-iter/시간 상한/no-progress 2회/circuit breaker 3회/킬스위치 `/mvp-stop`)을 1화면 보고
2. **사이클 시작**: `mvp-loop-protocol` 표준 사이클로 진입 — 스토리 선택 → 테스트 먼저 → 최소 구현 → 게이트 그린(여기까지 메인 세션이 mvp-builder 규율 체화) → `mvp-verifier` AC 반증(통과까지 수정 반복) → verified 마커 → passes:true 갱신(메인 세션) → **커밋 1회**(구현+prd.json+progress.md 일괄, `feat(mvp): S-xx ...`) — 이후 종료 시도마다 Stop훅이 정지조건을 판정

### --headless 분기 (러너 실행 안내 — 이 세션에서 루프 미가동)
`--headless` 지정 시 **Phase 1(status 분기)만 수행**하고 Phase 2(재개 프로토콜)·Phase 3(루프 가동 준비)·Phase 4(루프 진입)는 전부 건너뛴다 — **loop-active·loop-state.json을 만들지 않는다**. 재개 프로토콜은 러너가 매 반복 새로 띄우는 각 `claude -p` 세션이 스스로 수행한다. Stop훅 엔진 대신 동봉 러너(외부 `while + claude -p`, 컨텍스트 리셋형)를 쓰도록 아래를 출력하고 종료한다 — 정지조건 판정 규약은 Stop훅과 동일하다(게이트·E2E 모두 exit code 우선 + has_failure_marker 실패 표지 보정, all-passes·verified 마커·promise 결합). 안내 출력 시 `${CLAUDE_PLUGIN_ROOT}`는 실제 경로로 치환한다:
1. **전면 실행**: 프로젝트 루트에서 `bash "${CLAUDE_PLUGIN_ROOT}/bin/mvp-headless.sh"`
2. **백그라운드(무인/야간)**: `nohup bash "${CLAUDE_PLUGIN_ROOT}/bin/mvp-headless.sh" > .planning/headless.log 2>&1 &`
3. **가드 조정**: `LOOP_MAX_ITER=36 LOOP_MAX_MINUTES=300 bash "${CLAUDE_PLUGIN_ROOT}/bin/mvp-headless.sh"` (기본 24회/120분 — 하드 기본값, 비용 상한이 곧 안전장치)
4. **이중 가동 충돌 경고**: `.planning/loop-active`가 존재하면(Stop훅 루프 가동 중) 러너가 이중 가동 금지로 시작을 거부(exit 1)하고, 러너 가동 중 출현해도 매 반복 재검사가 감지해 중단(exit 1)한다 — `/mvp-stop`으로 해제 후 실행하라고 명시. 러너끼리의 중첩 실행(크론 겹침)은 `.planning/headless-active` 락(PID 기록, 스테일 자동 정리)이 거부한다
상세 규약(컨텍스트 리셋·재개·크론 등록·가드레일 대응표)은 `mvp-orchestrator`의 `references/headless-recipe.md` 참조.

## Tool Coordination
- **Glob/Read**: `.planning/mvp-*.md`·prd.json·progress.md·BLOCKED.md·verified/ 판독 (재개 프로토콜)
- **Bash**: `printf 'engine=mvp\n' > .planning/loop-active`, `git log --oneline -10`, jq로 미완 스토리 질의
- **Write**: loop-state.json 초기화/갱신
- **Task**: mvp-verifier(반증)만 매 스토리 디스패치 — 구현은 메인 세션이 mvp-builder 규율을 체화해 직접 수행(mvp-builder 서브에이전트 디스패치는 병렬 feature 구현의 worktree 격리 시에만), 구조적 BLOCKED 시 tech-architect 단독 재투입
- **Skill**: `mvp-loop-protocol` — 반복 사이클·재개 프로토콜·env 표의 기준 문서

## Examples

### 최초 가동
```
/mvp-run
# .planning/mvp-petwalk.md status: in_progress, Stage 4 → 재개 프로토콜 수행
# loop-active 생성, loop-state.json {"iteration":0,"last_fail_sig":"","started_at":1781224200,"max_iter":24,"max_minutes":120} (started_at=date +%s)
# 대상: S-03 (passes:false 최우선) — 가드레일: 24회 / 120분 / no-progress 2회
# 루프 진입: 이후 종료 시도는 Stop훅이 정지조건(게이트 그린+all-passes+verified 마커+E2E(선택)+promise)으로 판정
```

### 중단된 루프 재개 (상한 조정)
```
/mvp-run --max-iter 12 --max-minutes 60
# status: paused → 핸드오프(progress.md)와 git log로 마지막 지점 복구
# started_at 갱신(epoch 초 — 시간 상한 기준점 재설정), loop-state.json에 max_iter=12 / max_minutes=60 기록
# 미완 스토리 S-05부터 사이클 재개
```

### 산출물 없는 레포에서 호출
```
/mvp-run
# .planning/mvp-*.md 미존재 → 루프 미가동
# "/mvp-new \"<아이디어 한 줄>\"로 Stage 0~3을 먼저 완료하세요" 안내 후 종료
```

### headless 러너 안내 (--headless)
```
/mvp-run --headless
# status 분기까지만 수행, loop-active·loop-state.json 미생성
# 안내 출력: nohup bash "<플러그인 루트>/bin/mvp-headless.sh" > .planning/headless.log 2>&1 &
# 경고: .planning/loop-active 존재 시 러너가 시작 거부 — /mvp-stop 후 실행
```

## Boundaries

**Will:**
- 마스터 파일 status(미존재/done/blocked/paused/in_progress)별로 정확히 분기
- 재개 프로토콜 4단계로 아티팩트에서 작업 맥락을 재생성한 뒤에만 루프 가동
- loop-active·loop-state.json을 초기화하고 가드레일 설정을 보고한 뒤 표준 사이클 진입
- 미완(passes:false) 최우선 스토리 1개만 대상으로 반복 (한 반복 = 한 스토리)

**Will Not:**
- `.planning/` 산출물(prd.json·gate-cmd) 없이 루프 가동 (→ `/mvp-new` 안내)
- `--headless` 지정 시 세션 내 루프 가동·loop-active 생성 (러너 실행 안내만 출력)
- 정지조건·완료 판정을 모델 스스로 수행 (판정 주체는 Stop훅 루프 엔진)
- passes 직접 마킹(verified 마커 선행 필수 — prd-guard 훅이 차단), 테스트 삭제·약화
- status: done인 MVP의 재가동

## Related
- `mvp-loop-protocol` — 반복 사이클·재개 프로토콜·env 표·BLOCKED 에스컬레이션
- `mvp-orchestrator` — Stage 상태기계·Guardrails·Error Handling
- `/mvp-stop` — 수동 킬스위치 (loop-active 삭제 + 핸드오프 + paused)
- `/mvp-status` — 가동 전 현황 확인 (읽기 전용)
