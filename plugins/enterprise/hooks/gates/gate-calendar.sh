#!/usr/bin/env bash
# =============================================================================
# gate-calendar.sh — GRC 결정론 게이트 (/comp-calendar 커맨드가 Bash 호출)
# 대상: .planning/grc/compliance-calendar.json
# 검사:
#   ① duties 필수 필드(id/title/basis/due/owner/recurrence/status)
#   ② status ∈ {open,done,waived}
#   ③ status==done → evidence_path 비공백
#   ④ status==open && due < TODAY → 실패(도과)
#   ⑤ status==open && TODAY ≤ due ≤ TODAY+14일 → 경고 "D-14"(exit 무영향)
# 날짜: TODAY=GATE_TODAY|date +%F, 도과는 사전식 비교, D-14 는 BSD/GNU date 이중 관용구.
# 통과 exit 0 / 실패 exit 1.
# =============================================================================
set -euo pipefail

PROJ="${CLAUDE_PROJECT_DIR:-.}"
CAL="$PROJ/.planning/grc/compliance-calendar.json"
TODAY="${GATE_TODAY:-$(date +%F)}"
fail=0

to_epoch() { date -j -f %Y-%m-%d "$1" +%s 2>/dev/null || date -d "$1" +%s 2>/dev/null || echo ""; }

if ! command -v jq >/dev/null 2>&1; then
  echo "[gate-calendar] 실패: jq 미설치 — compliance-calendar.json 검사 불가 (jq 설치 후 재실행)" >&2
  exit 1
fi
if [ ! -f "$CAL" ]; then
  echo "[gate-calendar] 실패: $CAL 없음" >&2
  exit 1
fi
if ! jq -e '.duties | type == "array"' "$CAL" >/dev/null 2>&1; then
  echo "[gate-calendar] 실패: duties 배열 없음(또는 JSON 파싱 불가)" >&2
  exit 1
fi

# ① 필수 필드
if ! jq -e '[.duties[] | has("id") and has("title") and has("basis") and has("due") and has("owner") and has("recurrence") and has("status")] | all' "$CAL" >/dev/null 2>&1; then
  echo "[gate-calendar] 실패: 필수 필드 누락 duty 존재 (id/title/basis/due/owner/recurrence/status)" >&2
  fail=1
fi

# ② status enum
bad_status="$(jq -r '.duties[]? | select((.status|IN("open","done","waived"))|not) | (.id // "?")' "$CAL" 2>/dev/null || true)"
if [ -n "$bad_status" ]; then
  echo "[gate-calendar] 실패: status enum 위반(open/done/waived 아님) — $(echo "$bad_status" | tr '\n' ' ')" >&2
  fail=1
fi

# ③ done → evidence_path 비공백 (중대재해법 등 실질 운영 증적)
no_ev="$(jq -r '.duties[]? | select(.status=="done") | select((.evidence_path // "") == "") | (.id // "?")' "$CAL" 2>/dev/null || true)"
if [ -n "$no_ev" ]; then
  echo "[gate-calendar] 실패: done 이행인데 evidence_path 공백 — $(echo "$no_ev" | tr '\n' ' ')" >&2
  fail=1
fi

# ④ open && due < TODAY (도과)
overdue="$(jq -r --arg today "$TODAY" '.duties[]? | select(.status=="open") | select((.due // "9999-99-99") < $today) | "\(.id // "?")(due=\(.due))"' "$CAL" 2>/dev/null || true)"
if [ -n "$overdue" ]; then
  echo "[gate-calendar] 실패: 기한 도과 open 의무 — $(echo "$overdue" | tr '\n' ' ')" >&2
  fail=1
fi

# ⑤ D-14 경고 (오늘 ≤ due ≤ 오늘+14일)
today_epoch="$(to_epoch "$TODAY")"
if [ -n "$today_epoch" ]; then
  plus14=$(( today_epoch + 14*86400 ))
  while IFS=$'\t' read -r did ddue; do
    [ -z "$did" ] && continue
    [ "$ddue" \< "$TODAY" ] && continue   # 도과는 ④에서 처리
    de="$(to_epoch "$ddue")"
    [ -z "$de" ] && continue
    if [ "$de" -le "$plus14" ]; then
      echo "[gate-calendar] 경고: D-14 임박 의무 — $did (due=$ddue)" >&2
    fi
  done < <(jq -r '.duties[]? | select(.status=="open") | "\(.id // "?")\t\(.due // "")"' "$CAL" 2>/dev/null || true)
fi

if [ "$fail" -eq 0 ]; then
  echo "[gate-calendar] 통과: duty 필드·status·done증적·기한도과 검증 완료 (D-14 경고는 별도)"
fi
exit "$fail"
