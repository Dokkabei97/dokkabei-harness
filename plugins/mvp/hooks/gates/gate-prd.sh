#!/usr/bin/env bash
# =============================================================================
# gate-prd.sh — Stage 1 결정론 게이트 (훅 미등록, 오케스트레이터/커맨드가 Bash 호출)
# 검사: ① prd.md 필수 헤딩 grep(정본: prd-authoring 스킬 §2 표준 헤딩)
# ② prd.json jq 스키마(stories 배열, 각 항목 id/title/acceptance/passes,
#    id 형식 ^S-[0-9]{2}$·중복 금지, title 비어있지 않음,
#    acceptance 는 비어있지 않은 문자열 1개 이상의 배열)
# ③ 스토리 수 3~MVP_STORIES_MAX(기본 10, 하한 3 고정).
# 첫 번째 인자 --initial 전달 시 passes 전건 false 추가 검사
# (초기 PRD 전용 — 스코프 재협상 후 재검증은 인자 없이 호출).
# 실패 항목은 stderr 에 전부 나열. 통과 exit 0 / 실패 exit 1.
# =============================================================================
set -euo pipefail

PROJ="${CLAUDE_PROJECT_DIR:-.}"
PRD_MD="$PROJ/.planning/prd.md"
PRD_JSON="$PROJ/.planning/prd.json"
fail=0

# --initial: 초기 PRD 전용 추가 검사(passes 전건 false) 활성화
INITIAL=false
if [ "${1:-}" = "--initial" ]; then INITIAL=true; fi

# 스토리 수 상한 — MVP_STORIES_MAX env 로 치환 가능(기본 10), 하한 3 고정
STORIES_MAX="${MVP_STORIES_MAX:-10}"
case "$STORIES_MAX" in (''|*[!0-9]*) STORIES_MAX=10;; esac
if [ "$STORIES_MAX" -lt 3 ]; then STORIES_MAX=3; fi

# ① prd.md 존재 + 필수 헤딩 (prd-authoring 스킬 §2와 동일 문자열, 행두 앵커)
if [ ! -f "$PRD_MD" ]; then
  echo "[gate-prd] 실패: $PRD_MD 없음" >&2; fail=1
else
  for sec in "## 문제 정의" "## 페르소나" "## 범위" "### In" "### Out" "## 유저 스토리" "## 성공 지표"; do
    if ! grep -q "^$sec" "$PRD_MD"; then
      echo "[gate-prd] 실패: prd.md 필수 헤딩 누락 — '$sec'" >&2; fail=1
    fi
  done
fi

# ② prd.json jq 스키마 + ③ 스토리 수
if ! command -v jq >/dev/null 2>&1; then
  echo "[gate-prd] 실패: jq 미설치 — prd.json 스키마 검사 불가 (jq 설치 후 재실행)" >&2; fail=1
elif [ ! -f "$PRD_JSON" ]; then
  echo "[gate-prd] 실패: $PRD_JSON 없음" >&2; fail=1
else
  if ! jq -e '.stories | type == "array"' "$PRD_JSON" >/dev/null 2>&1; then
    echo "[gate-prd] 실패: prd.json 에 stories 배열 없음(또는 JSON 파싱 불가)" >&2; fail=1
  else
    if ! jq -e '[.stories[] | has("id") and has("title") and has("acceptance") and has("passes")] | all' "$PRD_JSON" >/dev/null 2>&1; then
      echo "[gate-prd] 실패: id/title/acceptance/passes 필드가 누락된 스토리 항목 존재" >&2; fail=1
    fi
    if ! jq -e '[.stories[].id | test("^S-[0-9]{2}$")] | all' "$PRD_JSON" >/dev/null 2>&1; then
      echo "[gate-prd] 실패: id 형식 위반 — ^S-[0-9]{2}$ (예: S-01) 필수" >&2; fail=1
    fi
    if ! jq -e '(.stories | map(.id) | length) == (.stories | map(.id) | unique | length)' "$PRD_JSON" >/dev/null 2>&1; then
      echo "[gate-prd] 실패: 중복된 스토리 id 존재" >&2; fail=1
    fi
    if ! jq -e '[.stories[] | (.title? // "") | (type == "string") and (length > 0)] | all' "$PRD_JSON" >/dev/null 2>&1; then
      echo "[gate-prd] 실패: title 이 비어있지 않은 문자열이 아닌 스토리 존재" >&2; fail=1
    fi
    if ! jq -e '[.stories[] | (.acceptance? // []) | (type == "array") and (length > 0) and (all(.[]?; (type == "string") and (length > 0)))] | all' "$PRD_JSON" >/dev/null 2>&1; then
      echo "[gate-prd] 실패: acceptance 가 비어있지 않은 문자열 1개 이상의 배열이 아닌 스토리 존재" >&2; fail=1
    fi
    if [ "$INITIAL" = true ]; then
      if ! jq -e '[.stories[].passes == false] | all' "$PRD_JSON" >/dev/null 2>&1; then
        echo "[gate-prd] 실패: --initial — passes 가 false 가 아닌 스토리 존재 (초기 PRD 는 전건 false 필수)" >&2; fail=1
      fi
    fi
    n="$(jq '.stories | length' "$PRD_JSON" 2>/dev/null || echo 0)"
    case "$n" in (''|*[!0-9]*) n=0;; esac
    if [ "$n" -lt 3 ] || [ "$n" -gt "$STORIES_MAX" ]; then
      echo "[gate-prd] 실패: 스토리 수 $n — 허용 범위 3~$STORIES_MAX 위반" >&2; fail=1
    fi
  fi
fi

if [ "$fail" -eq 0 ]; then
  if [ "$INITIAL" = true ]; then
    echo "[gate-prd] 통과: prd.md 필수 섹션 + prd.json 스키마 + 스토리 수(3~$STORIES_MAX) 검증 완료 (--initial: passes 전건 false 확인)"
  else
    echo "[gate-prd] 통과: prd.md 필수 섹션 + prd.json 스키마 + 스토리 수(3~$STORIES_MAX) 검증 완료"
  fi
fi
exit "$fail"
