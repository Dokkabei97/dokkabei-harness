#!/usr/bin/env bash
# =============================================================================
# gate-pipeline-hygiene.sh — 파이프라인 위생 감사 결정론 게이트 (대표 쇼케이스, 훅 미등록)
# 대상: .planning/scaleup/gtm/pipeline/*-audit.json 중 파일명 사전식 최신
# 검사(정본: skills/revops-pipeline-schema/references/pipeline-enums.json + hygiene-rules.md):
#   ① stage ∈ enum, forecast_category ∈ enum (enum 파일이 단일 진실 원천 — 하드코딩 금지)
#   ② amount_krw > 0 전건
#   ③ open 딜(forecast_category ∉ {closed_won,closed_lost}) close_date ≥ TODAY
#   ④ open 딜 last_activity 경과 > stale_max_days → 실패(딜 id 나열)
# 날짜: TODAY="${GATE_TODAY:-$(date +%F)}", BSD/GNU date 이중 관용구. jq 부재=사유 exit 1.
# 통과 0 / 실패 1.
# =============================================================================
set -euo pipefail

PROJ="${CLAUDE_PROJECT_DIR:-.}"
PIPE_DIR="$PROJ/.planning/scaleup/gtm/pipeline"
# 게이트 위치 기준 상대참조(${0%/*}=dirname, 외부 명령 불요 — jq 부재 테스트 PATH 격리 안전)
GATE_DIR="${0%/*}"
ENUM_FILE="$GATE_DIR/../../skills/revops-pipeline-schema/references/pipeline-enums.json"
TODAY="${GATE_TODAY:-$(date +%F)}"
fail=0

to_epoch() {
  date -j -f "%Y-%m-%d" "$1" "+%s" 2>/dev/null || date -d "$1" "+%s" 2>/dev/null
}

# 최신 audit
latest=""
for f in "$PIPE_DIR"/*-audit.json; do
  [ -e "$f" ] || continue
  if [ -z "$latest" ] || [[ "$f" > "$latest" ]]; then latest="$f"; fi
done
if [ -z "$latest" ]; then
  echo "[gate-pipeline-hygiene] 실패: $PIPE_DIR/*-audit.json 없음 (/pipeline-audit 로 감사 산출 필요)" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "[gate-pipeline-hygiene] 실패: jq 미설치 — 파이프라인 스키마 검사 불가 (jq 설치 후 재실행)" >&2
  exit 1
fi
if [ ! -f "$ENUM_FILE" ]; then
  echo "[gate-pipeline-hygiene] 실패: enum 정본 파일 없음 — $ENUM_FILE (revops-pipeline-schema 스킬 references)" >&2
  exit 1
fi
if ! jq -e . "$latest" >/dev/null 2>&1; then
  echo "[gate-pipeline-hygiene] 실패: $(basename "$latest") JSON 파싱 불가" >&2
  exit 1
fi

stages="$(jq -c '.stage' "$ENUM_FILE" 2>/dev/null || echo 'null')"
fcats="$(jq -c '.forecast_category' "$ENUM_FILE" 2>/dev/null || echo 'null')"
if [ "$stages" = "null" ] || [ "$fcats" = "null" ]; then
  echo "[gate-pipeline-hygiene] 실패: enum 파일에 stage/forecast_category 배열 없음" >&2
  exit 1
fi

# ① stage enum
bad_stage="$(jq -r --argjson e "$stages" '.deals[] | select(.stage as $s | ($e | index($s)) == null) | .id' "$latest" 2>/dev/null || true)"
if [ -n "$bad_stage" ]; then
  echo "[gate-pipeline-hygiene] 실패: stage enum 위반 딜 — $(printf '%s' "$bad_stage" | tr '\n' ' ')" >&2; fail=1
fi
# ① forecast_category enum
bad_fc="$(jq -r --argjson e "$fcats" '.deals[] | select(.forecast_category as $c | ($e | index($c)) == null) | .id' "$latest" 2>/dev/null || true)"
if [ -n "$bad_fc" ]; then
  echo "[gate-pipeline-hygiene] 실패: forecast_category enum 위반 딜 — $(printf '%s' "$bad_fc" | tr '\n' ' ')" >&2; fail=1
fi
# ② amount_krw > 0 전건
bad_amt="$(jq -r '.deals[] | select((.amount_krw | type != "number") or (.amount_krw <= 0)) | .id' "$latest" 2>/dev/null || true)"
if [ -n "$bad_amt" ]; then
  echo "[gate-pipeline-hygiene] 실패: amount_krw ≤ 0 또는 비수치 딜 — $(printf '%s' "$bad_amt" | tr '\n' ' ')" >&2; fail=1
fi
# ③ open 딜 close_date ≥ TODAY
past_open="$(jq -r --arg today "$TODAY" '.deals[] | select((.forecast_category | . != "closed_won" and . != "closed_lost")) | select(.close_date < $today) | .id' "$latest" 2>/dev/null || true)"
if [ -n "$past_open" ]; then
  echo "[gate-pipeline-hygiene] 실패: open 딜 close_date < TODAY($TODAY) — $(printf '%s' "$past_open" | tr '\n' ' ') (마감일 도과 미갱신)" >&2; fail=1
fi

# ④ open 딜 last_activity 경과 > stale_max_days
stale_max="$(jq -r '.stale_max_days // 30' "$latest")"
case "$stale_max" in (''|*[!0-9]*) stale_max=30 ;; esac
today_epoch="$(to_epoch "$TODAY")" || today_epoch=""
if [ -z "$today_epoch" ]; then
  echo "[gate-pipeline-hygiene] 실패: TODAY($TODAY) epoch 변환 실패" >&2; fail=1
else
  stale_ids=""
  while IFS=$'\t' read -r id la; do
    [ -n "$id" ] || continue
    if ! printf '%s' "$la" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'; then
      stale_ids="$stale_ids $id(last_activity무효)"; continue
    fi
    la_epoch="$(to_epoch "$la")" || la_epoch=""
    [ -n "$la_epoch" ] || { stale_ids="$stale_ids $id(epoch변환실패)"; continue; }
    d=$(( (today_epoch - la_epoch) / 86400 ))
    if [ "$d" -gt "$stale_max" ]; then
      stale_ids="$stale_ids $id(${d}일)"
    fi
  done < <(jq -r '.deals[] | select((.forecast_category | . != "closed_won" and . != "closed_lost")) | "\(.id)\t\(.last_activity // "")"' "$latest" 2>/dev/null)
  if [ -n "$stale_ids" ]; then
    echo "[gate-pipeline-hygiene] 실패: stale_max_days($stale_max) 초과 open 딜 —$stale_ids" >&2; fail=1
  fi
fi

if [ "$fail" -eq 0 ]; then
  echo "[gate-pipeline-hygiene] 통과: stage/forecast enum·amount>0·open close_date≥TODAY·stale≤${stale_max}일 검증 완료 — $(basename "$latest")"
fi
exit "$fail"
