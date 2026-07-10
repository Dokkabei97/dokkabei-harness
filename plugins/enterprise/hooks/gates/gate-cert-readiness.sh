#!/usr/bin/env bash
# =============================================================================
# gate-cert-readiness.sh — GRC 결정론 게이트 (/cert-gap 커맨드가 Bash 호출)
# 대상: .planning/grc/cert-gap.json
# 정본 참조: k-grc-context references/isms-p-items.json (101=16+64+21, core 플래그) — 하드코딩 금지
# 검사:
#   ① cert-gap items id 집합 == REF id 집합(101개 무결성)
#   ② status ∈ {n/a,planned,implemented,evidenced}
#   ③ status==evidenced 인데 evidence_path 파일 부재 → 실패
#   ④ REF core==true 항목의 status 가 planned/n·a → 실패 (핵심 통제 미이행)
# 통과 exit 0 / 실패 exit 1.
# =============================================================================
set -euo pipefail

PROJ="${CLAUDE_PROJECT_DIR:-.}"
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
GAP="$PROJ/.planning/grc/cert-gap.json"
REF="$SELF_DIR/../../skills/k-grc-context/references/isms-p-items.json"
fail=0

if ! command -v jq >/dev/null 2>&1; then
  echo "[gate-cert-readiness] 실패: jq 미설치 — cert-gap.json 검사 불가 (jq 설치 후 재실행)" >&2
  exit 1
fi
if [ ! -f "$REF" ]; then
  echo "[gate-cert-readiness] 실패: 정본 참조 파일 없음 — $REF (k-grc-context 스킬 references)" >&2
  exit 1
fi
if [ ! -f "$GAP" ]; then
  echo "[gate-cert-readiness] 실패: $GAP 없음" >&2
  exit 1
fi
if ! jq -e '.items | type == "array"' "$GAP" >/dev/null 2>&1; then
  echo "[gate-cert-readiness] 실패: items 배열 없음(또는 JSON 파싱 불가)" >&2
  exit 1
fi

# ① id 집합 무결성 (== REF 101개)
ref_ids="$(jq -r '.items[].id' "$REF" | sort -u)"
gap_ids="$(jq -r '.items[]?.id // empty' "$GAP" | sort -u)"
if [ "$ref_ids" != "$gap_ids" ]; then
  missing="$(comm -23 <(printf '%s\n' "$ref_ids") <(printf '%s\n' "$gap_ids") | tr '\n' ' ')"
  extra="$(comm -13 <(printf '%s\n' "$ref_ids") <(printf '%s\n' "$gap_ids") | tr '\n' ' ')"
  echo "[gate-cert-readiness] 실패: cert-gap id 집합이 ISMS-P 정본(101)과 불일치 — 누락:[$missing] 초과:[$extra]" >&2
  fail=1
fi

# ② status enum
bad_status="$(jq -r '.items[]? | select((.status|IN("n/a","planned","implemented","evidenced"))|not) | .id' "$GAP" 2>/dev/null || true)"
if [ -n "$bad_status" ]; then
  echo "[gate-cert-readiness] 실패: status enum 위반(n/a·planned·implemented·evidenced 아님) — $(echo "$bad_status" | tr '\n' ' ')" >&2
  fail=1
fi

# ③ evidenced && evidence 파일 부재
while IFS=$'\t' read -r iid ipath; do
  [ -z "$iid" ] && continue
  if [ -z "$ipath" ] || [ "$ipath" = "null" ]; then
    echo "[gate-cert-readiness] 실패: evidenced 항목에 evidence_path 없음 — $iid" >&2
    fail=1
    continue
  fi
  case "$ipath" in
    /*) abs="$ipath" ;;
    *)  abs="$PROJ/$ipath" ;;
  esac
  if [ ! -e "$abs" ]; then
    echo "[gate-cert-readiness] 실패: evidenced 항목의 evidence_path 파일 부재 — $iid ($ipath)" >&2
    fail=1
  fi
done < <(jq -r '.items[]? | select(.status=="evidenced") | "\(.id)\t\(.evidence_path // "")"' "$GAP" 2>/dev/null || true)

# ④ core 항목 미이행(planned/n·a)
core_gap="$(jq -r --slurpfile ref "$REF" '([$ref[0].items[] | select(.core==true) | .id]) as $core | .items[]? | select(.id as $id | ($core|index($id))) | select(.status=="planned" or .status=="n/a") | "\(.id):\(.status)"' "$GAP" 2>/dev/null || true)"
if [ -n "$core_gap" ]; then
  echo "[gate-cert-readiness] 실패: 핵심(core) 항목이 미이행(planned/n·a) — $(echo "$core_gap" | tr '\n' ' ')" >&2
  fail=1
fi

if [ "$fail" -eq 0 ]; then
  echo "[gate-cert-readiness] 통과: ISMS-P 101항목 무결성·status·evidenced 증적·core 이행 검증 완료"
fi
exit "$fail"
