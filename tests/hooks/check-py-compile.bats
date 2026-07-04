#!/usr/bin/env bats
# =============================================================================
# check-py-compile.bats — base 플러그인 Python 문법 검사 훅 회귀 테스트
# 대상: plugins/base/bin/hooks/check-py-compile.js
#       (PostToolUse: .py 편집 후 py_compile 로 문법 검사, 경고 전용·비차단)
# 규약: 항상 exit 0 + 원본 passthrough, 오류는 stderr.
# 핵심: execFileSync(인자 배열) 사용 — 파일명에 $()/백틱이 있어도 셸 명령
#       치환(RCE)이 일어나지 않는다(과거 execSync 문자열 보간 취약점 회귀 가드).
# 주의: @test 이름은 ASCII. python3 부재 시 skip.
# =============================================================================

bats_require_minimum_version 1.5.0

load 'helpers'

setup()    { make_project; command -v python3 >/dev/null 2>&1 || skip "python3 미설치"; }
teardown() { cleanup_project; }

PY_HOOK="$REPO_ROOT/plugins/base/bin/hooks/check-py-compile.js"

invoke_node_hook() {
  local hook="$1" stdin_json="${2:-"{}"}"
  printf '%s' "$stdin_json" | CLAUDE_PROJECT_DIR="$TEST_PROJ" node "$hook"
}
edit_event() { printf '{"tool":"Edit","tool_input":{"file_path":"%s"}}' "$1"; }

# ── 정상/오류 ────────────────────────────────────────────────────────────────

@test "check-py-compile: valid python -> no error, passthrough" {
  printf 'def add(a, b):\n    return a + b\n' > "$TEST_PROJ/ok.py"
  local ev; ev="$(edit_event "$TEST_PROJ/ok.py")"
  run --separate-stderr invoke_node_hook "$PY_HOOK" "$ev"
  [ "$status" -eq 0 ]
  [ "$output" = "$ev" ]
  [ -z "$stderr" ]
}

@test "check-py-compile: syntax error -> stderr warning, still exit 0" {
  printf 'def broken(:\n    pass\n' > "$TEST_PROJ/bad.py"
  local ev; ev="$(edit_event "$TEST_PROJ/bad.py")"
  run --separate-stderr invoke_node_hook "$PY_HOOK" "$ev"
  [ "$status" -eq 0 ]
  [ "$output" = "$ev" ]
  [[ "$stderr" == *"Python syntax error"* ]]
}

# ── 비대상 ──────────────────────────────────────────────────────────────────

@test "check-py-compile: non-.py file -> passthrough" {
  printf 'const x = 1;\n' > "$TEST_PROJ/app.js"
  local ev; ev="$(edit_event "$TEST_PROJ/app.js")"
  run --separate-stderr invoke_node_hook "$PY_HOOK" "$ev"
  [ "$status" -eq 0 ]
  [ "$output" = "$ev" ]
  [ -z "$stderr" ]
}

# ── 보안: 명령 치환 인젝션 차단 (RCE 회귀 가드) ────────────────────────────────

# 악성 파일명에 $() 명령 치환이 포함돼도, execFileSync 인자 배열 전달이라
# 셸을 거치지 않아 명령이 실행되지 않는다. 파일명은 리터럴로 생성(작은따옴표라
# 셸 확장 없음)하고, cwd 를 TEST_PROJ 로 고정해 취약 시 MARKER 가 여기 생기게 한다.
@test "check-py-compile: command-substitution in filename -> not executed" {
  local fname='x$(touch MARKER).py'   # 리터럴 — bash 변수값 내 명령치환은 재실행되지 않는다
  : > "$TEST_PROJ/$fname"             # 해당 이름의 파일을 실제 생성(existsSync 가드 통과)
  local ev
  ev="$(printf '{"tool":"Edit","tool_input":{"file_path":"%s/%s"}}' "$TEST_PROJ" "$fname")"
  ( cd "$TEST_PROJ" && printf '%s' "$ev" | CLAUDE_PROJECT_DIR="$TEST_PROJ" node "$PY_HOOK" >/dev/null 2>&1 ) || true
  # execSync 였다면 셸이 touch MARKER 를 실행해 마커가 생긴다 — execFileSync 는 생기지 않는다
  [ ! -f "$TEST_PROJ/MARKER" ]
}
