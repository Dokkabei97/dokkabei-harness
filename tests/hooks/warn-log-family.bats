#!/usr/bin/env bats
# =============================================================================
# warn-log-family.bats — 로그문 경고 훅 3종 회귀 테스트
# 대상: plugins/base/bin/hooks/warn-console-log.js (JS/TS console.log)
#       plugins/base/bin/hooks/warn-println.js    (Kotlin println)
#       plugins/base/bin/hooks/warn-print.js      (Python print)
# 규약: PostToolUse·비차단 — 항상 exit 0, 원본 passthrough, 경고는 stderr.
# 핵심: existsSync 통과 후 읽기 실패(EACCES/TOCTOU)에도 크래시하지 않고
#       조용히 passthrough 한다(try/catch 가드 회귀 방지).
# 주의: @test 이름은 ASCII. root 는 파일 권한을 우회하므로 unreadable 케이스는 skip.
# =============================================================================

bats_require_minimum_version 1.5.0

load 'helpers'

setup()    { make_project; }
teardown() { cleanup_project; }

CONSOLE_HOOK="$REPO_ROOT/plugins/base/bin/hooks/warn-console-log.js"
PRINTLN_HOOK="$REPO_ROOT/plugins/base/bin/hooks/warn-println.js"
PRINT_HOOK="$REPO_ROOT/plugins/base/bin/hooks/warn-print.js"

invoke_node_hook() {
  local hook="$1" stdin_json="${2:-"{}"}"
  printf '%s' "$stdin_json" | CLAUDE_PROJECT_DIR="$TEST_PROJ" node "$hook"
}
edit_event() { printf '{"tool":"Edit","tool_input":{"file_path":"%s"}}' "$1"; }

# ── 정상 탐지 ────────────────────────────────────────────────────────────────

@test "warn-console-log: console.log present -> stderr warning, passthrough" {
  printf 'function f(){ console.log("x"); }\n' > "$TEST_PROJ/a.ts"
  local ev; ev="$(edit_event "$TEST_PROJ/a.ts")"
  run --separate-stderr invoke_node_hook "$CONSOLE_HOOK" "$ev"
  [ "$status" -eq 0 ]
  [ "$output" = "$ev" ]
  [[ "$stderr" == *"console.log"* ]]
}

@test "warn-println: println present -> stderr warning, passthrough" {
  printf 'fun f() { println("x") }\n' > "$TEST_PROJ/A.kt"
  local ev; ev="$(edit_event "$TEST_PROJ/A.kt")"
  run --separate-stderr invoke_node_hook "$PRINTLN_HOOK" "$ev"
  [ "$status" -eq 0 ]
  [ "$output" = "$ev" ]
  [[ "$stderr" == *"println"* ]]
}

@test "warn-print: print present -> stderr warning, passthrough" {
  printf 'def f():\n    print("x")\n' > "$TEST_PROJ/a.py"
  local ev; ev="$(edit_event "$TEST_PROJ/a.py")"
  run --separate-stderr invoke_node_hook "$PRINT_HOOK" "$ev"
  [ "$status" -eq 0 ]
  [ "$output" = "$ev" ]
  [[ "$stderr" == *"print()"* ]]
}

# ── 크래시 방지 (readFileSync 가드) ──────────────────────────────────────────

@test "warn-console-log: unreadable file -> quiet passthrough, no crash" {
  if [ "$(id -u)" -eq 0 ]; then skip "root 는 파일 권한을 우회한다"; fi
  printf 'console.log("x");\n' > "$TEST_PROJ/locked.ts"
  chmod 000 "$TEST_PROJ/locked.ts"
  local ev; ev="$(edit_event "$TEST_PROJ/locked.ts")"
  run --separate-stderr invoke_node_hook "$CONSOLE_HOOK" "$ev"
  chmod 644 "$TEST_PROJ/locked.ts"
  [ "$status" -eq 0 ]
  [ "$output" = "$ev" ]
  [ -z "$stderr" ]
}

@test "warn-println: unreadable file -> quiet passthrough, no crash" {
  if [ "$(id -u)" -eq 0 ]; then skip "root 는 파일 권한을 우회한다"; fi
  printf 'println("x")\n' > "$TEST_PROJ/Locked.kt"
  chmod 000 "$TEST_PROJ/Locked.kt"
  local ev; ev="$(edit_event "$TEST_PROJ/Locked.kt")"
  run --separate-stderr invoke_node_hook "$PRINTLN_HOOK" "$ev"
  chmod 644 "$TEST_PROJ/Locked.kt"
  [ "$status" -eq 0 ]
  [ "$output" = "$ev" ]
  [ -z "$stderr" ]
}

@test "warn-print: unreadable file -> quiet passthrough, no crash" {
  if [ "$(id -u)" -eq 0 ]; then skip "root 는 파일 권한을 우회한다"; fi
  printf 'print("x")\n' > "$TEST_PROJ/locked.py"
  chmod 000 "$TEST_PROJ/locked.py"
  local ev; ev="$(edit_event "$TEST_PROJ/locked.py")"
  run --separate-stderr invoke_node_hook "$PRINT_HOOK" "$ev"
  chmod 644 "$TEST_PROJ/locked.py"
  [ "$status" -eq 0 ]
  [ "$output" = "$ev" ]
  [ -z "$stderr" ]
}
