#!/usr/bin/env bash
# =============================================================================
# gate-design.sh — Stage 2 결정론 게이트 (훅 미등록, 오케스트레이터/커맨드가 Bash 호출)
# 검사: prd.json 의 모든 story id 가 design-spec.md 에 "[story: {id}]" 태그로
# 등장하는지 grep -F 확인. 누락 id 를 stderr 에 전부 나열. 통과 exit 0 / 실패 exit 1.
# =============================================================================
set -euo pipefail

PROJ="${CLAUDE_PROJECT_DIR:-.}"
PRD_JSON="$PROJ/.planning/prd.json"
SPEC="$PROJ/.planning/design-spec.md"

if ! command -v jq >/dev/null 2>&1; then
  echo "[gate-design] 실패: jq 미설치 — story id 추출 불가 (jq 설치 후 재실행)" >&2
  exit 1
fi
if [ ! -f "$PRD_JSON" ]; then
  echo "[gate-design] 실패: $PRD_JSON 없음" >&2
  exit 1
fi
if [ ! -f "$SPEC" ]; then
  echo "[gate-design] 실패: $SPEC 없음" >&2
  exit 1
fi

ids="$(jq -r '.stories[]?.id // empty' "$PRD_JSON" 2>/dev/null || true)"
if [ -z "$ids" ]; then
  echo "[gate-design] 실패: prd.json 에서 story id 를 추출하지 못함(stories 비어있음 또는 파싱 불가)" >&2
  exit 1
fi

missing=""
for id in $ids; do
  if ! grep -qF "[story: $id]" "$SPEC"; then
    missing="$missing $id"
  fi
done

if [ -n "$missing" ]; then
  echo "[gate-design] 실패: design-spec.md 에 매핑 태그 누락 —$missing" >&2
  echo "[gate-design] 각 화면 명세에 [story: S-xx] 태그를 추가하라 (ux-designer 의무 사항)." >&2
  exit 1
fi

echo "[gate-design] 통과: 전 스토리 id 가 design-spec.md 에 [story: S-xx] 태그로 매핑됨"
exit 0
