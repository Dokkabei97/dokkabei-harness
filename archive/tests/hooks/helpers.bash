# =============================================================================
# helpers.bash — 훅 bats 테스트 공통 헬퍼 (tests/hooks/*.bats 가 load 로 사용)
#
# 사용법 (각 .bats 파일 상단):
#   load 'helpers'
#   setup()    { make_project; }      # 임시 프로젝트 생성 + CLAUDE_PROJECT_DIR 설정
#   teardown() { cleanup_project; }   # 임시 프로젝트 제거
#
# 훅 실행 (bats 의 run 과 결합 — $status / $output(stdout+stderr 병합) 검증):
#   run invoke_hook "$MVP_HOOK"                       # stdin 기본 '{}'
#   run invoke_hook "$MVP_HOOK" '{"stop_hook_active":true}'
#   run invoke_hook_without_jq "$MVP_HOOK"            # PATH 를 빈 디렉토리로 바꿔
#                                                     # command -v jq 만 실패시킴
#                                                     # (jq 검사 이전 코드는 전부 bash 빌트인)
#   run invoke_hook_with_args "$PRECOMPACT_MVP" '{}' mvp   # 위치 인자 전달형 (+_without_jq 버전)
#
# headless 러너 실행 (bin/*-headless.sh — "프로젝트 루트에서 실행" 계약):
#   run invoke_runner "$MVP_HEADLESS"                 # 임시 프로젝트로 cd 후 실행
#   write_stub_claude 'exit 0'                        # no-op claude 스텁 생성 +
#                                                     # LOOP_CLAUDE_BIN 주입 (가드 env 는
#                                                     # 테스트에서 export LOOP_MAX_ITER=2)
#
# .planning fixture 작성 함수 (전부 $TEST_PROJ/.planning 하위에 기록):
#   activate_loop                                     # loop-active 마커 생성
#   write_gate_script  'echo "3 failed"; exit 1'      # gate.sh 생성 + gate-cmd 등록
#   write_e2e_script   'exit 0'                       # e2e.sh 생성 + e2e-gate-cmd 등록
#   write_prd   S-01=true S-02=false                  # prd.json (stories)
#   write_tasks T-01=true T-02=false                  # tasks.json (tasks)
#   write_loop_state '{"iteration":3,"max_iter":3}'   # loop-state.json (JSON 그대로)
#   write_baseline   '{"baseline_exit":1,"fail_count":3}'  # baseline.json
#   mark_verified S-01 S-02                           # verified/{id} 마커 생성
#   write_progress '<promise>MVP_COMPLETE</promise>'  # progress.md 기록
#   activate_loop_engine mvp                          # loop-active + "engine=" 소유 줄
#   write_verify_round V-01 1                         # verify-round/{id} = "round=1"
#   mark_refuted V-01 '근거'                          # refuted/{id} 마커(반증 성공) 생성
#
# 재사용 지침: 다른 테스트 파일(보안 훅/headless 러너 등)도 본 헬퍼를 load 해
# make_project + invoke_hook 만으로 "임시 프로젝트 + stdin JSON 주입 실행" 패턴을
# 재사용한다. 새 fixture 가 필요하면 여기에 write_* 함수로 추가한다.
# =============================================================================

# 대상 훅 절대 경로 — tests/hooks/ 에서 두 단계 위가 저장소 루트
REPO_ROOT="${REPO_ROOT:-$(cd "${BATS_TEST_DIRNAME:-$(dirname "${BASH_SOURCE[0]}")}/../.." && pwd)}"
MVP_HOOK="$REPO_ROOT/plugins/mvp/hooks/mvp-loop-stop-hook.sh"
FLOOP_HOOK="$REPO_ROOT/plugins/feature-loop/hooks/floop-loop-stop-hook.sh"
CAPTURE_BASELINE="$REPO_ROOT/plugins/feature-loop/hooks/gates/capture-baseline.sh"
PRD_GUARD="$REPO_ROOT/plugins/mvp/hooks/prd-guard.sh"
TEST_GUARD_MVP="$REPO_ROOT/plugins/mvp/hooks/test-guard.sh"
TEST_GUARD_FLOOP="$REPO_ROOT/plugins/feature-loop/hooks/test-guard.sh"
TASKS_GUARD="$REPO_ROOT/plugins/feature-loop/hooks/tasks-guard.sh"
GATE_PRD="$REPO_ROOT/plugins/mvp/hooks/gates/gate-prd.sh"
GATE_DESIGN="$REPO_ROOT/plugins/mvp/hooks/gates/gate-design.sh"
GATE_EVAL="$REPO_ROOT/plugins/mvp/hooks/gates/gate-eval.sh"
GATE_SCAFFOLD="$REPO_ROOT/plugins/mvp/hooks/gates/gate-scaffold.sh"
GATE_TASKS="$REPO_ROOT/plugins/feature-loop/hooks/gates/gate-tasks.sh"
MVP_HEADLESS="$REPO_ROOT/plugins/mvp/bin/mvp-headless.sh"
FLOOP_HEADLESS="$REPO_ROOT/plugins/feature-loop/bin/floop-headless.sh"
PRECOMPACT_MVP="$REPO_ROOT/plugins/mvp/hooks/precompact-anchor.sh"
PRECOMPACT_FLOOP="$REPO_ROOT/plugins/feature-loop/hooks/precompact-anchor.sh"
SUBAGENT_STOP_MVP="$REPO_ROOT/plugins/mvp/hooks/subagent-stop-verify.sh"
SUBAGENT_STOP_FLOOP="$REPO_ROOT/plugins/feature-loop/hooks/subagent-stop-verify.sh"
# 신규 도메인/거버넌스 게이트 디렉토리 — 게이트는 stdin 없이 "인자 exit 0/1" 계약
GOV_GATES="$REPO_ROOT/plugins/eng-gov/hooks/gates"
SCALEUP_GATES="$REPO_ROOT/plugins/scaleup/hooks/gates"
ENTERPRISE_GATES="$REPO_ROOT/plugins/enterprise/hooks/gates"

