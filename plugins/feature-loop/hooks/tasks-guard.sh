#!/usr/bin/env bash
# =============================================================================
# tasks-guard.sh — maker/checker 분리 강제 (PostToolUse: Edit|Write on tasks.json 훅)
# tasks.json 에서 passes==true 인 task 마다 feature-verifier 승인 마커
# .planning/verified/{id} 존재를 검사한다. 마커 없는 마킹은 jq 로 false 원복
# (임시파일 → mv 원자적 재작성) 후 exit 2 로 차단한다.
# Evaluator 판정을 파일 마커로 물화해 결정론 검사로 변환하는 본 설계의 핵심 집행점.
# (mvp 플러그인 prd-guard.sh 의 브라운필드판 — prd.json/stories → tasks.json/tasks)
# =============================================================================
set -euo pipefail

PROJ="${CLAUDE_PROJECT_DIR:-.}"
PLAN="$PROJ/.planning"
TASKS="$PLAN/tasks.json"

# stdin(JSON) 소비 — 파이프 막힘 방지. 검사 대상은 항상 정본 경로의 tasks.json.
input="$(cat || true)"
: "${input}"

[ -f "$TASKS" ] || exit 0

# jq 부재 시 검사 불가 — 차단하지 않고 사유 명시 후 통과
if ! command -v jq >/dev/null 2>&1; then
  echo "[floop] jq 미설치 — tasks-guard 검사 생략(차단 없음)" >&2
  exit 0
fi

# 경로 필터 — 정본 tasks.json 편집일 때만 검사 (2차 정밀 필터: hooks.json matcher 는
# tool 명 regex 만 유효해 Edit|Write 전건에 발화하므로 여기서 좁힌다)
fp="$(printf '%s' "$input" | jq -r '.tool_input.file_path // ""' 2>/dev/null || echo "")"
case "$fp" in
  *.planning/tasks.json) ;;
  *) exit 0 ;;
esac

# passes==true 인 task 중 verified 마커 부재 id 수집 — while read 줄 단위 소비
nl=$'\n'
violations=""
while IFS= read -r id; do
  [ -n "$id" ] || continue
  if [ ! -f "$PLAN/verified/$id" ]; then
    violations="${violations:+$violations$nl}$id"
  fi
done < <(jq -r '.tasks[]? | select(.passes == true) | .id' "$TASKS" 2>/dev/null || true)
[ -n "$violations" ] || exit 0

# 위반 task passes 를 false 로 원복 — 임시파일 → mv (동일 디렉토리, 원자적 rename)
ids_json="$(printf '%s\n' "$violations" | jq -R . | jq -s . 2>/dev/null || echo '[]')"
tmp="$PLAN/.tasks-guard.tmp"
if jq --argjson ids "$ids_json" \
     '.tasks |= map(if (.id as $i | $ids | index($i)) then .passes = false else . end)' \
     "$TASKS" > "$tmp" 2>/dev/null; then
  mv "$tmp" "$TASKS"
  echo "[floop] verified 마커 없는 passes:true 를 false 로 원복했다." >&2
else
  echo "[floop] 경고: tasks.json 원복 실패(jq 오류) — 수동으로 passes 를 false 로 되돌려라." >&2
fi

while IFS= read -r id; do
  echo "task ${id}는 feature-verifier 승인 마커(.planning/verified/${id})가 없다. verifier 반증을 통과시킨 뒤 마킹하라." >&2
done <<< "$violations"
exit 2
