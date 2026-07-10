#!/usr/bin/env bash
# =============================================================================
# gate-risk-register.sh — GRC 결정론 게이트 (훅 미등록, /risk-register 커맨드가 Bash 호출)
# 대상: .planning/grc/risk-register.json
# 검사:
#   ① 필수 필드(id/title/category/likelihood/impact/score/level/owner/response/next_review)
#   ② likelihood·impact ∈ 1..5 정수
#   ③ id 중복 0
#   ④ score == likelihood × impact (재계산)
#   ⑤ level == 5x5 매핑 (grc-frameworks references/risk-matrix.json 정본 재계산 — 하드코딩 금지)
#   ⑥ level==critical & response.actions 0건 → 실패
#   ⑦ next_review < TODAY → 실패
# --require-verdict: grc/verdict.json 존재 + items 가 전 risk id 커버 + coverage 비공백
#   + verdict ∈ {ACCEPT,REMEDIATE,ESCALATE}, non-ACCEPT ≥1 → 실패(항목 나열, ESCALATE 는 legal 위임 안내)
# 통과 exit 0 / 실패 exit 1. 위반은 stderr "[gate-risk-register] 실패: …" 1줄씩 누적.
# =============================================================================
set -euo pipefail

PROJ="${CLAUDE_PROJECT_DIR:-.}"
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
REG="$PROJ/.planning/grc/risk-register.json"
VERDICT="$PROJ/.planning/grc/verdict.json"
MATRIX="$SELF_DIR/../../skills/grc-frameworks/references/risk-matrix.json"
TODAY="${GATE_TODAY:-$(date +%F)}"
fail=0

REQUIRE_VERDICT=false
if [ "${1:-}" = "--require-verdict" ]; then REQUIRE_VERDICT=true; fi

if ! command -v jq >/dev/null 2>&1; then
  echo "[gate-risk-register] 실패: jq 미설치 — risk-register.json 검사 불가 (jq 설치 후 재실행)" >&2
  exit 1
fi
if [ ! -f "$REG" ]; then
  echo "[gate-risk-register] 실패: $REG 없음" >&2
  exit 1
fi
if [ ! -f "$MATRIX" ]; then
  echo "[gate-risk-register] 실패: 정본 참조 파일 없음 — $MATRIX (grc-frameworks 스킬 references)" >&2
  exit 1
fi
if ! jq -e '.risks | type == "array"' "$REG" >/dev/null 2>&1; then
  echo "[gate-risk-register] 실패: risks 배열 없음(또는 JSON 파싱 불가)" >&2
  exit 1
fi

# ① 필수 필드
if ! jq -e '[.risks[] | has("id") and has("title") and has("category") and has("likelihood") and has("impact") and has("score") and has("level") and has("owner") and has("response") and has("next_review")] | all' "$REG" >/dev/null 2>&1; then
  echo "[gate-risk-register] 실패: 필수 필드 누락 risk 존재 (id/title/category/likelihood/impact/score/level/owner/response/next_review)" >&2
  fail=1
fi

# ② likelihood·impact ∈ 1..5 정수
bad_range="$(jq -r '.risks[]? | ((.likelihood|numbers) // 0) as $l | ((.impact|numbers) // 0) as $i | select(($l|floor)!=$l or ($i|floor)!=$i or $l<1 or $l>5 or $i<1 or $i>5) | (.id // "?")' "$REG" 2>/dev/null || true)"
if [ -n "$bad_range" ]; then
  echo "[gate-risk-register] 실패: likelihood·impact 가 1..5 정수가 아닌 risk — $(echo "$bad_range" | tr '\n' ' ')" >&2
  fail=1
fi

# ③ id 중복
if ! jq -e '(.risks|map(.id)|length) == (.risks|map(.id)|unique|length)' "$REG" >/dev/null 2>&1; then
  echo "[gate-risk-register] 실패: 중복된 risk id 존재" >&2
  fail=1
fi