# ── 프로젝트 생성/정리 ────────────────────────────────────────────────────────

# 임시 프로젝트 생성 — mktemp -d + .planning 디렉토리 + CLAUDE_PROJECT_DIR 설정.
# LOOP_* env 누출 차단(로컬 셸 환경이 판정을 오염시키지 않도록 매 테스트 초기화).
make_project() {
  local base="${BATS_TEST_TMPDIR:-${TMPDIR:-/tmp}}"
  TEST_PROJ="$(mktemp -d "$base/hook-proj.XXXXXX")"
  mkdir -p "$TEST_PROJ/.planning"
  export CLAUDE_PROJECT_DIR="$TEST_PROJ"
  unset LOOP_TEST_CMD LOOP_E2E_CMD LOOP_PROMISE LOOP_MAX_ITER LOOP_MAX_MINUTES LOOP_CLAUDE_BIN 2>/dev/null || true
  # 게이트 판정 env 누출 차단 — 날짜 오버라이드와 외부 도구 <TOOL>_BIN 오버라이드
  unset GATE_TODAY GITLEAKS_BIN SYFT_BIN GRYPE_BIN CONFTEST_BIN THREAGILE_BIN DEPCRUISE_BIN LINT_IMPORTS_BIN 2>/dev/null || true
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

# headless 러너 실행 — 러너는 "프로젝트 루트에서 실행" 계약(상대 .planning)이므로
# 임시 프로젝트로 cd 한 서브셸에서 실행한다. LOOP_* env 는 호출부가 export 로 주입.
invoke_runner() {
  local runner="$1"
  ( cd "$TEST_PROJ" && bash "$runner" )
}

# 인자 전달형 훅 실행 — $1 스크립트, $2 stdin JSON, $3.. 스크립트 위치 인자
# (precompact-anchor.sh / subagent-stop-verify.sh 는 $1 로 플러그인 식별자 mvp|floop 를 받는다)
invoke_hook_with_args() {
  local hook="$1" stdin_json="${2:-"{}"}"
  shift 2
  printf '%s' "$stdin_json" | CLAUDE_PROJECT_DIR="$TEST_PROJ" bash "$hook" "$@"
}

# 인자 전달형 + jq 부재 시뮬레이션 — invoke_hook_without_jq 의 위치 인자 버전
invoke_hook_without_jq_with_args() {
  local hook="$1" stdin_json="${2:-"{}"}"
  shift 2
  local emptybin="$TEST_PROJ/.emptybin"
  mkdir -p "$emptybin"
  printf '%s' "$stdin_json" | CLAUDE_PROJECT_DIR="$TEST_PROJ" PATH="$emptybin" /bin/bash "$hook" "$@"
}

# ── .planning fixture 작성 ───────────────────────────────────────────────────

# 루프 활성 마커 — Stop훅 안전핀 해제
activate_loop() {
  : > "$TEST_PROJ/.planning/loop-active"
}

# 루프 활성 마커 + engine 소유 명시 — 공유 계약 1 ("engine=mvp|floop|generic" 1줄)
activate_loop_engine() {
  printf 'engine=%s\n' "$1" > "$TEST_PROJ/.planning/loop-active"
}

# verify-round pending 기록 — 공유 계약 2 (오케스트레이터가 verifier 디스패치 직전 기록)
# 사용: write_verify_round V-01 [round]  (round 기본 1, 내용은 "round=N" 1줄)
write_verify_round() {
  mkdir -p "$TEST_PROJ/.planning/verify-round"
  printf 'round=%s\n' "${2:-1}" > "$TEST_PROJ/.planning/verify-round/$1"
}

# refuted 마커 생성 — 반증 성공(구체 근거)을 .planning/refuted/{id} 에 기록
mark_refuted() {
  mkdir -p "$TEST_PROJ/.planning/refuted"
  printf '%s\n' "${2:-반증 성공 — 구체 근거}" > "$TEST_PROJ/.planning/refuted/$1"
}

# 게이트 명령 시뮬레이션 — $1 을 본문으로 gate.sh 생성 후 .planning/gate-cmd 에 등록.
# 예: write_gate_script 'exit 0' / write_gate_script 'echo "3 failed"; exit 1'
write_gate_script() {
  printf '#!/usr/bin/env bash\n%s\n' "$1" > "$TEST_PROJ/gate.sh"
  chmod +x "$TEST_PROJ/gate.sh"
  printf 'bash gate.sh\n' > "$TEST_PROJ/.planning/gate-cmd"
}

# E2E 게이트 명령 시뮬레이션 — $1 을 본문으로 e2e.sh 생성 후 .planning/e2e-gate-cmd 에 등록
write_e2e_script() {
  printf '#!/usr/bin/env bash\n%s\n' "$1" > "$TEST_PROJ/e2e.sh"
  chmod +x "$TEST_PROJ/e2e.sh"
  printf 'bash e2e.sh\n' > "$TEST_PROJ/.planning/e2e-gate-cmd"
}

# prd.json 생성 — 인자 형식 "id=passes" (예: write_prd S-01=true S-02=false)
write_prd() {
  local items="" e id passes
  for e in "$@"; do
    id="${e%%=*}"; passes="${e##*=}"
    items="${items:+$items,}{\"id\":\"$id\",\"title\":\"스토리 $id\",\"acceptance\":[\"수용 기준 1\"],\"passes\":$passes}"
  done
  printf '{"stories":[%s]}\n' "$items" > "$TEST_PROJ/.planning/prd.json"
}

# tasks.json 생성 — 인자 형식 "id=passes" (예: write_tasks T-01=true T-02=false)
write_tasks() {
  local items="" e id passes
  for e in "$@"; do
    id="${e%%=*}"; passes="${e##*=}"
    items="${items:+$items,}{\"id\":\"$id\",\"title\":\"task $id\",\"acceptance\":[\"수용 기준 1\"],\"passes\":$passes}"
  done
  printf '{"tasks":[%s]}\n' "$items" > "$TEST_PROJ/.planning/tasks.json"
}

# loop-state.json 기록 — $1 JSON 문자열 그대로 (필드 조합 자유)
write_loop_state() {
  printf '%s\n' "$1" > "$TEST_PROJ/.planning/loop-state.json"
}

# baseline.json 기록 — $1 JSON 문자열 그대로 (예: '{"baseline_exit":1,"fail_count":3}')
write_baseline() {
  printf '%s\n' "$1" > "$TEST_PROJ/.planning/baseline.json"
}

# verified 마커 생성 — 인자로 받은 각 id 에 대해 .planning/verified/{id} 생성
mark_verified() {
  local id
  mkdir -p "$TEST_PROJ/.planning/verified"
  for id in "$@"; do
    : > "$TEST_PROJ/.planning/verified/$id"
  done
}

# progress.md 기록 — 인자 전체를 내용으로 (promise 문자열 포함 여부는 호출부가 결정)
write_progress() {
  printf '%s\n' "$*" > "$TEST_PROJ/.planning/progress.md"
}

# claude 스텁 생성 — $1 을 본문으로 claude-stub.sh 생성 후 LOOP_CLAUDE_BIN 에 등록.
# headless 러너 테스트용(기본 no-op): 실제 claude 호출 없이 반복 골격만 검증한다.
write_stub_claude() {
  printf '#!/usr/bin/env bash\n%s\n' "${1:-exit 0}" > "$TEST_PROJ/claude-stub.sh"
  chmod +x "$TEST_PROJ/claude-stub.sh"
  export LOOP_CLAUDE_BIN="$TEST_PROJ/claude-stub.sh"
}

# ── 게이트 실행 (eng-gov/scaleup/enterprise) ─────────────────────────────────
# 게이트 계약: stdin 없음, exit 0=통과/1=실패(gate-error-budget 만 2=미측정),
# 위반은 stderr "[gate-X] 실패: …" 1줄씩. 날짜 판정은 GATE_TODAY(YYYY-MM-DD)
# env 로 결정론화, 외부 도구는 <TOOL>_BIN env 오버라이드(기본값 도구명) —
# write_stub_claude/LOOP_CLAUDE_BIN 과 동일 규약. 호스트 설치 여부와 무관하게
# 존재/부재를 테스트에서 주입한다 (부재: <TOOL>_BIN=/nonexistent/tool).
invoke_gate() {
  local gate="$1"; shift
  CLAUDE_PROJECT_DIR="$TEST_PROJ" bash "$gate" "$@"
}

# 외부 도구 스텁 생성 — $TEST_PROJ/.stubbin/<name> 에 $2 본문 실행 파일을 만들고
# 경로를 stdout 으로 돌려준다. 사용: export GITLEAKS_BIN="$(stub_tool gitleaks 'exit 0')"
stub_tool() {
  mkdir -p "$TEST_PROJ/.stubbin"
  printf '#!/usr/bin/env bash\n%s\n' "${2:-exit 0}" > "$TEST_PROJ/.stubbin/$1"
  chmod +x "$TEST_PROJ/.stubbin/$1"
  printf '%s' "$TEST_PROJ/.stubbin/$1"
}
