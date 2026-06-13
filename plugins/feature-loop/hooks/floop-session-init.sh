#!/usr/bin/env bash
# =============================================================================
# floop-session-init.sh — 진행 중 feature-loop 감지 (SessionStart 훅)
# .planning/floop-*.md 에 'status: in_progress' 가 있을 때만 재개 안내 1줄을 stdout 출력.
# mkdir 등 부수효과 절대 금지 — 플러그인이 설치된 모든 프로젝트에 .planning 을
# 만들면 안 된다 (.planning 생성은 /floop-new 담당). 항상 exit 0.
# =============================================================================
set -euo pipefail

PROJ="${CLAUDE_PROJECT_DIR:-.}"

# .planning 자체가 없으면 무동작
[ -d "$PROJ/.planning" ] || exit 0

for f in "$PROJ"/.planning/floop-*.md; do
  # 글롭 미매치 시 리터럴 경로가 들어오므로 파일 존재를 방어 검사
  [ -f "$f" ] || continue
  if grep -q 'status: in_progress' "$f" 2>/dev/null; then
    echo "[floop] 진행 중 feature-loop 감지 — /floop-run 으로 재개 가능"
    break
  fi
done
exit 0
