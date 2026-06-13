#!/usr/bin/env bash
# =============================================================================
# gate-tasks.sh — Stage B 결정론 게이트 (훅 미등록, 오케스트레이터/커맨드가 Bash 호출)
# 검사: tasks.json jq 스키마(tasks 배열, 각 항목 id/title/acceptance/passes,
#   id 형식 ^T-[0-9]{2}$·중복 금지, title 비어있지 않음,
#   acceptance 는 비어있지 않은 문자열 1개 이상의 배열) + task 수 2~FLOOP_TASKS_MAX(기본 10).
# 첫 번째 인자 --initial 전달 시 passes 전건 false 추가 검사
# (초기 분해 전용 — 루프 중 재분해는 인자 없이 호출).
# 브라운필드는 prd.md/디자인 스펙 없음 — tasks.json 단일 산출만 검증한다.
# 실패 항목은 stderr 에 전부 나열. 통과 exit 0 / 실패 exit 1.
# (mvp 플러그인 gate-prd.sh 의 브라운필드판)
# =============================================================================
set -euo pipefail

PROJ="${CLAUDE_PROJECT_DIR:-.}"
TASKS_JSON="$PROJ/.planning/tasks.json"
fail=0

# --initial: 초기 분해 전용 추가 검사(passes 전건 false) 활성화
INITIAL=false
if [ "${1:-}" = "--initial" ]; then INITIAL=true; fi

# task 수 상한 — FLOOP_TASKS_MAX env 로 치환 가능(기본 10), 하한 2 고정
TASKS_MAX="${FLOOP_TASKS_MAX:-10}"
case "$TASKS_MAX" in (''|*[!0-9]*) TASKS_MAX=10;; esac
if [ "$TASKS_MAX" -lt 2 ]; then TASKS_MAX=2; fi

if ! command -v jq >/dev/null 2>&1; then
  echo "[gate-tasks] 실패: jq 미설치 — tasks.json 스키마 검사 불가 (jq 설치 후 재실행)" >&2; fail=1
elif [ ! -f "$TASKS_JSON" ]; then
  echo "[gate-tasks] 실패: $TASKS_JSON 없음" >&2; fail=1
else
  if ! jq -e '.tasks | type == "array"' "$TASKS_JSON" >/dev/null 2>&1; then
    echo "[gate-tasks] 실패: tasks.json 에 tasks 배열 없음(또는 JSON 파싱 불가)" >&2; fail=1
  else
    if ! jq -e '[.tasks[] | has("id") and has("title") and has("acceptance") and has("passes")] | all' "$TASKS_JSON" >/dev/null 2>&1; then
      echo "[gate-tasks] 실패: id/title/acceptance/passes 필드가 누락된 task 항목 존재" >&2; fail=1
    fi
    if ! jq -e '[.tasks[].id | test("^T-[0-9]{2}$")] | all' "$TASKS_JSON" >/dev/null 2>&1; then
      echo "[gate-tasks] 실패: id 형식 위반 — ^T-[0-9]{2}$ (예: T-01) 필수" >&2; fail=1
    fi
    if ! jq -e '(.tasks | map(.id) | length) == (.tasks | map(.id) | unique | length)' "$TASKS_JSON" >/dev/null 2>&1; then
      echo "[gate-tasks] 실패: 중복된 task id 존재" >&2; fail=1
    fi
    if ! jq -e '[.tasks[] | (.title? // "") | (type == "string") and (length > 0)] | all' "$TASKS_JSON" >/dev/null 2>&1; then
      echo "[gate-tasks] 실패: title 이 비어있지 않은 문자열이 아닌 task 존재" >&2; fail=1
    fi
    if ! jq -e '[.tasks[] | (.acceptance? // []) | (type == "array") and (length > 0) and (all(.[]?; (type == "string") and (length > 0)))] | all' "$TASKS_JSON" >/dev/null 2>&1; then
      echo "[gate-tasks] 실패: acceptance 가 비어있지 않은 문자열 1개 이상의 배열이 아닌 task 존재" >&2; fail=1
    fi
    if [ "$INITIAL" = true ]; then
      if ! jq -e '[.tasks[].passes == false] | all' "$TASKS_JSON" >/dev/null 2>&1; then
        echo "[gate-tasks] 실패: --initial — passes 가 false 가 아닌 task 존재 (초기 분해는 전건 false 필수)" >&2; fail=1
      fi
    fi
    n="$(jq '.tasks | length' "$TASKS_JSON" 2>/dev/null || echo 0)"
    case "$n" in (''|*[!0-9]*) n=0;; esac
    if [ "$n" -lt 2 ] || [ "$n" -gt "$TASKS_MAX" ]; then
      echo "[gate-tasks] 실패: task 수 $n — 허용 범위 2~$TASKS_MAX 위반" >&2; fail=1
    fi
  fi
fi

if [ "$fail" -eq 0 ]; then
  if [ "$INITIAL" = true ]; then
    echo "[gate-tasks] 통과: tasks.json 스키마 + task 수(2~$TASKS_MAX) 검증 완료 (--initial: passes 전건 false 확인)"
  else
    echo "[gate-tasks] 통과: tasks.json 스키마 + task 수(2~$TASKS_MAX) 검증 완료"
  fi
fi
exit "$fail"
