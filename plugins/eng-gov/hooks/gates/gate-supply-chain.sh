#!/usr/bin/env bash
# =============================================================================
# gate-supply-chain.sh — 공급망 게이트 (syft SBOM → grype 취약점 → 라이선스 denylist)
# 정본: supply-chain-guide 스킬 references/license-denylist.json.
# 정책: 등록된 게이트의 도구 부재는 fail-closed(exit 1) — SBOM/CVE skip green 은
#       SOC 2/ISO 27001 허위 증적. skip 은 /gov-init gates.json enabled:false 로 이동.
# 검사:
#   ① syft·grype(기본 syft/grype, SYFT_BIN·GRYPE_BIN 오버라이드) 존재 — 부재 fail-closed
#   ② syft scan dir:$PROJ -o syft-json → SBOM 생성
#   ③ grype sbom:… --fail-on high → 취약점 exit 캡처
#   ④ SBOM 라이선스 × denylist(프로젝트 .planning/gov/license-denylist.json 우선,
#      없으면 스킬 references/license-denylist.json) 대조
# 종합 판정: ③ 또는 ④ 위반 시 exit 1. 인자 없이 동작(루프 gate-cmd 직결).
# =============================================================================
set -euo pipefail

PROJ="${CLAUDE_PROJECT_DIR:-.}"
SYFT_BIN="${SYFT_BIN:-syft}"
GRYPE_BIN="${GRYPE_BIN:-grype}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_DENYLIST="$SCRIPT_DIR/../../skills/supply-chain-guide/references/license-denylist.json"
PROJECT_DENYLIST="$PROJ/.planning/gov/license-denylist.json"
fail=0

if ! command -v jq >/dev/null 2>&1; then
  echo "[gate-supply-chain] 실패: jq 미설치 — SBOM·denylist 대조 불가 (jq 설치 후 재실행)" >&2
  exit 1
fi

# ① 도구 존재 (fail-closed) — 하나라도 없으면 즉시 실패
missing=""
command -v "$SYFT_BIN"  >/dev/null 2>&1 || missing="$missing syft($SYFT_BIN)"
command -v "$GRYPE_BIN" >/dev/null 2>&1 || missing="$missing grype($GRYPE_BIN)"
if [ -n "$missing" ]; then
  echo "[gate-supply-chain] 실패: 미설치 도구 —$missing. 설치: brew install syft grype (또는 SYFT_BIN/GRYPE_BIN 오버라이드). 설치 불가 시 /gov-init 재실행으로 enabled:false 등록." >&2
  exit 1
fi

# denylist 선택 — 프로젝트 오버라이드 우선
DENYLIST="$DEFAULT_DENYLIST"
[ -f "$PROJECT_DENYLIST" ] && DENYLIST="$PROJECT_DENYLIST"

SBOM="$(mktemp "${TMPDIR:-/tmp}/eng-gov-sbom.XXXXXX")"
cleanup() { rm -f "$SBOM"; }
trap cleanup EXIT

# ② syft → SBOM(json)
syft_exit=0
"$SYFT_BIN" scan "dir:$PROJ" -o syft-json > "$SBOM" 2>/dev/null || syft_exit=$?
if [ "$syft_exit" -ne 0 ] || ! jq -e . "$SBOM" >/dev/null 2>&1; then
  echo "[gate-supply-chain] 실패: syft SBOM 생성 실패 (exit=$syft_exit, 유효 JSON 아님)" >&2
  exit 1
fi

# ③ grype 취약점 (--fail-on high)
grype_exit=0
gout="$("$GRYPE_BIN" "sbom:$SBOM" --fail-on high 2>&1)" || grype_exit=$?
if [ "$grype_exit" -ne 0 ]; then
  echo "[gate-supply-chain] 실패: grype high 이상 취약점 발견 (--fail-on high, exit=$grype_exit)" >&2
  printf '%s\n' "$gout" | tail -10 >&2
  fail=1
fi

# ④ 라이선스 denylist 대조
if [ -f "$DENYLIST" ] && jq -e . "$DENYLIST" >/dev/null 2>&1; then
  hits="$(jq -r --slurpfile dl "$DENYLIST" '
    ($dl[0].denied // []) as $denied
    | [ .artifacts[]?.licenses[]?.value // empty ]
    | map(select(. as $l | $denied | index($l)))
    | unique | .[]' "$SBOM" 2>/dev/null || true)"
  if [ -n "$hits" ]; then
    echo "[gate-supply-chain] 실패: 금지 라이선스 탐지 — $(printf '%s' "$hits" | paste -sd, -)" >&2
    fail=1
  fi
else
  echo "[gate-supply-chain] 경고: denylist($DENYLIST) 없음/파싱 불가 — 라이선스 대조 생략" >&2
fi

if [ "$fail" -eq 0 ]; then
  echo "[gate-supply-chain] 통과: SBOM 생성 + grype high 이상 0건 + 금지 라이선스 0건"
fi
exit "$fail"
