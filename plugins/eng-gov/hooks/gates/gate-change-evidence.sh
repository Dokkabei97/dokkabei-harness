#!/usr/bin/env bash
# =============================================================================
# gate-change-evidence.sh — 변경 증적 게이트 (SOC2 CC8.1 / ISMS-P 2.9.1 결정론 반쪽)
# 정본: governance-templates 스킬 references/change-policy-template.md + control-map.md.
# 검사 (jq — 부재 시 exit 1):
#   ① git HEAD SHA 확보 → .planning/gov/change/<sha>/evidence.json 실재
#   ② evidence.sha == 현재 HEAD (다른 커밋 증적 재사용 차단)
#   ③ author 와 approver 상이 (자기 승인 금지 — 4-eyes)
#   ④ risk_tier ∈ {standard, normal, high}
#   ⑤ gates[] 전 항목 exit == 0 (기록된 게이트가 전부 그린)
#   ⑥ risk_tier == high → gates[] 에 gate-secrets·gate-supply-chain 기록 필수
# 인자 없이 동작(루프 gate-cmd 직결). 위반은 stderr 1줄씩. 통과 exit 0 / 실패 exit 1.
# =============================================================================
set -euo pipefail

PROJ="${CLAUDE_PROJECT_DIR:-.}"
fail=0

if ! command -v jq >/dev/null 2>&1; then
  echo "[gate-change-evidence] 실패: jq 미설치 — evidence.json 검사 불가 (jq 설치 후 재실행)" >&2
  exit 1
fi

# ① git HEAD
HEAD_SHA="$(git -C "$PROJ" rev-parse HEAD 2>/dev/null || true)"
if [ -z "$HEAD_SHA" ]; then
  echo "[gate-change-evidence] 실패: git HEAD 없음 (git 저장소·커밋 필요)" >&2
  exit 1
fi
EV="$PROJ/.planning/gov/change/$HEAD_SHA/evidence.json"
if [ ! -f "$EV" ]; then
  echo "[gate-change-evidence] 실패: $EV 없음 — 현재 HEAD($HEAD_SHA) 의 변경 증적 미생성. /gov-change 먼저." >&2
  exit 1
fi
if ! jq -e . "$EV" >/dev/null 2>&1; then
  echo "[gate-change-evidence] 실패: evidence.json JSON 파싱 불가" >&2
  exit 1
fi

# ② sha 일치
if ! jq -e --arg h "$HEAD_SHA" '.sha == $h' "$EV" >/dev/null 2>&1; then
  echo "[gate-change-evidence] 실패: evidence.sha 가 현재 HEAD($HEAD_SHA)와 불일치 (다른 커밋 증적 재사용 금지)" >&2
  fail=1
fi

# ③ author ≠ approver (both non-empty)
if ! jq -e '(.author // "") as $a | (.approver // "") as $p | ($a|length>0) and ($p|length>0) and ($a != $p)' "$EV" >/dev/null 2>&1; then
  echo "[gate-change-evidence] 실패: author 와 approver 가 상이한 비공백 값이어야 함 (자기 승인 금지 — 4-eyes)" >&2
  fail=1
fi

# ④ risk_tier enum
if ! jq -e '.risk_tier as $t | ["standard","normal","high"] | index($t)' "$EV" >/dev/null 2>&1; then
  echo "[gate-change-evidence] 실패: risk_tier 가 {standard|normal|high} 중 하나가 아님" >&2
  fail=1
fi

# ⑤ gates[] 전 항목 exit == 0
if ! jq -e '(.gates // []) | (length > 0) and (all(.[]; .exit == 0))' "$EV" >/dev/null 2>&1; then
  echo "[gate-change-evidence] 실패: gates[] 가 비었거나 exit != 0 인 게이트 기록 존재 (기록된 게이트 전부 그린이어야 함)" >&2
  fail=1
fi

# ⑥ high → gate-secrets·gate-supply-chain 기록 필수
if jq -e '.risk_tier == "high"' "$EV" >/dev/null 2>&1; then
  for req in gate-secrets gate-supply-chain; do
    if ! jq -e --arg g "$req" '[.gates[]?.gate] | index($g)' "$EV" >/dev/null 2>&1; then
      echo "[gate-change-evidence] 실패: risk_tier=high 는 gates[] 에 '$req' 실행 기록이 필수" >&2
      fail=1
    fi
  done
fi

if [ "$fail" -eq 0 ]; then
  echo "[gate-change-evidence] 통과: HEAD 매칭 + 4-eyes(author≠approver) + risk_tier enum + gates 전건 그린$(jq -e '.risk_tier=="high"' "$EV" >/dev/null 2>&1 && printf ' + high 필수 게이트 기록' || true)"
fi
exit "$fail"
