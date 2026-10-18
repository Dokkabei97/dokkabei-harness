#!/usr/bin/env bash
# =============================================================================
# gate-error-budget.sh — 에러버짓 게이트 (판정 결정론, SLI 입력은 observe/infra-otel 연계)
# 정본: governance-templates 스킬 references/slo-template.md. SLI 수집기 자체 구현 금지.
# 검사:
#   ① .planning/gov/slo/thresholds.yaml 부재 → /gov-slo 안내 exit 1
#      → flat "error_budget_min_pct: <num>" 를 grep/sed 로 추출(yq 금지)
#   ② .planning/gov/slo/budget.json 부재 → "미측정" exit 2 (gate-eval 선례)
#   ③ jq 로 error_budget_remaining_pct 추출 → remaining >= min 산술 판정
# 3분기: 통과(exit 0) / 소진(exit 1) / 미측정(exit 2). 인자 없이 동작(루프 gate-cmd 직결).
# =============================================================================
set -euo pipefail

PROJ="${CLAUDE_PROJECT_DIR:-.}"
THRESH="$PROJ/.planning/gov/slo/thresholds.yaml"
BUDGET="$PROJ/.planning/gov/slo/budget.json"

if ! command -v jq >/dev/null 2>&1; then
  echo "[gate-error-budget] 실패: jq 미설치 — budget.json 판정 불가 (jq 설치 후 재실행)" >&2
  exit 1
fi

# ① thresholds.yaml → error_budget_min_pct
if [ ! -f "$THRESH" ]; then
  echo "[gate-error-budget] 실패: $THRESH 없음 — /gov-slo 로 SLO·에러버짓 임계값을 먼저 정의하세요." >&2
  exit 1
fi
MIN="$(grep -E '^error_budget_min_pct:' "$THRESH" | head -n1 | sed -E 's/^error_budget_min_pct:[[:space:]]*//' | tr -d '\r"' || true)"
case "$MIN" in
  (''|*[!0-9.]*) echo "[gate-error-budget] 실패: thresholds.yaml 에 'error_budget_min_pct: <숫자>' 항목이 없거나 숫자가 아님" >&2; exit 1;;
esac

# ② budget.json 부재 → 미측정(exit 2)
if [ ! -f "$BUDGET" ]; then
  echo "[gate-error-budget] 미측정: $BUDGET 없음 — 에러버짓 잔량이 한 번도 측정되지 않았습니다." >&2
  echo "[gate-error-budget] SLI 실측은 observe 플러그인·infra/otel 스택 연계로 채우세요(자체 수집기 구현 금지)." >&2
  exit 2
fi

# ③ remaining >= min
REMAIN="$(jq -r '.error_budget_remaining_pct // empty' "$BUDGET" 2>/dev/null || true)"
case "$REMAIN" in
  (''|*[!0-9.-]*) echo "[gate-error-budget] 실패: budget.json 에 error_budget_remaining_pct 숫자 필드가 없음" >&2; exit 1;;
esac

PASS="$(awk -v r="$REMAIN" -v m="$MIN" 'BEGIN { print (r+0 >= m+0) ? "1" : "0" }')"
if [ "$PASS" = "1" ]; then
  echo "[gate-error-budget] 통과: 에러버짓 잔량 ${REMAIN}% >= 최소 ${MIN}%"
  exit 0
else
  echo "[gate-error-budget] 실패: 에러버짓 잔량 ${REMAIN}% < 최소 ${MIN}% — 소진. 릴리즈 계열 차단(안정화 우선)." >&2
  exit 1
fi
