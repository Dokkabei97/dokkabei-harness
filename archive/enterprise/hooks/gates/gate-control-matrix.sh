#!/usr/bin/env bash
# =============================================================================
# gate-control-matrix.sh — GRC 결정론 게이트 (/control-matrix 커맨드가 Bash 호출)
# 대상: .planning/grc/control-matrix.json  (크로스: .planning/grc/risk-register.json)
# 검사:
#   ① 필수 필드(id/risk_ids/name/type/line/owner/frequency/status) + id 중복 0
#   ② type ∈ {preventive,detective}, line ∈ {1,2,3}
#   ③ status==implemented 인데 evidence_path 파일 부재 → 실패
#   ④ [크로스, 양쪽 존재 시만] risk_ids 가 register 에 실재 / register 의 high·critical 무통제 0건
#   ⑤ 2·3선(line 2 또는 3) 통제 0건 → 경고(무영향)
# 통과 exit 0 / 실패 exit 1.
# =============================================================================
set -euo pipefail

PROJ="${CLAUDE_PROJECT_DIR:-.}"
CM="$PROJ/.planning/grc/control-matrix.json"
REG="$PROJ/.planning/grc/risk-register.json"
fail=0

if ! command -v jq >/dev/null 2>&1; then
  echo "[gate-control-matrix] 실패: jq 미설치 — control-matrix.json 검사 불가 (jq 설치 후 재실행)" >&2
  exit 1
fi
if [ ! -f "$CM" ]; then
  echo "[gate-control-matrix] 실패: $CM 없음" >&2
  exit 1
fi
if ! jq -e '.controls | type == "array"' "$CM" >/dev/null 2>&1; then
  echo "[gate-control-matrix] 실패: controls 배열 없음(또는 JSON 파싱 불가)" >&2
  exit 1
fi

# ① 필수 필드 + id 중복
if ! jq -e '[.controls[] | has("id") and has("risk_ids") and has("name") and has("type") and has("line") and has("owner") and has("frequency") and has("status")] | all' "$CM" >/dev/null 2>&1; then
  echo "[gate-control-matrix] 실패: 필수 필드 누락 control 존재 (id/risk_ids/name/type/line/owner/frequency/status)" >&2
  fail=1
fi
if ! jq -e '(.controls|map(.id)|length) == (.controls|map(.id)|unique|length)' "$CM" >/dev/null 2>&1; then
  echo "[gate-control-matrix] 실패: 중복된 control id 존재" >&2
  fail=1
fi

# ② type / line enum
bad_type="$(jq -r '.controls[]? | select((.type|IN("preventive","detective"))|not) | (.id // "?")' "$CM" 2>/dev/null || true)"
if [ -n "$bad_type" ]; then
  echo "[gate-control-matrix] 실패: type enum 위반(preventive/detective 아님) — $(echo "$bad_type" | tr '\n' ' ')" >&2
  fail=1
fi
bad_line="$(jq -r '.controls[]? | select((.line|IN(1,2,3))|not) | (.id // "?")' "$CM" 2>/dev/null || true)"
if [ -n "$bad_line" ]; then
  echo "[gate-control-matrix] 실패: line enum 위반(1/2/3 아님) — $(echo "$bad_line" | tr '\n' ' ')" >&2
  fail=1
fi

# ③ status==implemented && evidence 파일 부재
while IFS=$'\t' read -r cid cpath; do
  [ -z "$cid" ] && continue
  if [ -z "$cpath" ] || [ "$cpath" = "null" ]; then
    echo "[gate-control-matrix] 실패: implemented control 에 evidence_path 없음 — $cid" >&2
    fail=1
    continue
  fi
  case "$cpath" in
    /*) abs="$cpath" ;;
    *)  abs="$PROJ/$cpath" ;;
  esac
  if [ ! -e "$abs" ]; then
    echo "[gate-control-matrix] 실패: implemented control 의 evidence_path 파일 부재 — $cid ($cpath)" >&2
    fail=1
  fi
done < <(jq -r '.controls[]? | select(.status=="implemented") | "\(.id // "?")\t\(.evidence_path // "")"' "$CM" 2>/dev/null || true)

# ④ 크로스파일 (register 존재 시만)
if [ -f "$REG" ] && jq -e '.risks | type=="array"' "$REG" >/dev/null 2>&1; then
  dangling="$(jq -r --slurpfile r "$REG" '([$r[0].risks[]?.id]) as $rids | .controls[]? | .id as $cid | (.risk_ids // [])[] | select(. as $x | ($rids|index($x))|not) | "\($cid)->\(.)"' "$CM" 2>/dev/null || true)"
  if [ -n "$dangling" ]; then
    echo "[gate-control-matrix] 실패: register 에 없는 risk_ids 참조 — $(echo "$dangling" | tr '\n' ' ')" >&2
    fail=1
  fi
  uncontrolled="$(jq -r --slurpfile c "$CM" '([$c[0].controls[]?.risk_ids[]?]) as $mapped | .risks[]? | select(.level=="high" or .level=="critical") | select(.id as $id | ($mapped|index($id))|not) | "\(.id)(\(.level))"' "$REG" 2>/dev/null || true)"
  if [ -n "$uncontrolled" ]; then
    echo "[gate-control-matrix] 실패: high·critical 리스크 무통제(매핑된 통제 0건) — $(echo "$uncontrolled" | tr '\n' ' ')" >&2
    fail=1
  fi
else
  echo "[gate-control-matrix] 경고: risk-register.json 부재 — 크로스 검증(risk_ids 실재·무통제) 생략" >&2
fi

# ⑤ 2·3선 통제 0건 경고
n_23="$(jq '[.controls[]? | select(.line==2 or .line==3)] | length' "$CM" 2>/dev/null || echo 0)"
case "$n_23" in (''|*[!0-9]*) n_23=0;; esac
if [ "$n_23" -eq 0 ]; then
  echo "[gate-control-matrix] 경고: 2선·3선(line 2/3) 통제 0건 — IIA Three Lines(2020) 방어선 공백. 관리·감사 통제 보강 권고." >&2
fi

if [ "$fail" -eq 0 ]; then
  n="$(jq '.controls | length' "$CM" 2>/dev/null || echo 0)"
  echo "[gate-control-matrix] 통과: control ${n}건 — 필드·type/line·증적·크로스(risk_ids/무통제) 검증 완료"
fi
exit "$fail"
