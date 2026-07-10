#!/usr/bin/env bash
# =============================================================================
# gate-budget.sh — 전사 계획 결정론 게이트 (최강 산술 게이트, /annual-plan 커맨드가 Bash 호출)
# 대상: .planning/enterprise/budget-*.json (최신)
# 정본 참조: fpna-planning references/clap-keys.json (CLAP 5키) — 하드코딩 금지
# 검사:
#   ① |Σdepartments.total_krw − org_total_krw| / org_total_krw > 0.005 → 실패
#   ② scenarios base/best/worst number && worst ≤ base ≤ best
#   ③ clap 키 집합 == 정본 5키, 각 값 비공백
#   ④ assumptions ≥ 3
# 통과 exit 0 / 실패 exit 1.
# =============================================================================
set -euo pipefail

PROJ="${CLAUDE_PROJECT_DIR:-.}"
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
BDIR="$PROJ/.planning/enterprise"
CLAP="$SELF_DIR/../../skills/fpna-planning/references/clap-keys.json"
fail=0

if ! command -v jq >/dev/null 2>&1; then
  echo "[gate-budget] 실패: jq 미설치 — budget.json 검사 불가 (jq 설치 후 재실행)" >&2
  exit 1
fi
if [ ! -f "$CLAP" ]; then
  echo "[gate-budget] 실패: 정본 참조 파일 없음 — $CLAP (fpna-planning 스킬 references)" >&2
  exit 1
fi

# 최신 budget-*.json (파일명 사전식 최대)
BUDGET="$( (cd "$BDIR" 2>/dev/null && ls -1 budget-*.json 2>/dev/null | sort | tail -n1) || true)"
if [ -z "$BUDGET" ]; then
  echo "[gate-budget] 실패: $BDIR/budget-*.json 없음" >&2
  exit 1
fi
BUDGET="$BDIR/$BUDGET"
if ! jq -e '.' "$BUDGET" >/dev/null 2>&1; then
  echo "[gate-budget] 실패: $BUDGET JSON 파싱 불가" >&2
  exit 1
fi

# ① 부서 합 == 전사 (±0.5%)
org="$(jq -r '.org_total_krw // "null"' "$BUDGET")"
if [ "$org" = "null" ] || ! jq -e '(.org_total_krw|type=="number") and (.org_total_krw>0)' "$BUDGET" >/dev/null 2>&1; then
  echo "[gate-budget] 실패: org_total_krw 가 양수 number 가 아님" >&2
  fail=1
else
  sumdept="$(jq '[.departments[]?.total_krw // 0] | add // 0' "$BUDGET")"
  verdict="$(awk -v o="$org" -v s="$sumdept" 'BEGIN{ d=s-o; if(d<0)d=-d; print (d/o>0.005)?"FAIL":"OK" }')"
  if [ "$verdict" = "FAIL" ]; then
    echo "[gate-budget] 실패: Σ부서 total_krw($sumdept) ≠ org_total_krw($org) — 허용오차 ±0.5% 초과" >&2
    fail=1
  fi
fi

# ② scenarios 3키 number + worst ≤ base ≤ best
if ! jq -e '(.scenarios.base|type=="number") and (.scenarios.best|type=="number") and (.scenarios.worst|type=="number")' "$BUDGET" >/dev/null 2>&1; then
  echo "[gate-budget] 실패: scenarios base/best/worst 가 모두 number 가 아님" >&2
  fail=1
elif ! jq -e '(.scenarios.worst <= .scenarios.base) and (.scenarios.base <= .scenarios.best)' "$BUDGET" >/dev/null 2>&1; then
  echo "[gate-budget] 실패: scenarios 순서 위반 — worst ≤ base ≤ best 아님" >&2
  fail=1
fi

# ③ clap 키 집합 == 정본 5키 + 값 비공백
ref_keys="$(jq -r '.keys[]' "$CLAP" | sort -u)"
clap_keys="$(jq -r '(.clap // {}) | keys[]?' "$BUDGET" | sort -u)"
if [ "$ref_keys" != "$clap_keys" ]; then
  miss="$(comm -23 <(printf '%s\n' "$ref_keys") <(printf '%s\n' "$clap_keys") | tr '\n' ' ')"
  ext="$(comm -13 <(printf '%s\n' "$ref_keys") <(printf '%s\n' "$clap_keys") | tr '\n' ' ')"
  echo "[gate-budget] 실패: clap 키 집합이 정본(CLAP 5키)과 불일치 — 누락:[$miss] 초과:[$ext]" >&2
  fail=1
fi
blank_clap="$(jq -r --slurpfile ref "$CLAP" '([$ref[0].keys[]]) as $k | (.clap // {}) as $c | $k[] | select(($c[.]) == null or ($c[.]) == "")' "$BUDGET" 2>/dev/null || true)"
if [ -n "$blank_clap" ]; then
  echo "[gate-budget] 실패: clap 값 공백 키 — $(echo "$blank_clap" | tr '\n' ' ')" >&2
  fail=1
fi

# ④ assumptions ≥ 3
n_assum="$(jq '(.assumptions // []) | length' "$BUDGET" 2>/dev/null || echo 0)"
case "$n_assum" in (''|*[!0-9]*) n_assum=0;; esac
if [ "$n_assum" -lt 3 ]; then
  echo "[gate-budget] 실패: assumptions ${n_assum}개 — 최소 3개 필요" >&2
  fail=1
fi

if [ "$fail" -eq 0 ]; then
  echo "[gate-budget] 통과: $(basename "$BUDGET") — Σ부서=전사(±0.5%)·시나리오·CLAP 5키·assumptions 검증 완료"
fi
exit "$fail"
