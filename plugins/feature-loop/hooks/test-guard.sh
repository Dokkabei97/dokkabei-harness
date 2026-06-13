#!/usr/bin/env bash
# =============================================================================
# test-guard.sh — 루프 활성 중 테스트 파일 삭제 차단 (PreToolUse: Bash 훅)
# .planning/loop-active 존재 시에만 작동. rm 대상에 test|spec 패턴이 있으면
# exit 2 로 차단한다 (테스트 삭제 금지 규칙의 결정론 집행).
# 브라운필드에서는 특히 중요 — 회귀 게이트의 신뢰는 기존 테스트가 보존될 때만 성립한다.
# =============================================================================
set -euo pipefail

PROJ="${CLAUDE_PROJECT_DIR:-.}"

# stdin(JSON) 소비 — 파이프 막힘 방지를 위해 먼저 읽는다
input="$(cat || true)"

# 루프 비활성 시 무동작
[ -f "$PROJ/.planning/loop-active" ] || exit 0

# jq 부재 시 검사 불가 — 차단하지 않고 사유 명시 후 통과
if ! command -v jq >/dev/null 2>&1; then
  echo "[floop] jq 미설치 — test-guard 검사 생략(차단 없음)" >&2
  exit 0
fi

cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // ""' 2>/dev/null || echo "")"
[ -n "$cmd" ] || exit 0

# rm 대상에 test|spec 토큰이 비알파벳 경계 뒤에 등장하면 차단 (2차 정밀 필터 —
# hooks.json matcher 가 1차 과포착 필터). 'latest.log' 류 오탐 제거,
# 'tests/' 디렉토리와 'foo.spec.ts'(.spec.)는 반드시 차단 유지.
if printf '%s' "$cmd" | grep -Eq 'rm[[:space:]](.*[[:space:]/_.-])?(tests?|specs?)([[:space:]/_.-]|$)'; then
  echo "테스트 삭제 금지 — 실패 테스트는 구현을 고쳐 통과시켜라. 불가피하면 BLOCKED.md에 사유 기록 후 /floop-stop 으로 중단하라." >&2
  exit 2
fi
exit 0
