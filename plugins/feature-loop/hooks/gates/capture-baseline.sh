#!/usr/bin/env bash
# =============================================================================
# capture-baseline.sh — Stage A baseline 캡처 (훅 미등록, /floop-new 가 Bash 호출)
# .planning/gate-cmd 를 1회 실행해 현재 테스트 상태를 기준선으로 고정한다.
# 산출: .planning/baseline.json = {captured_at, gate_cmd, baseline_exit, fail_count}
#   - baseline_exit==0 : 클린 기준선 — 회귀 게이트는 "gate-cmd exit 0 유지"로 단순.
#   - baseline_exit!=0 : 기존 N개 실패 존재 — 회귀 게이트는 "fail_count <= N(신규 실패 0)".
#   - fail_count==-1   : 기존 red 이지만 실패 수 파싱 불가 — Stop훅이 exit code 로만 보수 판정.
# extract_fail_count() 는 floop-loop-stop-hook.sh 와 동일 규약(일관된 회귀 판정의 전제).
# 통과 exit 0 / gate-cmd 부재·실행 불가 exit 1.
# =============================================================================
set -euo pipefail

PROJ="${CLAUDE_PROJECT_DIR:-.}"
PLAN="$PROJ/.planning"
GATE_FILE="$PLAN/gate-cmd"
BASELINE="$PLAN/baseline.json"

if ! command -v jq >/dev/null 2>&1; then
  echo "[capture-baseline] 실패: jq 미설치 — baseline.json 생성 불가 (jq 설치 후 재실행)" >&2
  exit 1
fi

# gate-cmd 동적 로드 — 인자 우선, 없으면 .planning/gate-cmd 1행
GATE_CMD="${1:-}"
if [ -z "$GATE_CMD" ] && [ -s "$GATE_FILE" ]; then
  GATE_CMD="$(head -n 1 "$GATE_FILE" | tr -d '\r')"
fi
if [ -z "$GATE_CMD" ]; then
  echo "[capture-baseline] 실패: gate-cmd 없음 — .planning/gate-cmd 1줄 기록 후 재실행하거나 인자로 명령을 전달하라." >&2
  exit 1
fi

# 출력에서 실패 수 추출 — "N failed/failures/errors" 최대값. 못 찾으면:
#   exit 0 → 0 / exit!=0 → -1(카운트 불명, exit code 로만 판정).
# Stop훅의 회귀 판정과 동일한 규약을 공유한다.
extract_fail_count() {
  local out="$1" exit_code="$2" n
  n="$(printf '%s\n' "$out" | grep -oiE '[1-9][0-9]* +(fail(ed|ure|ures)?|errors?)' | grep -oE '^[0-9]+' | sort -rn | head -n1 || true)"
  if [ -n "$n" ]; then
    echo "$n"
  elif [ "$exit_code" -eq 0 ]; then
    echo 0
  else
    echo -1
  fi
}

# gate-cmd 실행 — eval 금지, bash -c. 출력·exit code 캡처.
gate_exit=0
out="$( (cd "$PROJ" && bash -c "$GATE_CMD") 2>&1 )" || gate_exit=$?

fail_count="$(extract_fail_count "$out" "$gate_exit")"
now="$(date +%s)"

[ -d "$PLAN" ] || mkdir -p "$PLAN"
jq -n --arg ts "$now" --arg cmd "$GATE_CMD" --argjson ex "$gate_exit" --argjson fc "$fail_count" \
  '{captured_at: ($ts|tonumber), gate_cmd: $cmd, baseline_exit: $ex, fail_count: $fc}' > "$BASELINE"

if [ "$gate_exit" -eq 0 ]; then
  echo "[capture-baseline] 클린 기준선 캡처 — gate-cmd green (회귀 게이트 = exit 0 유지). baseline.json 기록."
else
  if [ "$fail_count" -ge 0 ]; then
    echo "[capture-baseline] 경고: 기준선에 기존 실패 ${fail_count}개 존재 (exit=$gate_exit). 회귀 게이트는 '신규 실패 0 = fail_count <= ${fail_count}'로 동작한다. 기존 실패 선수정을 권장하나 강제하지 않는다." >&2
  else
    echo "[capture-baseline] 경고: 기준선이 red(exit=$gate_exit)이나 실패 수 파싱 불가. Stop훅은 exit code 로만 보수 판정한다 — 정확한 회귀 추적을 원하면 gate-cmd 를 카운트가 출력되는 명령으로 조정하라." >&2
  fi
fi
exit 0
