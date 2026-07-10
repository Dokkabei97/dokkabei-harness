#!/usr/bin/env bash
# =============================================================================
# gate-variance.sh — 전사 계획 결정론 게이트 (/rolling-forecast 커맨드가 Bash 호출)
# 대상: .planning/enterprise/variance/*.json (최신)
# 검사:
#   ① lines[] plan·actual 이 number
#   ② |variance − (actual − plan)| > 0.01 → 실패(라인 나열, 재계산 검증)
#   ③ |variance_pct| > threshold_pct 인 라인의 derp 4키(describe/explain/respond/prevent) 공백 → 실패
# DERP 4키 정본(서술): fpna-planning references/derp-template.md (Farseer DERP)
# 통과 exit 0 / 실패 exit 1.
# =============================================================================
set -euo pipefail

PROJ="${CLAUDE_PROJECT_DIR:-.}"
VDIR="$PROJ/.planning/enterprise/variance"
fail=0

if ! command -v jq >/dev/null 2>&1; then
  echo "[gate-variance] 실패: jq 미설치 — variance.json 검사 불가 (jq 설치 후 재실행)" >&2
  exit 1
fi

VAR="$( (cd "$VDIR" 2>/dev/null && ls -1 ./*.json 2>/dev/null | sed 's#.*/##' | sort | tail -n1) || true)"
if [ -z "$VAR" ]; then
  echo "[gate-variance] 실패: $VDIR/*.json 없음" >&2
  exit 1
fi
VAR="$VDIR/$VAR"
if ! jq -e '.lines | type == "array"' "$VAR" >/dev/null 2>&1; then
  echo "[gate-variance] 실패: lines 배열 없음(또는 JSON 파싱 불가)" >&2
  exit 1
fi

# threshold_pct (기본 10, 비정상 시 10)
thr="$(jq -r '.threshold_pct // 10' "$VAR" 2>/dev/null || echo 10)"
case "$thr" in (''|*[!0-9.]*) thr=10;; esac

# ① plan·actual number
bad_num="$(jq -r '.lines[]? | select(((.plan|type)!="number") or ((.actual|type)!="number")) | (.item // "?")' "$VAR" 2>/dev/null || true)"
if [ -n "$bad_num" ]; then
  echo "[gate-variance] 실패: plan·actual 이 number 가 아닌 라인 — $(echo "$bad_num" | tr '\n' ' ')" >&2
  fail=1
fi

# ② variance == actual − plan (±0.01 재계산)
bad_var="$(jq -r '.lines[]? | ((.plan|numbers)//0) as $p | ((.actual|numbers)//0) as $a | ((.variance|numbers)//0) as $v | select((($v-($a-$p)) | if .<0 then -. else . end) > 0.01) | "\(.item // "?")(variance=\(.variance) 기대=\($a-$p))"' "$VAR" 2>/dev/null || true)"
if [ -n "$bad_var" ]; then
  echo "[gate-variance] 실패: variance ≠ actual−plan 재계산 불일치 — $(echo "$bad_var" | tr '\n' ' ')" >&2
  fail=1
fi

# ③ |variance_pct| > threshold_pct 라인의 derp 4키 공백
derp_blank="$(jq -r --argjson thr "$thr" '.lines[]? | ((.variance_pct|numbers)//0) as $vp | select(($vp | if .<0 then -. else . end) > $thr) | select(((.derp.describe // "")=="") or ((.derp.explain // "")=="") or ((.derp.respond // "")=="") or ((.derp.prevent // "")=="")) | (.item // "?")' "$VAR" 2>/dev/null || true)"
if [ -n "$derp_blank" ]; then
  echo "[gate-variance] 실패: 임계(|variance_pct|>${thr}%) 초과 라인의 DERP 4키 공백 — $(echo "$derp_blank" | tr '\n' ' ')" >&2
  fail=1
fi

if [ "$fail" -eq 0 ]; then
  echo "[gate-variance] 통과: $(basename "$VAR") — plan/actual·variance 재계산·임계초과 DERP 검증 완료 (threshold=${thr}%)"
fi
exit "$fail"
