#!/usr/bin/env bash
# =============================================================================
# gate-okr.sh — 분기 OKR 트리 결정론 게이트 (훅 미등록, 커맨드/오케스트레이터가 Bash 호출)
# 대상: .planning/scaleup/okr/okr-*.json 중 파일명 사전식 최신
# 검사(정본: skills/scaleup-orchestrator/references/gate-policy.md):
#   ① objectives 1..5, 각 objective 의 krs 1..4
#   ② objective.owner 비공백, 각 KR statement/owner 비공백
#   ③ 각 KR baseline·target 은 number, due 는 YYYY-MM-DD 형식
#   ④ id 중복 0 (objective id + KR id 전역 유일)
#   --scored          : 전 KR score 가 0..1 number (분기말 스코어링 검증)
#   --require-verdict : okr/verdict.json 존재 + items 가 전 KR id 커버 +
#                       coverage 비공백 배열 + verdict ∈ {ADOPT,REWRITE,DROP} +
#                       non-ADOPT(REWRITE/DROP) 1건 이상 → 실패(항목 나열)
# 규약: jq 부재=사유 exit 1. 위반은 stderr "[gate-okr] 실패: …" 1줄씩 누적. 통과 0 / 실패 1.
# =============================================================================
set -euo pipefail

PROJ="${CLAUDE_PROJECT_DIR:-.}"
OKR_DIR="$PROJ/.planning/scaleup/okr"
fail=0

SCORED=false
REQUIRE_VERDICT=false
for arg in "$@"; do
  case "$arg" in
    --scored) SCORED=true ;;
    --require-verdict) REQUIRE_VERDICT=true ;;
    *) echo "[gate-okr] 경고: 알 수 없는 인자 무시 — '$arg'" >&2 ;;
  esac
done

# 최신 okr-*.json 선택 — 파일명 사전식 최대(YYYYQn 규약상 최신 분기)
latest=""
for f in "$OKR_DIR"/okr-*.json; do
  [ -e "$f" ] || continue
  if [ -z "$latest" ] || [[ "$f" > "$latest" ]]; then latest="$f"; fi
done
if [ -z "$latest" ]; then
  echo "[gate-okr] 실패: $OKR_DIR/okr-*.json 없음 (/okr-plan 로 분기 OKR 트리 생성 필요)" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "[gate-okr] 실패: jq 미설치 — OKR 스키마 검사 불가 (jq 설치 후 재실행)" >&2
  exit 1
fi
if ! jq -e . "$latest" >/dev/null 2>&1; then
  echo "[gate-okr] 실패: $latest JSON 파싱 불가" >&2
  exit 1
fi

# ① objectives 1..5
if ! jq -e '.objectives | type == "array" and length >= 1 and length <= 5' "$latest" >/dev/null 2>&1; then
  echo "[gate-okr] 실패: objectives 는 1~5개 배열이어야 함" >&2; fail=1
fi
# ① 각 objective 의 krs 1..4
if ! jq -e '[.objectives[]? | (.krs | type == "array" and length >= 1 and length <= 4)] | all' "$latest" >/dev/null 2>&1; then
  echo "[gate-okr] 실패: 각 objective 의 krs 는 1~4개 배열이어야 함" >&2; fail=1
fi
# ② objective.owner 비공백
if ! jq -e '[.objectives[]? | (.owner | type == "string" and length > 0)] | all' "$latest" >/dev/null 2>&1; then
  echo "[gate-okr] 실패: owner 가 비공백 문자열이 아닌 objective 존재" >&2; fail=1
fi
# ②③ 각 KR statement/owner 비공백 + baseline/target number + due 날짜형
if ! jq -e '[.objectives[]?.krs[]? |
      (.statement | type == "string" and length > 0)
      and (.owner | type == "string" and length > 0)
      and (.baseline | type == "number")
      and (.target | type == "number")
      and (.due | type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}$"))] | all' "$latest" >/dev/null 2>&1; then
  echo "[gate-okr] 실패: KR 의 statement/owner 비공백·baseline/target number·due(YYYY-MM-DD) 규격 위반" >&2; fail=1
