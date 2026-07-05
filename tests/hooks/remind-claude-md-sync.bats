#!/usr/bin/env bats
# =============================================================================
# remind-claude-md-sync.bats — workflow 플러그인 CLAUDE.md 갱신 검토 강제 훅 회귀 테스트
# 대상: plugins/workflow/hooks/remind-claude-md-sync.js
#       (PreToolUse Bash: git commit/push 를 세션당 1회 exit 2 차단 —
#        sync-claude-md 검토를 결정론 경로로 강제, 재시도는 마커로 통과)
# 규약: 차단은 exit 2(PreToolUse), 통과는 exit 0 + 원본 passthrough.
#       발동 regex: (^|[;&|]\s*)git\s+(commit|push)\b — 인자 위치 등장은 비발동.
#       게이트: CLAUDE_MD_SYNC_REMIND=0 킬스위치, CLAUDE.md 부재 프로젝트 비대상.
# 주의: @test 이름은 ASCII. 각 테스트는 고유 session_id(rcms- 접두) 사용,
#       teardown 에서 해당 마커만 정리(실세션 마커 무접촉).
# =============================================================================

bats_require_minimum_version 1.5.0

load 'helpers'

REMIND_HOOK="$REPO_ROOT/plugins/workflow/hooks/remind-claude-md-sync.js"

setup() {
  make_project
  printf '# CLAUDE.md\n' > "$TEST_PROJ/CLAUDE.md"
  unset CLAUDE_MD_SYNC_REMIND 2>/dev/null || true
  # 훅과 같은 방식(node os.tmpdir())으로 마커 디렉토리 계산 — teardown 정리에 사용
  NODE_TMPDIR="$(node -p 'require("os").tmpdir()')"
}

teardown() {
  rm -f "$NODE_TMPDIR"/claude-md-sync-remind-rcms-* 2>/dev/null || true
  rm -f "$NODE_TMPDIR/claude-md-sync-remind-nosession" 2>/dev/null || true
  cleanup_project
}

# 테스트별 고유 session_id — 이전 크래시 런의 잔류 마커와 충돌하지 않도록 난수 포함
new_sid() { printf 'rcms-%s-%s-%s' "$BATS_TEST_NUMBER" "$$" "$RANDOM"; }

# Bash PreToolUse 이벤트 JSON — $1 session_id, $2 command
bash_event() {
  printf '{"session_id":"%s","tool_name":"Bash","tool_input":{"command":"%s"},"cwd":"%s"}' \
    "$1" "$2" "$TEST_PROJ"
}

invoke_remind() {
  local stdin_json="$1"
  printf '%s' "$stdin_json" | CLAUDE_PROJECT_DIR="$TEST_PROJ" node "$REMIND_HOOK"
}

# CLAUDE_PROJECT_DIR 미설정 실행 — stdin cwd 폴백 계약 검증용
invoke_remind_nodir() {
  local stdin_json="$1"
  printf '%s' "$stdin_json" | env -u CLAUDE_PROJECT_DIR node "$REMIND_HOOK"
}

# ── 차단 (첫 발동) ───────────────────────────────────────────────────────────

@test "remind-sync: first git commit -> blocked (exit 2) with BLOCKED message" {
  local sid; sid="$(new_sid)"
  run invoke_remind "$(bash_event "$sid" "git commit -m x")"
  [ "$status" -eq 2 ]
  [[ "$output" == *"BLOCKED"* ]]
  [[ "$output" == *"sync-claude-md"* ]]
  [[ "$output" == *"CLAUDE_MD_SYNC_REMIND=0"* ]]
}

@test "remind-sync: first git push -> blocked (exit 2)" {
  local sid; sid="$(new_sid)"
  run invoke_remind "$(bash_event "$sid" "git push origin main")"
  [ "$status" -eq 2 ]
  [[ "$output" == *"BLOCKED"* ]]
}

# 구분자 뒤 등장도 발동 — "cd x && git commit" 류 체이닝
@test "remind-sync: chained '&& git commit' -> blocked (exit 2)" {
  local sid; sid="$(new_sid)"
  run invoke_remind "$(bash_event "$sid" "cd sub && git commit -m x")"
  [ "$status" -eq 2 ]
}

# ── 세션당 1회 (마커 재시도 통과) ─────────────────────────────────────────────

