# Loop Engine Hook Validation Rules (LOOP-*)

루프 엔진 Stop 훅 전용 룰셋 — `flow-scaffolding/templates/loop-stop-hook.sh` 파생물에 적용한다.
근거 라인 표기는 레포에 남은 유일한 프로덕션 훅 기준이다 (mvp·floop 엔진은 2026-10 `archive/`로 이동):
- **generic**: `plugins/harness/hooks/generic-loop-stop-hook.sh`

## LOOP-001: Safety Pin Present
- **Severity**: Critical
- **Check**: 훅 최상단(판정 로직 이전)에 `[ -f "$PLAN/loop-active" ] || exit 0` 안전핀 존재 — 루프 미가동 세션의 종료를 절대 방해하지 않는다
- **Auto-fixable**: No
- **근거**: generic:33

## LOOP-002: Engine Scope Guard
- **Severity**: High
- **Check**: `loop-active`의 `engine=` 줄로 소유권 판별 — 타 엔진 값이면 무개입 `exit 0`. 레거시(engine 줄 없음)는 무주장 — 엔진은 자기 값이 명시된 경우에만 활성
- **Auto-fixable**: No
- **근거**: generic:35-39 (`tr -d '\r'` CRLF 방어 포함 — 레거시 무주장)

## LOOP-003: jq Graceful Degrade
- **Severity**: High
- **Check**: `command -v jq` 부재 시 재주입도 통과 판정도 하지 않고 사유를 stderr에 명시한 뒤 `exit 0` (loop-active는 유지 — 해제는 킬스위치 커맨드의 몫)
- **Auto-fixable**: No
- **근거**: generic:41-45

## LOOP-004: Promise Exact-Match Only
- **Severity**: High
- **Check**: completion promise 판정은 `grep -qF` 정확 문자열 일치만 사용 — 정규식 매칭 금지(promise에 `<`,`>` 등 메타문자가 포함되므로 오탐/미탐 유발)
- **Auto-fixable**: No
- **근거**: generic:150-154

## LOOP-005: Guardrails + Kill-Switch Release Path
- **Severity**: Critical
- **Check**: 가드레일 3종(max iterations · no-progress 동일 실패 시그니처 연속 · 시간 상한) 전부 존재하고, 각 종료 경로(가드레일 도달·정지조건 충족)가 `rm -f "$PLAN/loop-active"`로 루프를 해제한다. 별도의 수동 킬스위치 커맨드(예: `/loop-stop`)가 문서화되어 있어야 한다
- **Auto-fixable**: No
- **근거**: max-iter generic:109-114 / 시간 상한 generic:116-122 / no-progress generic:176-194 / 해제 경로 generic:111·118·171·178

## LOOP-006: Stdin Consumed Before Gate Execution
- **Severity**: Medium
- **Check**: stdin(JSON)을 게이트 명령 실행 **전에** `input="$(cat || true)"`로 선소비 — 미소비 시 파이프 버퍼 블로킹 위험이 있고, 게이트 자식 프로세스가 훅의 stdin을 상속해 오염될 수 있다
- **Auto-fixable**: No
- **근거**: generic:87-90 (주석에 선소비 규약 명시)

## LOOP-007: Numeric Defense via Case Pattern
- **Severity**: Medium
- **Check**: loop-state.json/env에서 읽은 모든 수치(iteration·max_iter·max_minutes·started_at)에 `case "$v" in (''|*[!0-9]*) v=<기본값>;; esac` 방어 — `set -e` 환경에서 비숫자 값이 `-ge` 산술 비교를 크래시시키는 것을 차단 (bash 3.2 호환 패턴)
- **Auto-fixable**: Yes (누락 변수에 case 방어 삽입)
- **근거**: generic:60-61·67-68·100-102

## LOOP-008: Atomic State Write (tmp → mv)
- **Severity**: Medium
- **Check**: loop-state.json 기록은 임시파일에 쓴 뒤 `mv`로 원자 교체 — 훅 중단 시 부분 기록(깨진 JSON)이 다음 반복의 상태 로드를 오염시키는 것을 방지
- **Auto-fixable**: Yes (`> "$STATE_FILE"` 직접 기록을 tmp→mv로 치환)
- **근거**: generic:161-167 (`state_tmp="$STATE_FILE.tmp.$$"` 후 `mv`)

## LOOP-009: Failure-Marker Correction on Exit 0
- **Severity**: High
- **Check**: 게이트 exit 0이어도 출력에 실패 표지(`^FAIL` 또는 1 이상 카운트 `[1-9][0-9]* +(fail(ed|ure|ures)?|errors?)`)가 있으면 보수적으로 red 판정(`has_failure_marker`). "0 failed" 류는 오탐하지 않아야 하며, 정규식은 템플릿과 공유 규약 — 변경 시 함께 갱신한다
- **Auto-fixable**: No
- **근거**: generic:124-127 (generic:126 에 공유 규약 주석)

## LOOP-010: Loop-State Update Contract
- **Severity**: Medium
- **Check**: 매 반복 상태 갱신 시 (1) iteration 은 `iter+1`로 증가, (2) `started_at`은 최초 반복에서 초기화 후 보존, (3) 가동 커맨드가 기록한 `max_iter`/`max_minutes`(및 promise)는 덮어쓰지 않고 보존, (4) `last_fail_sig`는 게이트 red일 때만 산출된 시그니처로 갱신
- **Auto-fixable**: No
- **근거**: generic:156-167 (promise 필드까지 보존)

## LOOP-011: Turn Block Cap Handoff
- **Severity**: High
- **Check**: Claude Code는 한 턴에 Stop 블록을 연속 8회까지만 따르고 9번째 `exit 2`는 무시한 채 턴을 끝낸다(실측 2026-09-20, n=3). 훅은 payload `stop_hook_active`로 턴 단위 연속 블록 카운터를 유지하고(false면 리셋), 상한 도달 시 차단 대신 핸드오프를 기록하고 `exit 0` 해야 한다 — 미감지 시 루프가 핸드오프 없이 조용히 끊긴다. 누적 `iteration`으로 판정하면 오답(헤드리스·재개 루프를 잘못 끊음)
- **Auto-fixable**: No
- **근거**: generic:98-104 (카운터 로드·리셋) · 165 (기록) · 196-209 (핸드오프)