fi
# ④ id 중복 0 (objective + KR 전역 유일)
if ! jq -e '([.objectives[]?.id] + [.objectives[]?.krs[]?.id]) as $ids | ($ids | length) == ($ids | unique | length)' "$latest" >/dev/null 2>&1; then
  echo "[gate-okr] 실패: 중복된 id 존재 (objective id·KR id 는 전역 유일해야 함)" >&2; fail=1
fi

# --scored: 전 KR score 0..1 number
if [ "$SCORED" = true ]; then
  if ! jq -e '[.objectives[]?.krs[]? | (.score | type == "number" and . >= 0 and . <= 1)] | all' "$latest" >/dev/null 2>&1; then
    echo "[gate-okr] 실패: --scored — score 가 0.0~1.0 number 가 아닌 KR 존재 (분기말 스코어링 미완)" >&2; fail=1
  fi
fi

# --require-verdict: okr/verdict.json 검사
if [ "$REQUIRE_VERDICT" = true ]; then
  VERDICT="$OKR_DIR/verdict.json"
  if [ ! -f "$VERDICT" ]; then
    echo "[gate-okr] 실패: --require-verdict — $VERDICT 없음 (okr-checker 판정 미물화)" >&2; fail=1
  elif ! jq -e . "$VERDICT" >/dev/null 2>&1; then
    echo "[gate-okr] 실패: --require-verdict — verdict.json JSON 파싱 불가" >&2; fail=1
  else
    if ! jq -e '.coverage | type == "array" and length > 0' "$VERDICT" >/dev/null 2>&1; then
      echo "[gate-okr] 실패: verdict.coverage 는 비공백 배열이어야 함 (검증한 반증 질문 기록)" >&2; fail=1
    fi
    if ! jq -e '[.items[]?.verdict] | all(. as $v | ["ADOPT","REWRITE","DROP"] | index($v) != null)' "$VERDICT" >/dev/null 2>&1; then
      echo "[gate-okr] 실패: verdict 는 ADOPT|REWRITE|DROP 중 하나여야 함" >&2; fail=1
    fi
    # items 가 전 KR id 커버
    if ! jq -e --slurpfile okr "$latest" '
        ([$okr[0].objectives[]?.krs[]?.id] - [.items[]?.id]) | length == 0' "$VERDICT" >/dev/null 2>&1; then
      missing="$(jq -r --slurpfile okr "$latest" '([$okr[0].objectives[]?.krs[]?.id] - [.items[]?.id]) | join(", ")' "$VERDICT" 2>/dev/null || true)"
      echo "[gate-okr] 실패: verdict.items 가 커버하지 못한 KR id — $missing" >&2; fail=1
    fi
    # non-ADOPT 1건 이상 → 실패 (REWRITE/DROP 항목 나열)
    non_adopt="$(jq -r '[.items[]? | select(.verdict != "ADOPT")] | map("\(.id):\(.verdict)") | join(", ")' "$VERDICT" 2>/dev/null || true)"
    if [ -n "$non_adopt" ]; then
      echo "[gate-okr] 실패: ADOPT 아닌 KR 존재 — $non_adopt (REWRITE/DROP 는 재작성 필요, okr-checker 반증 반영 후 재판정)" >&2; fail=1
    fi
  fi
fi

if [ "$fail" -eq 0 ]; then
  msg="[gate-okr] 통과: objectives(1~5)·krs(1~4)·필드·id 유일성 검증 완료 — $(basename "$latest")"
  [ "$SCORED" = true ] && msg="$msg (--scored: 전 KR score 0~1 확인)"
  [ "$REQUIRE_VERDICT" = true ] && msg="$msg (--require-verdict: 전 KR ADOPT 확인)"
  echo "$msg"
fi
exit "$fail"
