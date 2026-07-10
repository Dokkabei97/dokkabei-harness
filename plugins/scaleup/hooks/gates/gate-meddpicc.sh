#!/usr/bin/env bash
# =============================================================================
# gate-meddpicc.sh — 엔터프라이즈 딜 MEDDPICC 결정론 게이트 (훅 미등록)
# 대상: .planning/scaleup/gtm/deals/*/meddpicc.json (발견된 전 딜)
# 검사(정본: skills/meddpicc-qualification 8요소 계약):
#   ① elements 키 집합 == 8요소 정확히
#      (metrics,economic_buyer,decision_criteria,decision_process,
#       paper_process,identify_pain,champion,competition)
#   ② 각 element status ∈ {unknown,identified,verified}
#   ③ status ≠ unknown → evidence 비공백
#   ④ unknown 개수 > 3 → 실패
#   ⑤ close_date < TODAY → 실패 (마감일 도과한 미종결 딜)
#   --require-verdict : 딜 디렉토리 verdict.json 존재 + verdict ∈ {COMMIT,DOWNGRADE,
#                       DISQUALIFY} + coverage 비공백 배열
# 날짜: TODAY="${GATE_TODAY:-$(date +%F)}", 사전식 비교. jq 부재=사유 exit 1. 통과 0 / 실패 1.
# =============================================================================
set -euo pipefail

PROJ="${CLAUDE_PROJECT_DIR:-.}"
DEALS_DIR="$PROJ/.planning/scaleup/gtm/deals"
TODAY="${GATE_TODAY:-$(date +%F)}"
fail=0

REQUIRE_VERDICT=false
for arg in "$@"; do
  case "$arg" in
    --require-verdict) REQUIRE_VERDICT=true ;;
    *) echo "[gate-meddpicc] 경고: 알 수 없는 인자 무시 — '$arg'" >&2 ;;
  esac
done

if ! command -v jq >/dev/null 2>&1; then
  echo "[gate-meddpicc] 실패: jq 미설치 — MEDDPICC 스키마 검사 불가 (jq 설치 후 재실행)" >&2
  exit 1
fi

found=0
for m in "$DEALS_DIR"/*/meddpicc.json; do
  [ -e "$m" ] || continue
  found=1
  deal_dir="$(dirname "$m")"
  tag="$(basename "$deal_dir")"

  if ! jq -e . "$m" >/dev/null 2>&1; then
    echo "[gate-meddpicc] 실패: [$tag] meddpicc.json JSON 파싱 불가" >&2; fail=1; continue
  fi
  # ① elements 8키 정확히 (jq keys 는 정렬 반환)
  if ! jq -e '.elements | keys == ["champion","competition","decision_criteria","decision_process","economic_buyer","identify_pain","metrics","paper_process"]' "$m" >/dev/null 2>&1; then
    echo "[gate-meddpicc] 실패: [$tag] elements 키가 8요소(metrics,economic_buyer,decision_criteria,decision_process,paper_process,identify_pain,champion,competition)와 정확히 일치하지 않음" >&2; fail=1
  fi
  # ② status enum
  if ! jq -e '[.elements[] | (.status | . == "unknown" or . == "identified" or . == "verified")] | all' "$m" >/dev/null 2>&1; then
    echo "[gate-meddpicc] 실패: [$tag] status 가 unknown|identified|verified 중 하나가 아닌 element 존재" >&2; fail=1
  fi
  # ③ status ≠ unknown → evidence 비공백
  if ! jq -e '[.elements[] | select(.status != "unknown") | (.evidence | type == "string" and length > 0)] | all' "$m" >/dev/null 2>&1; then
    echo "[gate-meddpicc] 실패: [$tag] identified/verified 인데 evidence 가 비공백이 아닌 element 존재" >&2; fail=1
  fi
  # ④ unknown 개수 > 3
  if jq -e '([.elements[] | select(.status == "unknown")] | length) > 3' "$m" >/dev/null 2>&1; then
    unk="$(jq -r '[.elements[] | select(.status == "unknown")] | length' "$m")"
    echo "[gate-meddpicc] 실패: [$tag] unknown element ${unk}개 > 3 (딜 자격 미달 — deal-qualifier 반증 필요)" >&2; fail=1
  fi
  # ⑤ close_date < TODAY
  cd_date="$(jq -r '.close_date // ""' "$m")"
  if [ -z "$cd_date" ]; then
    echo "[gate-meddpicc] 실패: [$tag] close_date 없음" >&2; fail=1
  elif [[ "$cd_date" < "$TODAY" ]]; then
    echo "[gate-meddpicc] 실패: [$tag] close_date($cd_date) < TODAY($TODAY) — 마감일 도과한 미종결 딜" >&2; fail=1
  fi

  # --require-verdict
  if [ "$REQUIRE_VERDICT" = true ]; then
    v="$deal_dir/verdict.json"
    if [ ! -f "$v" ]; then
      echo "[gate-meddpicc] 실패: [$tag] --require-verdict — verdict.json 없음 (deal-qualifier 판정 미물화)" >&2; fail=1
    elif ! jq -e . "$v" >/dev/null 2>&1; then
      echo "[gate-meddpicc] 실패: [$tag] verdict.json JSON 파싱 불가" >&2; fail=1
    else
      if ! jq -e '.coverage | type == "array" and length > 0' "$v" >/dev/null 2>&1; then
        echo "[gate-meddpicc] 실패: [$tag] verdict.coverage 는 비공백 배열이어야 함" >&2; fail=1
      fi
      if ! jq -e '[.items[]?.verdict] | length > 0 and all(. as $x | ["COMMIT","DOWNGRADE","DISQUALIFY"] | index($x) != null)' "$v" >/dev/null 2>&1; then
        echo "[gate-meddpicc] 실패: [$tag] verdict 는 COMMIT|DOWNGRADE|DISQUALIFY 중 하나여야 함" >&2; fail=1
      fi
    fi
  fi
done

if [ "$found" -eq 0 ]; then
  echo "[gate-meddpicc] 실패: $DEALS_DIR/*/meddpicc.json 없음 (/deal-review 로 MEDDPICC 스코어카드 생성 필요)" >&2
  exit 1
fi

if [ "$fail" -eq 0 ]; then
  msg="[gate-meddpicc] 통과: 전 딜 elements 8요소·status enum·evidence·unknown≤3·close_date≥TODAY 검증 완료"
  [ "$REQUIRE_VERDICT" = true ] && msg="$msg (--require-verdict: deal-qualifier 판정 확인)"
  echo "$msg"
fi
exit "$fail"
