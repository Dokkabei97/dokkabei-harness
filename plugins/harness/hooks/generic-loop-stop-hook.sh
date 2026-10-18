#!/usr/bin/env bash
# =============================================================================
# generic-loop-stop-hook.sh — /loop-run 경량 반복 루프 엔진 (Stop 훅)
# flow-scaffolding templates/loop-stop-hook.sh 의 물화(harness 프로덕션판).
# 산출물 구조(prd/tasks) 없이 "게이트 그린까지 반복"만 수행하는 단발 미니 루프 엔진이다.
# (mvp·feature-loop 엔진은 2026-10 archive/ 로 이동 — 레포에 남은 유일한 루프 엔진)
#   - exit 0 : 종료 허용 (루프 비활성 / 타 엔진 소유 / 정지조건 충족 / 가드레일 도달)
#   - exit 2 : 종료 차단. stderr가 Claude에게 전달되어 다음 반복이 이어진다.
#
# engine 스코프 (공유 계약 — loop-active engine 스코프):
#   .planning/loop-active 에 "engine=generic" 1줄이 명시된 경우에만 활성.
#   engine 줄이 없는 레거시 loop-active 는 무주장(exit 0) — archive 된 mvp/floop 엔진의
#   잔존물일 수 있다. 타 engine 값도 즉시 exit 0.
#   /loop-run 이 loop-active 생성 시 "engine=generic" 을 기록한다.
#
# 정지조건 (판정 주체 = 본 훅, 모델 아님):
#   ① 결정론 게이트: .planning/gate-cmd 실행 — exit code 우선 + has_failure_marker 보정
#   ② completion promise: progress.md 의 정확 문자열 일치 (grep -qF, 정규식 금지)
#   종료 허용 = ① ∧ ②
# 가드레일: max iterations(기본 12) · no-progress(md5 시그니처 연속 동일) · 시간 상한(기본 60분)
# 턴 블록 상한: Claude Code 는 연속 8회 Stop 블록 후 9번째 exit 2 를 무시하고 턴을 끝낸다
#   (실측 2026-09-20, n=3). stop_hook_active 로 턴 단위 연속 블록(turn_blocks)을 세고,
#   상한 도달 시 차단 대신 progress.md 에 핸드오프를 남기고 종료 허용(loop-active 유지 —
#   다음 턴에 카운터가 리셋되어 루프가 이어진다). iteration(누적)과는 별개의 카운터다.
# 킬스위치: /loop-stop (loop-active 삭제) — 가드레일과 별개의 수동 중단 수단
# =============================================================================
set -euo pipefail

PROJ="${CLAUDE_PROJECT_DIR:-.}"
PLAN="$PROJ/.planning"

# (a) 안전핀 — 루프 미가동 세션의 종료는 절대 방해하지 않는다 (즉시 종료 허용)
[ -f "$PLAN/loop-active" ] || exit 0

# (a') engine 스코프 가드 — engine=generic 명시된 경우에만 내 소유.
# 레거시(engine 줄 없음)·타 엔진 값은 무주장 exit 0.
# tr -d '\r' 방어 — CRLF 로 기록된 loop-active 도 동일 판정.
loop_engine="$(grep -m1 '^engine=' "$PLAN/loop-active" 2>/dev/null | tr -d '\r' || true)"
[ "${loop_engine#engine=}" = "generic" ] || exit 0

# jq 부재 시 graceful degrade — 재주입도 통과 판정도 하지 않고, 사유 명시 후 종료 허용
if ! command -v jq >/dev/null 2>&1; then
  echo "[generic-loop] jq 미설치 — 정지조건 판정 불가. 루프를 진행할 수 없어 종료를 허용한다. jq 설치 후 /loop-run 으로 재가동하라. (loop-active 유지 — 해제는 /loop-stop)" >&2
  exit 0
fi

# ▼ CONFIG — env > loop-state.json 필드 > 기본값 순 로드
STATE_FILE="$PLAN/loop-state.json"
PROGRESS_FILE="$PLAN/progress.md"
GOAL_FILE="$PLAN/loop-goal.md"
BLOCKED_FILE="$PLAN/BLOCKED.md"

