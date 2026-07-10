#!/usr/bin/env bash
# =============================================================================
# gate-cadence.sh — 주간 체크인 케이던스 결정론 게이트 (훅 미등록)
# 대상: .planning/scaleup/checkins/YYYY-Www.md 중 파일명 사전식 최신
# 검사(정본: skills/operating-cadence + gate-policy.md):
#   ① 최신 체크인 frontmatter 의 `date: YYYY-MM-DD` 추출(없으면 실패)
#   ② (TODAY − date) > 7일 → 실패 (주간 세션 생략 = 케이던스 붕괴 신호)
#   ③ "## 스코어카드" 헤딩 부재 → 실패
#   지표 5~15개 범위 밖 → 경고만(exit 무영향)
# 날짜: TODAY="${GATE_TODAY:-$(date +%F)}", BSD/GNU date 이중 관용구로 일수 계산.
# jq 불요(.md 대상). 통과 0 / 실패 1.
# =============================================================================
set -euo pipefail

PROJ="${CLAUDE_PROJECT_DIR:-.}"
CHK_DIR="$PROJ/.planning/scaleup/checkins"
TODAY="${GATE_TODAY:-$(date +%F)}"
fail=0

# YYYY-MM-DD → epoch (BSD/GNU 이중 관용구)
to_epoch() {
  date -j -f "%Y-%m-%d" "$1" "+%s" 2>/dev/null || date -d "$1" "+%s" 2>/dev/null
}

latest=""
for f in "$CHK_DIR"/*.md; do
  [ -e "$f" ] || continue
  if [ -z "$latest" ] || [[ "$f" > "$latest" ]]; then latest="$f"; fi
done
if [ -z "$latest" ]; then
  echo "[gate-cadence] 실패: $CHK_DIR/*.md 체크인 없음 (/okr-checkin 로 주간 체크인 생성 필요)" >&2
  exit 1
fi

# ① frontmatter date: 추출
date_line="$(grep -m1 '^date:' "$latest" || true)"
d="${date_line#date:}"
d="${d//[[:space:]]/}"
if ! printf '%s' "$d" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'; then
  echo "[gate-cadence] 실패: $(basename "$latest") frontmatter 에 유효한 date: YYYY-MM-DD 없음" >&2
  exit 1
fi

# ② 경과 일수 > 7 → 실패
today_epoch="$(to_epoch "$TODAY")" || today_epoch=""
date_epoch="$(to_epoch "$d")" || date_epoch=""
if [ -z "$today_epoch" ] || [ -z "$date_epoch" ]; then
  echo "[gate-cadence] 실패: 날짜 epoch 변환 실패 (TODAY=$TODAY, date=$d)" >&2; fail=1
else
  days=$(( (today_epoch - date_epoch) / 86400 ))
  if [ "$days" -gt 7 ]; then
    echo "[gate-cadence] 실패: 최신 체크인($d)이 ${days}일 경과 — 7일 초과 (주간 세션 생략 시 2사이클 내 붕괴, /okr-checkin 실행)" >&2; fail=1
  fi
fi

# ③ "## 스코어카드" 헤딩
if ! grep -q '^## 스코어카드' "$latest"; then
  echo "[gate-cadence] 실패: '## 스코어카드' 헤딩 부재 (주간 지표 스코어카드 갱신 필요)" >&2; fail=1
else
  # 지표 개수 5~15 범위 — 경고만(스코어카드 헤딩 이후 다음 '## ' 전까지의 표 데이터행/불릿 수)
  metrics="$(awk '
    /^## 스코어카드/ {ins=1; next}
    ins && /^## / {ins=0}
    ins && /^\| *[^|-]/ {c++}
    ins && /^- / {c++}
    END {print c+0}' "$latest")"
  if [ "$metrics" -lt 5 ] || [ "$metrics" -gt 15 ]; then
    echo "[gate-cadence] 경고: 스코어카드 지표 ${metrics}개 — 권장 5~15개 범위 밖 (EOS Scorecard/4DX 기준)" >&2
  fi
fi

if [ "$fail" -eq 0 ]; then
  echo "[gate-cadence] 통과: 최신 체크인 $(basename "$latest") (date=$d, TODAY=$TODAY, 7일 이내) + 스코어카드 헤딩 확인"
fi
exit "$fail"