@test "remind-sync: same session retry -> allowed (exit 0)" {
  local sid; sid="$(new_sid)"
  run invoke_remind "$(bash_event "$sid" "git commit -m x")"
  [ "$status" -eq 2 ]
  local ev; ev="$(bash_event "$sid" "git commit -m x")"
  run invoke_remind "$ev"
  [ "$status" -eq 0 ]
  [ "$output" = "$ev" ]
}

# session_id 부재 → 'nosession' 마커로 동일한 1회 차단 동작
@test "remind-sync: missing session_id -> nosession marker, blocked then allowed" {
  rm -f "$NODE_TMPDIR/claude-md-sync-remind-nosession"
  local ev; ev="$(printf '{"tool_name":"Bash","tool_input":{"command":"git commit -m x"},"cwd":"%s"}' "$TEST_PROJ")"
  run invoke_remind "$ev"
  [ "$status" -eq 2 ]
  run invoke_remind "$ev"
  [ "$status" -eq 0 ]
}

# ── 비발동 (명령 패턴) ───────────────────────────────────────────────────────

@test "remind-sync: non-git command -> passthrough (exit 0)" {
  local ev; ev="$(bash_event "$(new_sid)" "ls -la")"
  run invoke_remind "$ev"
  [ "$status" -eq 0 ]
  [ "$output" = "$ev" ]
}

# 인자 위치의 'git commit' 문자열은 비발동 — regex 계약 고정
@test "remind-sync: 'echo git commit' argument position -> allowed (exit 0)" {
  local ev; ev="$(bash_event "$(new_sid)" "echo git commit")"
  run invoke_remind "$ev"
  [ "$status" -eq 0 ]
  [ "$output" = "$ev" ]
}

# 'git commitfoo' 접두 오탐 방지 — \b 계약 고정
@test "remind-sync: 'git commitfoo' -> allowed (exit 0)" {
  run invoke_remind "$(bash_event "$(new_sid)" "git commitfoo")"
  [ "$status" -eq 0 ]
}

# commit/push 외 git 서브커맨드는 비발동
@test "remind-sync: git status -> allowed (exit 0)" {
  run invoke_remind "$(bash_event "$(new_sid)" "git status")"
  [ "$status" -eq 0 ]
}

# ── 게이트 1: 킬스위치 ───────────────────────────────────────────────────────

@test "remind-sync: CLAUDE_MD_SYNC_REMIND=0 -> allowed (exit 0)" {
  export CLAUDE_MD_SYNC_REMIND=0
  local ev; ev="$(bash_event "$(new_sid)" "git commit -m x")"
  run invoke_remind "$ev"
  [ "$status" -eq 0 ]
  [ "$output" = "$ev" ]
}

# ── 게이트 2: CLAUDE.md 부재 프로젝트 ────────────────────────────────────────

@test "remind-sync: project without CLAUDE.md -> allowed (exit 0)" {
  rm -f "$TEST_PROJ/CLAUDE.md"
  local ev; ev="$(bash_event "$(new_sid)" "git commit -m x")"
  run invoke_remind "$ev"
  [ "$status" -eq 0 ]
  [ "$output" = "$ev" ]
}

# claude/CLAUDE.md 배치도 대상 — 발동한다
@test "remind-sync: claude/CLAUDE.md layout -> blocked (exit 2)" {
  rm -f "$TEST_PROJ/CLAUDE.md"
  mkdir -p "$TEST_PROJ/claude"
  printf '# CLAUDE.md\n' > "$TEST_PROJ/claude/CLAUDE.md"
  run invoke_remind "$(bash_event "$(new_sid)" "git commit -m x")"
  [ "$status" -eq 2 ]
}

# ── 프로젝트 디렉토리 폴백 ───────────────────────────────────────────────────

# CLAUDE_PROJECT_DIR 미설정 시 stdin cwd 기준으로 CLAUDE.md 를 찾는다
@test "remind-sync: no CLAUDE_PROJECT_DIR, cwd fallback -> blocked (exit 2)" {
  run invoke_remind_nodir "$(bash_event "$(new_sid)" "git commit -m x")"
  [ "$status" -eq 2 ]
}

# ── 견고성 ──────────────────────────────────────────────────────────────────

# 비정상 stdin(JSON 아님)에도 죽지 않고 통과
@test "remind-sync: malformed stdin -> allowed (exit 0)" {
  run bash -c "printf 'not-json' | CLAUDE_PROJECT_DIR='$TEST_PROJ' node '$REMIND_HOOK'"
  [ "$status" -eq 0 ]
}
