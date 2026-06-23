#!/usr/bin/env bash
# =============================================================================
# gate-eval.sh — 제품 검증(평가) 소프트 게이트 (훅 미등록, /mvp-eval·오케스트레이터가 Bash 호출)
# 정본: mvp-eval-harness 스킬. "검증된 코드 ≠ 검증된 제품" 간극을 메우는 평가 결과 판정.
# 검사: ① .planning/eval/report.json 존재 ② 필수 필드(metric/value/threshold) ③ value >= threshold
#   - threshold 는 report.json 의 값을 정본으로 쓰되, MVP_EVAL_F1_MIN env 로 override 가능.
# 회귀 게이트(gate-cmd, 결정론)와 달리 이 게이트는 데이터·모델 의존 소프트 게이트다:
#   report 부재 = "제품 가치 미측정" 경고(exit 2), 임계값 미달 = 실패(exit 1), 충족 = 통과(exit 0).
# 평가 러너(실제 LLM 호출) 실행은 eval-engineer 의 몫 — 이 스크립트는 기록된 결과만 판정한다.
# =============================================================================
set -euo pipefail

PROJ="${CLAUDE_PROJECT_DIR:-.}"
REPORT="$PROJ/.planning/eval/report.json"

if ! command -v jq >/dev/null 2>&1; then
  echo "[gate-eval] 실패: jq 미설치 — report.json 검사 불가 (jq 설치 후 재실행)" >&2
  exit 1
fi

# ① report 존재 — 부재는 "미측정"으로 구분(exit 2). 가장 흔한 실패: 제품 가치를 한 번도 안 쟀음.
if [ ! -f "$REPORT" ]; then
  echo "[gate-eval] 미측정: $REPORT 없음 — 제품 품질 지표가 한 번도 측정되지 않았습니다." >&2
  echo "[gate-eval] eval-engineer 디스패치(/mvp-eval)로 골든셋 평가를 먼저 실행하세요." >&2
  exit 2
fi

# ② 필수 필드 + JSON 파싱
if ! jq -e 'has("metric") and has("value") and has("threshold")' "$REPORT" >/dev/null 2>&1; then
  echo "[gate-eval] 실패: report.json 에 metric/value/threshold 필드 누락(또는 JSON 파싱 불가)" >&2
  exit 1
fi

METRIC="$(jq -r '.metric' "$REPORT")"
VALUE="$(jq -r '.value' "$REPORT")"
N="$(jq -r '.n // "?"' "$REPORT")"
MODEL="$(jq -r '.model // "?"' "$REPORT")"
SYNTH="$(jq -r '.synthetic // false' "$REPORT")"

# ③ 임계값 — report 정본, MVP_EVAL_F1_MIN env 로 override 가능
THRESHOLD="$(jq -r '.threshold' "$REPORT")"
if [ -n "${MVP_EVAL_F1_MIN:-}" ]; then
  THRESHOLD="$MVP_EVAL_F1_MIN"
fi

# value >= threshold (부동소수 비교는 awk)
PASS="$(awk -v v="$VALUE" -v t="$THRESHOLD" 'BEGIN { print (v+0 >= t+0) ? "1" : "0" }')"

if [ "$SYNTH" = "true" ]; then
  echo "[gate-eval] 주의: 평가셋이 합성 데이터(synthetic=true) — 지표 해석에 한계 있음." >&2
fi

if [ "$PASS" = "1" ]; then
  echo "[gate-eval] 통과: $METRIC=$VALUE >= $THRESHOLD (n=$N, model=$MODEL)"
  exit 0
else
  echo "[gate-eval] 실패: $METRIC=$VALUE < 임계값 $THRESHOLD (n=$N, model=$MODEL)" >&2
  echo "[gate-eval] 임계값은 PRD 정본 — 하향 금지. per_class 로 저조 클래스 확인 후 프롬프트·스코프 조정." >&2
  exit 1
fi
