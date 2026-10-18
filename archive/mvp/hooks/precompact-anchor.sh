#!/usr/bin/env bash
# =============================================================================
# precompact-anchor.sh — 루프 재개 앵커 (PreCompact 훅, mvp/floop 공유 스크립트)
# compaction 직전에 루프 재개에 필요한 최소 맥락(앵커)을 5줄 이내로 stdout 출력한다.
# 양 플러그인(mvp/feature-loop)에 동일 내용으로 복제 등록 — $1 로 자기 플러그인
# 식별자(mvp|floop)를 받아 타 엔진 소유 루프에는 개입하지 않는다(중복 출력 방지).
#   - 항상 exit 0 — PreCompact 의 exit 2 는 compaction 자체를 차단하므로 절대 금지.
#   - loop-active 부재 → 즉시 exit 0 (일반 세션은 workflow 플러그인 소관 — 개입 금지)
#   - engine 판별: loop-active 의 "engine=" 줄 우선, 없으면 레거시 호환으로
#     prd.json(→mvp) vs tasks.json(→floop) 존재로 자기 판별. generic 등 타 엔진 → exit 0
#   - jq 부재 시 graceful degrade — 마스터 경로 1줄만 출력
# 주의: 현행 훅 레퍼런스상 PreCompact stdout 은 컨텍스트 주입이 아닌 디버그 로그
# 대상이다 — 앵커는 버전에 따라 무해한 로그로만 남을 수 있다(방어적 설계).
# =============================================================================
set -euo pipefail

PROJ="${CLAUDE_PROJECT_DIR:-.}"
PLAN="$PROJ/.planning"
SELF="${1:-}"

# stdin(JSON) 방어적 소비 — 판정은 전부 파일 기반, 어떤 페이로드가 와도 무시
_stdin="$(cat 2>/dev/null || true)"; : "$_stdin"

# (a) 안전핀 — 루프 미가동 세션에는 절대 개입하지 않는다
[ -f "$PLAN/loop-active" ] || exit 0

# (b) engine 판별 — "engine=" 줄 우선, 없으면 산출물(prd.json vs tasks.json)로 자기 판별
engine=""
eline="$(grep -m1 '^engine=' "$PLAN/loop-active" 2>/dev/null || true)"
[ -n "$eline" ] && engine="$(printf '%s' "${eline#engine=}" | tr -d '\r')"
if [ -z "$engine" ]; then
  if [ -f "$PLAN/prd.json" ]; then engine="mvp"
  elif [ -f "$PLAN/tasks.json" ]; then engine="floop"
  else exit 0  # 판별 불가 — 앵커 없이 통과
  fi
fi
case "$engine" in (mvp|floop) ;; (*) exit 0;; esac   # generic 등 타 엔진 소유 루프
[ -z "$SELF" ] || [ "$engine" = "$SELF" ] || exit 0  # 타 플러그인 몫 — 중복 출력 방지

# (c) 엔진별 마스터 파일·항목 JSON 확정 — 글롭 미매치 시 항목 JSON 경로로 폴백
master=""
if [ "$engine" = "mvp" ]; then
  items_json="$PLAN/prd.json"; items_key=".stories"
  for f in "$PLAN"/mvp-*.md; do [ -f "$f" ] && { master="$f"; break; }; done
else
  items_json="$PLAN/tasks.json"; items_key=".tasks"
  for f in "$PLAN"/floop-*.md; do [ -f "$f" ] && { master="$f"; break; }; done
fi
[ -n "$master" ] || master="$items_json"

# (d) jq 부재 graceful degrade — 마스터 경로 1줄만
if ! command -v jq >/dev/null 2>&1; then
  echo "[${engine}-loop 재개 앵커] 마스터: $master (jq 미설치 — 상세 생략)"
  exit 0
fi

# (e) 앵커 구성 — 다음 대상(passes:false 첫 항목)·게이트·반복·핵심 규율
next_id="$(jq -r "[${items_key}[]? | select(.passes != true) | .id] | first // \"없음\"" "$items_json" 2>/dev/null || echo "판독 불가")"
gate="(미설정 — gate-cmd 확인)"
[ -s "$PLAN/gate-cmd" ] && gate="$(head -n 1 "$PLAN/gate-cmd" | tr -d '\r')"
iter="?"; max_iter="?"
if [ -f "$PLAN/loop-state.json" ]; then
  iter="$(jq -r '.iteration // 0' "$PLAN/loop-state.json" 2>/dev/null || echo "?")"
  max_iter="$(jq -r '.max_iter // 24' "$PLAN/loop-state.json" 2>/dev/null || echo "?")"
fi

# 5줄 상한 하드코딩 — 구성이 늘어나도 head -n 5 가 최종 방어선
{
  echo "[${engine}-loop 재개 앵커] 마스터: $master"
  echo "- 다음 대상: $next_id (passes:false 최우선 1개)"
  echo "- 게이트: $gate"
  echo "- 반복: $iter/$max_iter"
  echo "- 규율: 테스트 삭제·약화 금지, passes 직접 마킹 금지(verified 마커 선행), 완료 판정은 Stop훅"
} | head -n 5
exit 0
