#!/usr/bin/env bash
# =============================================================================
# gate-screen.sh — 전사 계획 결정론 게이트 (/biz-screen 커맨드가 Bash 호출)
# 대상: .planning/enterprise/screen/*.json (최신), verdict: screen/verdict.json
# 검사:
#   ① categories 길이 == 5, 각 weight number, Σweight ∈ [0.999,1.001]
#   ② 각 score ∈ 1..5 정수
#   ③ disqualifiers ≥ 1, stop_rule 비공백
#   ④ annual_revenue_krw ≥ 기업결합 임계(기본 300억) → 경고(법 판단 legal 위임)
# --require-verdict: verdict.json items(APPROVE/REBASELINE/REJECT)·coverage 비공백,
#   non-APPROVE ≥1 → 실패(항목 나열).  기업결합 임계값 정본표는 strategy-frameworks 스킬.
# 통과 exit 0 / 실패 exit 1.
# =============================================================================
set -euo pipefail

PROJ="${CLAUDE_PROJECT_DIR:-.}"
SDIR="$PROJ/.planning/enterprise/screen"
VERDICT="$SDIR/verdict.json"
MERGER_KRW="${GATE_MERGER_KRW:-30000000000}"   # 300억 (기업결합신고 매출 임계 근사, legal 위임)
fail=0

REQUIRE_VERDICT=false
if [ "${1:-}" = "--require-verdict" ]; then REQUIRE_VERDICT=true; fi

if ! command -v jq >/dev/null 2>&1; then
  echo "[gate-screen] 실패: jq 미설치 — screen.json 검사 불가 (jq 설치 후 재실행)" >&2
  exit 1
fi

SCR="$( (cd "$SDIR" 2>/dev/null && ls -1 ./*.json 2>/dev/null | sed 's#.*/##' | grep -v '^verdict.json$' | sort | tail -n1) || true)"
if [ -z "$SCR" ]; then
  echo "[gate-screen] 실패: $SDIR/*.json (verdict 제외) 없음" >&2
  exit 1
fi
SCR="$SDIR/$SCR"
if ! jq -e '.categories | type=="array"' "$SCR" >/dev/null 2>&1; then
  echo "[gate-screen] 실패: categories 배열 없음(또는 JSON 파싱 불가)" >&2
  exit 1
fi

# ① categories 길이 5 + weight number + Σweight
n_cat="$(jq '.categories | length' "$SCR" 2>/dev/null || echo 0)"
case "$n_cat" in (''|*[!0-9]*) n_cat=0;; esac
if [ "$n_cat" -ne 5 ]; then
  echo "[gate-screen] 실패: categories 길이 $n_cat — 정확히 5 필요" >&2
  fail=1
fi
bad_w="$(jq -r '.categories[]? | select((.weight|type)!="number") | (.name // "?")' "$SCR" 2>/dev/null || true)"
if [ -n "$bad_w" ]; then
  echo "[gate-screen] 실패: weight 가 number 가 아닌 category — $(echo "$bad_w" | tr '\n' ' ')" >&2
  fail=1
else
  sumw="$(jq '[.categories[]?.weight // 0] | add // 0' "$SCR")"
  wv="$(awk -v s="$sumw" 'BEGIN{ print (s>=0.999 && s<=1.001)?"OK":"FAIL" }')"
  if [ "$wv" = "FAIL" ]; then
    echo "[gate-screen] 실패: Σweight=$sumw — 허용 [0.999,1.001] 위반" >&2
    fail=1
  fi
fi

# ② score ∈ 1..5 정수
bad_score="$(jq -r '.categories[]? | ((.score|numbers)//0) as $s | select(($s|floor)!=$s or $s<1 or $s>5) | (.name // "?")' "$SCR" 2>/dev/null || true)"
if [ -n "$bad_score" ]; then
  echo "[gate-screen] 실패: score 가 1..5 정수가 아닌 category — $(echo "$bad_score" | tr '\n' ' ')" >&2
  fail=1
fi

# ③ disqualifiers ≥ 1 + stop_rule 비공백
n_dq="$(jq '(.disqualifiers // []) | length' "$SCR" 2>/dev/null || echo 0)"
case "$n_dq" in (''|*[!0-9]*) n_dq=0;; esac
if [ "$n_dq" -lt 1 ]; then
  echo "[gate-screen] 실패: disqualifiers 0개 — 최소 1개 필요" >&2
  fail=1
fi
if ! jq -e '(.stop_rule // "") | type=="string" and (length>0)' "$SCR" >/dev/null 2>&1; then
  echo "[gate-screen] 실패: stop_rule 공백" >&2
  fail=1
fi

# ④ 기업결합 임계 교차 경고 (legal 위임)
rev="$(jq -r '.annual_revenue_krw // 0' "$SCR" 2>/dev/null || echo 0)"
cross="$(awk -v r="$rev" -v t="$MERGER_KRW" 'BEGIN{ print (r+0>=t+0)?"1":"0" }')"
if [ "$cross" = "1" ]; then
  echo "[gate-screen] 경고: annual_revenue_krw=$rev 가 기업결합 임계($MERGER_KRW) 교차 — 기업결합신고 요건은 legal 위임(정본표: strategy-frameworks)" >&2
fi

# --require-verdict
if [ "$REQUIRE_VERDICT" = true ]; then
  if [ ! -f "$VERDICT" ]; then
    echo "[gate-screen] 실패: --require-verdict — $VERDICT 없음 (plan-challenger 디스패치 필요)" >&2
    fail=1
  else
    if ! jq -e '(.items | type=="array") and (.coverage | type=="array" and length>0)' "$VERDICT" >/dev/null 2>&1; then
      echo "[gate-screen] 실패: verdict.json items 배열/coverage 비공백 배열 요건 위반" >&2
      fail=1
    fi
    bad_enum="$(jq -r '.items[]? | select((.verdict|IN("APPROVE","REBASELINE","REJECT"))|not) | (.id // "?")' "$VERDICT" 2>/dev/null || true)"
    if [ -n "$bad_enum" ]; then
      echo "[gate-screen] 실패: verdict enum 위반(APPROVE/REBASELINE/REJECT 아님) — $(echo "$bad_enum" | tr '\n' ' ')" >&2
      fail=1
    fi
    non_approve="$(jq -r '.items[]? | select(.verdict != "APPROVE") | "\(.id // "?"):\(.verdict)"' "$VERDICT" 2>/dev/null || true)"
    if [ -n "$non_approve" ]; then
      echo "[gate-screen] 실패: non-APPROVE 판정 항목 존재(해소 필요) — $(echo "$non_approve" | tr '\n' ' ')" >&2
      fail=1
    fi
  fi
fi

if [ "$fail" -eq 0 ]; then
  echo "[gate-screen] 통과: $(basename "$SCR") — categories(5)·Σweight·score·disqualifier·stop_rule 검증 완료$([ "$REQUIRE_VERDICT" = true ] && echo ' (+verdict)')"
fi
exit "$fail"
