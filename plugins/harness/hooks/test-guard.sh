#!/usr/bin/env bash
# =============================================================================
# test-guard.sh — generic 루프 활성 중 테스트 파일 삭제 차단 (PreToolUse: Bash 훅)
# .planning/loop-active 가 engine=generic 일 때만 작동. rm 대상에 test|spec 패턴이
# 있으면 exit 2 로 차단한다 — "게이트를 테스트 삭제로 그린 만들기"의 결정론 차단.
# (archive/mvp·feature-loop 의 test-guard.sh 에서 회수, 2026-10-18)
# =============================================================================
set -euo pipefail

PROJ="${CLAUDE_PROJECT_DIR:-.}"

# stdin(JSON) 소비 — 파이프 막힘 방지를 위해 먼저 읽는다
input="$(cat || true)"

# 루프 비활성 시 무동작
[ -f "$PROJ/.planning/loop-active" ] || exit 0

# jq 부재(=최소 PATH, grep 도 없을 수 있음) 시 검사 불가 — 차단하지 않고 사유 명시 후 통과
if ! command -v jq >/dev/null 2>&1; then
  echo "[generic-loop] jq 미설치 — test-guard 검사 생략(차단 없음)" >&2
  exit 0
fi

# engine 스코프 가드 — engine=generic 명시된 경우에만 내 소유 (Stop 훅과 동일 패턴)
loop_engine="$(grep -m1 '^engine=' "$PROJ/.planning/loop-active" 2>/dev/null | tr -d '\r' || true)"
[ "${loop_engine#engine=}" = "generic" ] || exit 0

cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // ""' 2>/dev/null || echo "")"
[ -n "$cmd" ] || exit 0

# rm 대상에 test|spec 토큰이 비알파벳 경계 뒤에 등장하면 차단.
# 'latest.log' 류 오탐 제거, 'tests/' 디렉토리와 'foo.spec.ts'(.spec.)는 반드시 차단 유지.
if printf '%s' "$cmd" | grep -Eq 'rm[[:space:]](.*[[:space:]/_.-])?(tests?|specs?)([[:space:]/_.-]|$)'; then
  echo "테스트 삭제 금지 — 실패 테스트는 구현을 고쳐 통과시켜라. 불가피하면 .planning/BLOCKED.md 에 사유 기록 후 /loop-stop 으로 중단하라." >&2
  exit 2
fi
exit 0