# promise/max_iter/max_minutes — env > loop-state.json(/loop-run 의 --promise/--max-iter/--max-minutes 기록) > 기본값
state_promise=""; state_max_iter=""; state_max_minutes=""
if [ -f "$STATE_FILE" ]; then
  state_promise="$(jq -r '.promise // empty' "$STATE_FILE" 2>/dev/null || echo "")"
  state_max_iter="$(jq -r '.max_iter // empty' "$STATE_FILE" 2>/dev/null || echo "")"
  state_max_minutes="$(jq -r '.max_minutes // empty' "$STATE_FILE" 2>/dev/null || echo "")"
fi
case "$state_max_iter" in (''|*[!0-9]*) state_max_iter="";; esac
case "$state_max_minutes" in (''|*[!0-9]*) state_max_minutes="";; esac
PROMISE="${LOOP_PROMISE:-${state_promise:-<promise>LOOP_COMPLETE</promise>}}"
MAX_ITER="${LOOP_MAX_ITER:-${state_max_iter:-12}}"
MAX_MINUTES="${LOOP_MAX_MINUTES:-${state_max_minutes:-60}}"

# 숫자 방어 — 비정상 값이면 기본값으로 복원 (set -e 환경에서 -ge 오류 방지)
case "$MAX_ITER" in (''|*[!0-9]*) MAX_ITER=12;; esac
case "$MAX_MINUTES" in (''|*[!0-9]*) MAX_MINUTES=60;; esac

# (b) 게이트 명령 동적 로드 — LOOP_TEST_CMD env 우선, 없으면 .planning/gate-cmd 1행
GATE_CMD="${LOOP_TEST_CMD:-}"
if [ -z "$GATE_CMD" ] && [ -s "$PLAN/gate-cmd" ]; then
  GATE_CMD="$(head -n 1 "$PLAN/gate-cmd" | tr -d '\r')"
fi
if [ -z "$GATE_CMD" ]; then
  echo "[generic-loop] 게이트 명령 없음(.planning/gate-cmd 비어있음, LOOP_TEST_CMD 미지정) — 판정 불가로 종료를 허용한다. /loop-run --gate-cmd '<명령>' 으로 재가동하라. (loop-active 유지 — 해제는 /loop-stop)" >&2
  exit 0
fi

# stdin 해시 (no-progress 시그니처용) — macOS/Linux 이식성 폴백
hash_stdin() {
  if command -v md5sum >/dev/null 2>&1; then md5sum | cut -d' ' -f1
  elif command -v md5 >/dev/null 2>&1; then md5 -q
  else shasum | cut -d' ' -f1; fi
}

# stdin 입력(JSON) 선소비 — 게이트 실행 전에 소비, stop_hook_active 로 재진입 여부 확인.
# 재진입(stop_hook_active=true)이라도 우회하지 않는다 — 차단/허용은 가드레일이 판정.
input="$(cat || true)"
stop_active="$(printf '%s' "$input" | jq -r '.stop_hook_active // false' 2>/dev/null || echo false)"

# 상태 로드 — iteration / last_fail_sig / started_at (epoch 초) / turn_blocks
iter=0; last_fail_sig=""; started_at=0; turn_blocks=0
if [ -f "$STATE_FILE" ]; then
  iter="$(jq -r '.iteration // 0' "$STATE_FILE" 2>/dev/null || echo 0)"
  last_fail_sig="$(jq -r '.last_fail_sig // ""' "$STATE_FILE" 2>/dev/null || echo "")"
  started_at="$(jq -r '.started_at // 0' "$STATE_FILE" 2>/dev/null || echo 0)"
  turn_blocks="$(jq -r '.turn_blocks // 0' "$STATE_FILE" 2>/dev/null || echo 0)"
fi
case "$iter" in (''|*[!0-9]*) iter=0;; esac
case "$started_at" in (''|*[!0-9]*) started_at=0;; esac
case "$turn_blocks" in (''|*[!0-9]*) turn_blocks=0;; esac
# 새 턴(stop_hook_active=false)이면 연속 블록 카운터 리셋
[ "$stop_active" = "true" ] || turn_blocks=0
TURN_BLOCK_CAP=8

