#!/usr/bin/env bash
# =============================================================================
# gate-threat-model.sh — 위협 모델 게이트 (준결정론 — 결정론 반쪽은 항상 판정)
# 정본: threat-model-checker 에이전트 + governance-templates. 유일한 degraded 허용 게이트:
#   threagile 재생성만 skip+경고, 결정론 판정(미완화 critical 수)은 항상 수행.
# 검사:
#   ① .planning/gov/threat/threagile.yaml 부재 → /gov-threat 안내 exit 1
#   ② command -v $THREAGILE_BIN (기본 threagile) 있으면 실행해 risks.json 갱신,
#      없으면 기존 risks.json 으로 판정 + "[경고] threagile 미설치 — risks.json stale 가능"
#   ③ risks.json 부재(재생성도 실패) → exit 1
#   ④ jq: severity==critical ∧ status ∉ {mitigated, accepted} 건수 == 0
# 인자 없이 동작(루프 gate-cmd 직결). 통과 exit 0 / 실패 exit 1.
# =============================================================================
set -euo pipefail

PROJ="${CLAUDE_PROJECT_DIR:-.}"
THREAGILE_BIN="${THREAGILE_BIN:-threagile}"
THREAT_DIR="$PROJ/.planning/gov/threat"
MODEL="$THREAT_DIR/threagile.yaml"
RISKS="$THREAT_DIR/risks.json"

if ! command -v jq >/dev/null 2>&1; then
  echo "[gate-threat-model] 실패: jq 미설치 — risks.json 판정 불가 (jq 설치 후 재실행)" >&2
  exit 1
fi

# ① 모델 존재
if [ ! -f "$MODEL" ]; then
  echo "[gate-threat-model] 실패: $MODEL 없음 — /gov-threat 로 위협 모델 초안을 먼저 작성하세요." >&2
  exit 1
fi

# ② threagile 있으면 재생성, 없으면 degraded 경고 (유일한 degraded 허용)
if command -v "$THREAGILE_BIN" >/dev/null 2>&1; then
  tg_exit=0
  out="$( (cd "$PROJ" && "$THREAGILE_BIN" -model "$MODEL" -output "$THREAT_DIR") 2>&1 )" || tg_exit=$?
  if [ "$tg_exit" -ne 0 ]; then
    echo "[gate-threat-model] 경고: threagile 실행 실패(exit=$tg_exit) — 기존 risks.json 으로 판정 진행." >&2
    printf '%s\n' "$out" | tail -5 >&2
  fi
else
  echo "[gate-threat-model] 경고: '$THREAGILE_BIN' 미설치 — risks.json 이 stale 일 수 있음(결정론 판정은 계속 수행). 설치: brew install threagile 또는 THREAGILE_BIN 오버라이드." >&2
fi

# ③ risks.json 존재
if [ ! -f "$RISKS" ]; then
  echo "[gate-threat-model] 실패: $RISKS 없음 — threagile 실행 또는 위협 모델러가 risks.json 을 생성해야 함." >&2
  exit 1
fi
if ! jq -e . "$RISKS" >/dev/null 2>&1; then
  echo "[gate-threat-model] 실패: risks.json JSON 파싱 불가" >&2
  exit 1
fi

# ④ 미완화 critical 수 == 0 (status 또는 risk_status 필드 지원)
unmit="$(jq '[ .[]? | select((.severity // "") == "critical")
              | ((.status // .risk_status) // "") as $s
              | select((["mitigated","accepted"] | index($s)) | not) ] | length' "$RISKS" 2>/dev/null || echo -1)"
case "$unmit" in (''|*[!0-9-]*) unmit=-1;; esac

if [ "$unmit" -lt 0 ]; then
  echo "[gate-threat-model] 실패: risks.json 구조 판정 불가 (배열·severity·status 필드 확인)" >&2
  exit 1
fi
if [ "$unmit" -ne 0 ]; then
  echo "[gate-threat-model] 실패: 미완화 critical 위협 ${unmit}건 (status ∉ {mitigated, accepted}). 완화 또는 근거 있는 accepted 처리 필요." >&2
  exit 1
fi

echo "[gate-threat-model] 통과: 미완화 critical 위협 0건 (전부 mitigated/accepted)"
exit 0
