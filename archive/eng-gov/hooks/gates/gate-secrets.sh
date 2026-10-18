#!/usr/bin/env bash
# =============================================================================
# gate-secrets.sh — 시크릿 스캔 게이트 (gitleaks exit 0/1 계약 전파)
# 정본: supply-chain-guide 스킬. baseline 로 "기존 시크릿은 무시, 신규만 차단".
# 정책: 등록된 게이트의 도구 부재는 fail-closed(exit 1) — skip green 은 심사 허위 증적이 되므로
#       금지. skip 판단은 /gov-init 의 gates.json 등록 시점(enabled:false)으로 이동.
# 검사:
#   ① command -v $GITLEAKS_BIN (기본 gitleaks) 부재 → 설치 안내 exit 1
#   ② .planning/gov/gitleaks-baseline.json 존재 시 --baseline-path 추가(신규 시크릿만)
#   ③ gitleaks git --no-banner --exit-code 1 실행 exit 그대로 전파
# 인자 없이 동작(루프 gate-cmd 직결). 통과 exit 0 / 실패 exit 1.
# =============================================================================
set -euo pipefail

PROJ="${CLAUDE_PROJECT_DIR:-.}"
GITLEAKS_BIN="${GITLEAKS_BIN:-gitleaks}"
BASELINE="$PROJ/.planning/gov/gitleaks-baseline.json"

# ① 도구 존재 (fail-closed)
if ! command -v "$GITLEAKS_BIN" >/dev/null 2>&1; then
  echo "[gate-secrets] 실패: '$GITLEAKS_BIN' 미설치 — 설치: brew install gitleaks (또는 GITLEAKS_BIN 오버라이드). 설치 불가 시 /gov-init 재실행으로 gates.json 에서 enabled:false 등록." >&2
  exit 1
fi

# ②③ baseline 유무에 따라 인자 구성 후 실행 — exit 전파
gl_exit=0
if [ -f "$BASELINE" ]; then
  out="$( (cd "$PROJ" && "$GITLEAKS_BIN" git --no-banner --exit-code 1 --baseline-path "$BASELINE") 2>&1 )" || gl_exit=$?
else
  out="$( (cd "$PROJ" && "$GITLEAKS_BIN" git --no-banner --exit-code 1) 2>&1 )" || gl_exit=$?
fi

if [ "$gl_exit" -ne 0 ]; then
  echo "[gate-secrets] 실패: gitleaks 신규 시크릿 탐지 (exit=$gl_exit). 오탐이면 baseline 갱신(supply-chain-guide 스킬 §baseline)." >&2
  printf '%s\n' "$out" | tail -10 >&2
  exit "$gl_exit"
fi

if [ -f "$BASELINE" ]; then
  echo "[gate-secrets] 통과: gitleaks 신규 시크릿 0건 (baseline 적용)"
else
  echo "[gate-secrets] 통과: gitleaks 시크릿 0건 (baseline 없음 — 전수 스캔)"
fi
exit 0