now="$(date +%s)"

# 가드레일 1: max iterations — 도달 시 루프 해제 + 미완 보고
if [ "$iter" -ge "$MAX_ITER" ]; then
  rm -f "$PLAN/loop-active"
  echo "[generic-loop] max iterations($MAX_ITER) 도달 — 루프 종료(loop-active 해제). 미완 상태는 $PROGRESS_FILE 참조, /loop-run 으로 재가동하라(--max-iter 로 상한 조정)." >&2
  exit 0
fi

# 가드레일 3: 시간 상한 — started_at(epoch 초) 대비 MAX_MINUTES 초과 시 종료
if [ "$started_at" -gt 0 ] && [ $(( now - started_at )) -ge $(( MAX_MINUTES * 60 )) ]; then
  rm -f "$PLAN/loop-active"
  elapsed_min=$(( (now - started_at) / 60 ))
  echo "[generic-loop] 시간 상한 도달(경과 ${elapsed_min}분 >= ${MAX_MINUTES}분) — 루프 종료(loop-active 해제). /loop-run 으로 재가동 가능(--max-minutes 로 상한 조정)." >&2
  exit 0
fi

# 출력의 명백한 실패 표지 판정 — exit 0이어도 출력에 실패 카운트가 있으면 보수적으로 레드.
# "0 failed" 류 오탐 방지: 행두 FAIL 또는 1 이상 카운트가 붙은 실패 표지만 매칭.
# ※ 정규식은 flow-scaffolding templates/loop-stop-hook.sh 와 공유 규약 — 변경 시 함께 갱신하라.
has_failure_marker() { printf '%s\n' "$1" | grep -Eqi '(^FAIL([ :]|$)|[1-9][0-9]* +(fail(ed|ure|ures)?|errors?))'; }

# ① 결정론 게이트 실행 — eval 금지, bash -c 사용. 판정은 exit code 우선.
gate_exit=0
test_out="$( (cd "$PROJ" && bash -c "$GATE_CMD") 2>&1 )" || gate_exit=$?

gate_green=false
if [ "$gate_exit" -eq 0 ]; then
  gate_green=true
  has_failure_marker "$test_out" && gate_green=false
fi

# 실패 시그니처(md5) — no-progress 감지용. 게이트 레드일 때 산출.
fail_sig=""
if [ "$gate_green" = false ]; then
  # 숫자 토큰 제거 정규화 — "1 failed in 0.01s" 류 소요시간 비결정성 제거
  sig_src="$(printf '%s' "$test_out" | grep -Ei 'fail|error' | sed -E 's/[0-9]+([.][0-9]+)?//g' | sort || true)"
  if [ -z "$sig_src" ]; then
    sig_src="exit=$gate_exit"$'\n'"$(printf '%s' "$test_out" | tail -20)"
  fi
  fail_sig="$(printf '%s' "$sig_src" | hash_stdin 2>/dev/null || echo "")"
fi

# ② completion promise — 정확 문자열 일치 (grep -qF, 정규식 금지)
promise_found=false
if [ -f "$PROGRESS_FILE" ] && grep -qF "$PROMISE" "$PROGRESS_FILE"; then
  promise_found=true
fi

# 상태 갱신 — 임시파일→mv 원자적 기록(부분 기록 방지). started_at은 최초 반복에서 초기화 후
# 보존, promise/max_iter/max_minutes 는 /loop-run 기록 값 보존 (없으면 현재 해석값으로 채움)
# turn_blocks 는 이번 호출이 차단으로 끝날 때의 값(+1)을 기록 — 허용 경로에선 다음 턴에 리셋되므로 무해
next_iter=$((iter + 1))
[ "$started_at" -gt 0 ] || started_at="$now"
state_tmp="$STATE_FILE.tmp.$$"
jq -n --argjson it "$next_iter" --arg sig "$fail_sig" --argjson st "$started_at" \
  --arg pr "${state_promise:-$PROMISE}" \
  --argjson mi "${state_max_iter:-$MAX_ITER}" --argjson mm "${state_max_minutes:-$MAX_MINUTES}" \
  --argjson tb "$((turn_blocks + 1))" \
  '{iteration:$it, last_fail_sig:$sig, started_at:$st, promise:$pr, max_iter:$mi, max_minutes:$mm, turn_blocks:$tb}' > "$state_tmp"
