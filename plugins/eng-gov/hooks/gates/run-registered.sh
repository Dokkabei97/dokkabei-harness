#!/usr/bin/env bash
# =============================================================================
# run-registered.sh — 등록 게이트 일괄 실행 어댑터 (/gov-audit·루프 gate-cmd 직결)
# 정본: gates.json(= /gov-init 이 등록). 개별 게이트를 인자 없이 순회 실행하는 단일 진입점.
# 검사:
#   ① .planning/gov/gates.json 부재 → /gov-init 안내 exit 1
#   ② jq 로 enabled==true 게이트만 순회, 각 cmd 를 bash -c 로 실행(eval 금지)
#   ③ 실패(exit≠0) 게이트를 stderr 에 나열, 하나라도 실패 → exit 1
# 부수효과 없음(판정만) — audit-log.jsonl 기록은 /gov-audit 커맨드 몫.
# 인자 없이 동작(루프 gate-cmd 직결). 통과 exit 0 / 실패 exit 1.
# =============================================================================
set -euo pipefail

PROJ="${CLAUDE_PROJECT_DIR:-.}"
GATES="$PROJ/.planning/gov/gates.json"

if ! command -v jq >/dev/null 2>&1; then
  echo "[run-registered] 실패: jq 미설치 — gates.json 순회 불가 (jq 설치 후 재실행)" >&2
  exit 1
fi

if [ ! -f "$GATES" ]; then
  echo "[run-registered] 실패: $GATES 없음 — /gov-init 으로 게이트를 먼저 등록하세요." >&2
  exit 1
fi
if ! jq -e '.gates | type == "array"' "$GATES" >/dev/null 2>&1; then
  echo "[run-registered] 실패: gates.json 에 gates 배열이 없음(또는 JSON 파싱 불가)" >&2
  exit 1
fi

fail=0
count=0
export CLAUDE_PROJECT_DIR="$PROJ"

# enabled==true 게이트만 id\tcmd 로 추출 후 순회 (bash 3.2 — mapfile 금지, 프로세스 치환)
while IFS=$'\t' read -r gid gcmd; do
  [ -n "$gid" ] || continue
  count=$((count + 1))
  gexit=0
  ( cd "$PROJ" && bash -c "$gcmd" ) >/dev/null 2>&1 || gexit=$?
  if [ "$gexit" -ne 0 ]; then
    echo "[run-registered] 실패: $gid (exit=$gexit) — cmd: $gcmd" >&2
    fail=1
  fi
done < <(jq -r '.gates[] | select(.enabled == true) | [.id, .cmd] | @tsv' "$GATES")

if [ "$count" -eq 0 ]; then
  echo "[run-registered] 통과: 활성 게이트 0종 (gates.json 에 enabled:true 없음). /gov-init 로 게이트를 활성화하세요."
  exit 0
fi

if [ "$fail" -eq 0 ]; then
  echo "[run-registered] 통과: 활성 게이트 ${count}종 전부 그린(exit 0)"
fi
exit "$fail"
