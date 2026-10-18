#!/usr/bin/env bash
# =============================================================================
# gate-board-deck.sh — 분기 보드덱 결정론 게이트 (훅 미등록)
# 대상: .planning/scaleup/board/*-deck.md 중 파일명 사전식 최신
# 검사(정본: skills/board-governance §덱 표준 헤딩 — 아래 REQUIRED 와 동일 문자열):
#   ① 필수 H2 헤딩 전부 행두 grep (gate-prd 관용구 — 스킬과 같은 문자열 하드코딩)
#   ② 전분기 덱 존재 시 '^## ' 헤딩 목록 diff ≠ 0 → 실패 (분기 간 구조 일관성)
#   ③ '## Asks' 섹션의 각 ask 는 '담당:' 과 '기한: YYYY-MM-DD' 짝 일치(≥1) → 불일치 실패
# jq 불요(.md 대상). 통과 0 / 실패 1.
# =============================================================================
set -euo pipefail

PROJ="${CLAUDE_PROJECT_DIR:-.}"
BOARD_DIR="$PROJ/.planning/scaleup/board"
fail=0

# 덱 표준 필수 헤딩 — board-governance 스킬 §덱 표준과 반드시 동일 문자열
REQUIRED=(
  "## 실적 요약"
  "## KPI 스코어카드"
  "## 하이라이트·로우라이트"
  "## 재무·런웨이"
  "## 전략·OKR 진척"
  "## Asks"
)

# 최신·전분기 덱 선택 (파일명 사전식)
latest=""; prev=""
for f in "$BOARD_DIR"/*-deck.md; do
  [ -e "$f" ] || continue
  if [ -z "$latest" ] || [[ "$f" > "$latest" ]]; then
    prev="$latest"; latest="$f"
  elif [ -z "$prev" ] || [[ "$f" > "$prev" ]]; then
    prev="$f"
  fi
done
if [ -z "$latest" ]; then
  echo "[gate-board-deck] 실패: $BOARD_DIR/*-deck.md 없음 (/board-deck 로 보드덱 생성 필요)" >&2
  exit 1
fi

# ① 필수 헤딩
for sec in "${REQUIRED[@]}"; do
  if ! grep -qF "$sec" "$latest"; then
    echo "[gate-board-deck] 실패: 필수 헤딩 누락 — '$sec' ($(basename "$latest"))" >&2; fail=1
  fi
done

# ② 전분기 덱과 H2 목록 diff
if [ -n "$prev" ]; then
  if ! diff <(grep '^## ' "$latest" | sort) <(grep '^## ' "$prev" | sort) >/dev/null 2>&1; then
    echo "[gate-board-deck] 실패: 전분기 덱($(basename "$prev"))과 H2 헤딩 목록 불일치 (분기 간 구조 일관성 위반)" >&2; fail=1
  fi
fi

# ③ Asks 섹션 담당/기한 짝
asks="$(awk '/^## Asks/{ins=1;next} ins&&/^## /{ins=0} ins{print}' "$latest")"
a_cnt="$(printf '%s\n' "$asks" | grep -c '담당:' || true)"
b_cnt="$(printf '%s\n' "$asks" | grep -Ec '기한: *[0-9]{4}-[0-9]{2}-[0-9]{2}' || true)"
if [ "$a_cnt" -lt 1 ]; then
  echo "[gate-board-deck] 실패: Asks 섹션에 '담당:' 항목이 없음 (Ask 는 담당·기한 명시 필수)" >&2; fail=1
elif [ "$a_cnt" -ne "$b_cnt" ]; then
  echo "[gate-board-deck] 실패: Asks 담당:(${a_cnt}) 과 기한:YYYY-MM-DD(${b_cnt}) 개수 불일치 (각 Ask 는 담당+기한 짝 필수)" >&2; fail=1
fi

if [ "$fail" -eq 0 ]; then
  echo "[gate-board-deck] 통과: 필수 헤딩 + 분기 구조 일관성 + Asks 담당/기한 짝 검증 완료 — $(basename "$latest")"
fi
exit "$fail"