mv "$state_tmp" "$STATE_FILE"

# 정지 판정: ①(게이트 그린) ∧ ②(promise) → 종료 허용 + 루프 해제
if [ "$gate_green" = true ] && [ "$promise_found" = true ]; then
  rm -f "$PLAN/loop-active"
  echo "[generic-loop] 정지조건 충족(게이트 그린 + promise) — iteration $next_iter 에서 루프 정상 종료(loop-active 해제)." >&2
  exit 0
fi

# 가드레일 2: no-progress — 직전 반복과 동일 실패 시그니처 연속 시 종료 + BLOCKED 기록
if [ -n "$fail_sig" ] && [ "$fail_sig" = "$last_fail_sig" ]; then
  rm -f "$PLAN/loop-active"
  {
    echo ""
    echo "## no-progress 차단 — $(date '+%Y-%m-%d %H:%M:%S')"
    echo "- 엔진: generic (/loop-run)"
    echo "- iteration: $next_iter/$MAX_ITER"
    echo "- 실패 시그니처(md5): $fail_sig (연속 2회 동일)"
    echo "- gate-cmd: $GATE_CMD (exit=$gate_exit)"
    echo "- 게이트 출력 tail -20:"
    echo '```'
    printf '%s\n' "$test_out" | tail -20
    echo '```'
    echo "- 권장 다음 행동: 실패 원인 분석 후 /loop-run 재가동."
  } >> "$BLOCKED_FILE"
  echo "[generic-loop] no-progress 감지(동일 실패 시그니처 연속) — 루프 종료(loop-active 해제). 상세는 $BLOCKED_FILE 참조." >&2
  exit 0
fi

# 턴 블록 상한 — 이미 이번 턴에 8회 차단했다면 이번 exit 2 는 Claude Code 가 무시한다.
# 조용히 끝나지 않도록 핸드오프를 남기고 종료 허용. loop-active 는 유지(다음 턴에 재개).
if [ "$turn_blocks" -ge "$TURN_BLOCK_CAP" ]; then
  {
    echo ""
    echo "## 턴 블록 상한 핸드오프 — $(date '+%Y-%m-%d %H:%M:%S')"
    echo "- 엔진: generic (/loop-run), iteration: $next_iter/$MAX_ITER"
    echo "- 이번 턴 연속 블록 ${turn_blocks}회 = Claude Code 상한 — 턴 종료"
    echo "- 게이트: $([ "$gate_green" = true ] && echo 그린 || echo "레드 (exit=$gate_exit)")"
    echo "- 재개: 아무 메시지(예: '계속')로 다음 턴을 시작하면 루프가 이어진다. 중단은 /loop-stop"
  } >> "$PROGRESS_FILE"
  echo "[generic-loop] 이번 턴 연속 블록 ${turn_blocks}회 — Claude Code 상한(${TURN_BLOCK_CAP})이라 턴을 넘긴다. loop-active 유지, 핸드오프는 $PROGRESS_FILE 참조. '계속'으로 재개, 중단은 /loop-stop." >&2
  exit 0
fi

# 미충족 → 종료 차단, 작업 재주입 (stderr가 Claude에게 전달됨)
{
  echo "[generic-loop] 작업 미완료 (iteration $next_iter/$MAX_ITER, 재진입=$stop_active). 다음을 해결하고 계속 진행하라:"
  if [ -s "$GOAL_FILE" ]; then
    echo "- 목표: $(head -n 1 "$GOAL_FILE")"
  fi
  if [ "$gate_green" = false ]; then
    echo "- 결정론 게이트 실패 (cmd: $GATE_CMD, exit=$gate_exit). 출력 tail -20:"
    printf '%s\n' "$test_out" | tail -20
  fi
  if [ "$promise_found" = false ]; then
    echo "- 목표 달성과 게이트 그린을 확인한 뒤 $PROGRESS_FILE 에 '$PROMISE' 를 정확히 기록하라."
  fi
} >&2
exit 2