# ④ score == likelihood × impact
bad_score="$(jq -r '.risks[]? | ((.likelihood|numbers)//0) as $l | ((.impact|numbers)//0) as $i | select((.score) != ($l*$i)) | "\(.id // "?")(score=\(.score) 기대=\($l*$i))"' "$REG" 2>/dev/null || true)"
if [ -n "$bad_score" ]; then
  echo "[gate-risk-register] 실패: score≠likelihood×impact — $(echo "$bad_score" | tr '\n' ' ')" >&2
  fail=1
fi

# ⑤ level == 5x5 매핑 재계산 (risk-matrix.json 정본)
bad_level="$(jq -r --slurpfile m "$MATRIX" '.risks[]? | ((.likelihood|numbers)//0|tostring) as $l | ((.impact|numbers)//0|tostring) as $i | ($m[0].matrix[$l][$i]) as $exp | select(.level != $exp) | "\(.id // "?")(level=\(.level) 기대=\($exp // "매핑없음"))"' "$REG" 2>/dev/null || true)"
if [ -n "$bad_level" ]; then
  echo "[gate-risk-register] 실패: level 이 5x5 매핑과 불일치 — $(echo "$bad_level" | tr '\n' ' ')" >&2
  fail=1
fi

# ⑥ critical & actions 0건
no_action="$(jq -r '.risks[]? | select(.level=="critical") | select((.response.actions // []) | length == 0) | (.id // "?")' "$REG" 2>/dev/null || true)"
if [ -n "$no_action" ]; then
  echo "[gate-risk-register] 실패: critical 리스크에 대응 action 0건 — $(echo "$no_action" | tr '\n' ' ')" >&2
  fail=1
fi

# ⑦ next_review 도과 (YYYY-MM-DD 사전식 비교)
overdue="$(jq -r --arg today "$TODAY" '.risks[]? | select((.next_review // "9999-99-99") < $today) | "\(.id // "?")(next_review=\(.next_review))"' "$REG" 2>/dev/null || true)"
if [ -n "$overdue" ]; then
  echo "[gate-risk-register] 실패: next_review 도과 리스크 — $(echo "$overdue" | tr '\n' ' ')" >&2
  fail=1
fi

# --require-verdict: checker 판정 물화 검사
if [ "$REQUIRE_VERDICT" = true ]; then
  if [ ! -f "$VERDICT" ]; then
    echo "[gate-risk-register] 실패: --require-verdict — $VERDICT 없음 (grc-challenger 디스패치 필요)" >&2
    fail=1
  else
    if ! jq -e '(.items | type=="array") and (.coverage | type=="array" and length>0)' "$VERDICT" >/dev/null 2>&1; then
      echo "[gate-risk-register] 실패: verdict.json items 배열/coverage 비공백 배열 요건 위반" >&2
      fail=1
    fi
    bad_enum="$(jq -r '.items[]? | select((.verdict|IN("ACCEPT","REMEDIATE","ESCALATE"))|not) | (.id // "?")' "$VERDICT" 2>/dev/null || true)"
    if [ -n "$bad_enum" ]; then
      echo "[gate-risk-register] 실패: verdict enum 위반(ACCEPT/REMEDIATE/ESCALATE 아님) — $(echo "$bad_enum" | tr '\n' ' ')" >&2
      fail=1
    fi
    uncovered="$(jq -r --slurpfile v "$VERDICT" '([$v[0].items[]?.id]) as $c | .risks[]?.id | select(. as $id | ($c | index($id)) | not)' "$REG" 2>/dev/null || true)"
    if [ -n "$uncovered" ]; then
      echo "[gate-risk-register] 실패: verdict 가 커버하지 않은 risk id — $(echo "$uncovered" | tr '\n' ' ')" >&2
      fail=1
    fi
    non_accept="$(jq -r '.items[]? | select(.verdict != "ACCEPT") | "\(.id // "?"):\(.verdict)"' "$VERDICT" 2>/dev/null || true)"
    if [ -n "$non_accept" ]; then
      echo "[gate-risk-register] 실패: non-ACCEPT 판정 항목 존재(해소 필요) — $(echo "$non_accept" | tr '\n' ' ')" >&2
      fail=1
    fi
    escalate="$(jq -r '.items[]? | select(.verdict=="ESCALATE") | (.id // "?")' "$VERDICT" 2>/dev/null || true)"
    if [ -n "$escalate" ]; then
      echo "[gate-risk-register] 경고: ESCALATE 항목은 legal 위임(corporate law·M&A/규제 신고·privacy 등 법적 판단) — $(echo "$escalate" | tr '\n' ' ')" >&2
    fi
  fi
fi

if [ "$fail" -eq 0 ]; then
  n="$(jq '.risks | length' "$REG" 2>/dev/null || echo 0)"
  echo "[gate-risk-register] 통과: risk ${n}건 — 필드·1..5·score·level(5x5)·critical대응·next_review 검증 완료$([ "$REQUIRE_VERDICT" = true ] && echo ' (+verdict)')"
fi
exit "$fail"
