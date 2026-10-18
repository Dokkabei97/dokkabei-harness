# =============================================================================
# helpers.bash — 훅 bats 테스트 공통 헬퍼 (tests/hooks/*.bats 가 load 로 사용)
#
# 사용법 (각 .bats 파일 상단):
#   load 'helpers'
#   setup()    { make_project; }      # 임시 프로젝트 생성 + CLAUDE_PROJECT_DIR 설정
#   teardown() { cleanup_project; }   # 임시 프로젝트 제거
#
# 훅 실행 (bats 의 run 과 결합 — $status / $output(stdout+stderr 병합) 검증):
#   run invoke_hook "$GENERIC_HOOK"                   # stdin 기본 '{}'
#   run invoke_hook "$GENERIC_HOOK" '{"stop_hook_active":true}'
#   run invoke_hook_without_jq "$TEST_GUARD"          # PATH 를 빈 디렉토리로 바꿔
#                                                     # command -v jq 만 실패시킴
#                                                     # (jq 검사 이전 코드는 전부 bash 빌트인)
#
# .planning fixture 작성 함수 (전부 $TEST_PROJ/.planning 하위에 기록):
#   activate_loop                                     # loop-active 마커 생성 (engine 줄 없음 = 레거시)
#   activate_loop_engine generic                      # loop-active + "engine=" 소유 줄
#   write_gate_script  'echo "3 failed"; exit 1'      # gate.sh 생성 + gate-cmd 등록
#   write_loop_state '{"iteration":3,"max_iter":3}'   # loop-state.json (JSON 그대로)
#   write_progress '<promise>LOOP_COMPLETE</promise>' # progress.md 기록
#
# mvp/feature-loop 등 archive 된 플러그인의 테스트·헬퍼 원본은 archive/tests/hooks/ 에 보존.
# =============================================================================

# 대상 훅 절대 경로 — tests/hooks/ 에서 두 단계 위가 저장소 루트
REPO_ROOT="${REPO_ROOT:-$(cd "${BATS_TEST_DIRNAME:-$(dirname "${BASH_SOURCE[0]}")}/../.." && pwd)}"
GENERIC_HOOK="$REPO_ROOT/plugins/harness/hooks/generic-loop-stop-hook.sh"
TEST_GUARD="$REPO_ROOT/plugins/harness/hooks/test-guard.sh"

# ── 프로젝트 생성/정리 ────────────────────────────────────────────────────────

# 임시 프로젝트 생성 — mktemp -d + .planning 디렉토리 + CLAUDE_PROJECT_DIR 설정.
# LOOP_* env 누출 차단(로컬 셸 환경이 판정을 오염시키지 않도록 매 테스트 초기화).
make_project() {
  local base="${BATS_TEST_TMPDIR:-${TMPDIR:-/tmp}}"
  TEST_PROJ="$(mktemp -d "$base/hook-proj.XXXXXX")"
  mkdir -p "$TEST_PROJ/.planning"
  export CLAUDE_PROJECT_DIR="$TEST_PROJ"
  unset LOOP_TEST_CMD LOOP_PROMISE LOOP_MAX_ITER LOOP_MAX_MINUTES 2>/dev/null || true
}

cleanup_project() {
  [ -n "${TEST_PROJ:-}" ] && rm -rf "$TEST_PROJ"
  unset CLAUDE_PROJECT_DIR
}

# ── 훅 실행 ──────────────────────────────────────────────────────────────────

# stdin JSON 주입 실행 — $1 스크립트 절대 경로, $2 stdin JSON(기본 '{}').
# 훅과 동일한 계약(stdin=JSON, CLAUDE_PROJECT_DIR env)으로 호출한다.
invoke_hook() {
  local hook="$1" stdin_json="${2:-"{}"}"
  printf '%s' "$stdin_json" | CLAUDE_PROJECT_DIR="$TEST_PROJ" bash "$hook"
}

# jq 부재 시뮬레이션 실행 — PATH 를 빈 디렉토리로 바꿔 command -v jq 만 실패시킨다.
# 셔뱅 우회를 위해 /bin/bash 절대 경로로 실행 (macOS/Linux 공통 존재).
invoke_hook_without_jq() {
  local hook="$1" stdin_json="${2:-"{}"}"
  local emptybin="$TEST_PROJ/.emptybin"
  mkdir -p "$emptybin"
  printf '%s' "$stdin_json" | CLAUDE_PROJECT_DIR="$TEST_PROJ" PATH="$emptybin" /bin/bash "$hook"
}

# ── .planning fixture 작성 ───────────────────────────────────────────────────

# 루프 활성 마커 — Stop훅 안전핀 해제 (engine 줄 없음 = 레거시)
activate_loop() {
  : > "$TEST_PROJ/.planning/loop-active"
}

# 루프 활성 마커 + engine 소유 명시 ("engine=<name>" 1줄)
activate_loop_engine() {
  printf 'engine=%s\n' "$1" > "$TEST_PROJ/.planning/loop-active"
}

# 게이트 명령 시뮬레이션 — $1 을 본문으로 gate.sh 생성 후 .planning/gate-cmd 에 등록.
# 예: write_gate_script 'exit 0' / write_gate_script 'echo "3 failed"; exit 1'
write_gate_script() {
  printf '#!/usr/bin/env bash\n%s\n' "$1" > "$TEST_PROJ/gate.sh"
  chmod +x "$TEST_PROJ/gate.sh"
  printf 'bash gate.sh\n' > "$TEST_PROJ/.planning/gate-cmd"
}

# loop-state.json 기록 — $1 JSON 문자열 그대로 (필드 조합 자유)
write_loop_state() {
  printf '%s\n' "$1" > "$TEST_PROJ/.planning/loop-state.json"
}

# progress.md 기록 — 인자 전체를 내용으로 (promise 문자열 포함 여부는 호출부가 결정)
write_progress() {
  printf '%s\n' "$*" > "$TEST_PROJ/.planning/progress.md"
}
