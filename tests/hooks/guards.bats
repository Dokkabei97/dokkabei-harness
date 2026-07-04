#!/usr/bin/env bats
# =============================================================================
# guards.bats — 가드 훅 회귀 테스트 (2차 범위)
# 대상: plugins/mvp/hooks/prd-guard.sh (PostToolUse: Edit|Write on prd.json)
#       plugins/feature-loop/hooks/tasks-guard.sh (PostToolUse: Edit|Write on tasks.json)
#       plugins/mvp/hooks/test-guard.sh · plugins/feature-loop/hooks/test-guard.sh
#       (PreToolUse: Bash — 루프 활성 중 테스트 삭제 차단)
# 규약: exit 0 = 허용, exit 2 = 차단
# 주의: @test 이름은 ASCII — macOS 기본 bash 3.2 의 bats 한글 테스트명 인코딩
#       문제 회피. 한국어 설명은 주석 참조.
# =============================================================================

load 'helpers'

setup()    { make_project; }
teardown() { cleanup_project; }

# prd-guard/tasks-guard 는 stdin 의 tool_input.file_path 가 정본 경로일 때만 검사한다
# (2차 경로 필터). 실제 PostToolUse 이벤트를 시뮬레이션하려면 file_path 를 넣어야 한다.
prd_event()   { printf '{"tool":"Edit","tool_input":{"file_path":"%s/.planning/prd.json"}}' "$TEST_PROJ"; }
tasks_event() { printf '{"tool":"Edit","tool_input":{"file_path":"%s/.planning/tasks.json"}}' "$TEST_PROJ"; }

# ── prd-guard — maker/checker 분리 강제 ──────────────────────────────────────

# 마커 없는 passes:true — 차단 + prd.json passes 를 false 로 원복
@test "prd-guard: passes true without marker -> exit 2 + passes reverted to false" {
  write_prd S-01=true S-02=false
  run invoke_hook "$PRD_GUARD" "$(prd_event)"
  [ "$status" -eq 2 ]
  [[ "$output" == *"false 로 원복"* ]]
  [[ "$output" == *"S-01"* ]]
  [ "$(jq -r '.stories[] | select(.id=="S-01") | .passes' "$TEST_PROJ/.planning/prd.json")" = "false" ]
}

# 마커 있는 passes:true — 통과 + passes 유지
@test "prd-guard: passes true with marker -> exit 0 + passes kept" {
  write_prd S-01=true S-02=false
  mark_verified S-01
  run invoke_hook "$PRD_GUARD" "$(prd_event)"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.stories[] | select(.id=="S-01") | .passes' "$TEST_PROJ/.planning/prd.json")" = "true" ]
}

# prd.json 부재 — 무동작 통과
@test "prd-guard: no prd.json -> exit 0" {
  run invoke_hook "$PRD_GUARD"
  [ "$status" -eq 0 ]
}

# ── tasks-guard — prd-guard 의 브라운필드판 ──────────────────────────────────

@test "tasks-guard: passes true without marker -> exit 2 + passes reverted" {
  write_tasks T-01=true T-02=false
  run invoke_hook "$TASKS_GUARD" "$(tasks_event)"
  [ "$status" -eq 2 ]
  [[ "$output" == *"false 로 원복"* ]]
  [ "$(jq -r '.tasks[] | select(.id=="T-01") | .passes' "$TEST_PROJ/.planning/tasks.json")" = "false" ]
}

@test "tasks-guard: passes true with marker -> exit 0" {
  write_tasks T-01=true
  mark_verified T-01
  run invoke_hook "$TASKS_GUARD" "$(tasks_event)"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.tasks[] | select(.id=="T-01") | .passes' "$TEST_PROJ/.planning/tasks.json")" = "true" ]
}

# ── test-guard — 루프 활성 중 테스트 삭제 차단 ───────────────────────────────

# 루프 활성 + rm 대상에 tests/ — 차단
@test "test-guard(mvp): rm -rf tests/ while loop active -> exit 2" {
  activate_loop
  run invoke_hook "$TEST_GUARD_MVP" '{"tool_input":{"command":"rm -rf tests/"}}'
  [ "$status" -eq 2 ]
  [[ "$output" == *"테스트 삭제 금지"* ]]
}

# .spec. 파일 삭제 — 차단 유지
@test "test-guard(mvp): rm foo.spec.ts -> exit 2" {
  activate_loop
  run invoke_hook "$TEST_GUARD_MVP" '{"tool_input":{"command":"rm foo.spec.ts"}}'
  [ "$status" -eq 2 ]
}

# 'latest.log' 류 오탐 — 허용 (test 토큰이 비알파벳 경계로 시작하지 않음)
@test "test-guard(mvp): rm latest.log -> exit 0 (no false positive)" {
  activate_loop
  run invoke_hook "$TEST_GUARD_MVP" '{"tool_input":{"command":"rm latest.log"}}'
  [ "$status" -eq 0 ]
}

# 루프 비활성 — 무동작 통과
@test "test-guard(mvp): loop inactive -> exit 0 even for rm tests/" {
  run invoke_hook "$TEST_GUARD_MVP" '{"tool_input":{"command":"rm -rf tests/"}}'
  [ "$status" -eq 0 ]
}

# floop 판 동일 로직 스모크 — 차단 메시지가 /floop-stop 을 안내
@test "test-guard(floop): rm -rf tests/ while loop active -> exit 2 with floop message" {
  activate_loop
  run invoke_hook "$TEST_GUARD_FLOOP" '{"tool_input":{"command":"rm -rf tests/"}}'
  [ "$status" -eq 2 ]
  [[ "$output" == *"/floop-stop"* ]]
}

# engine 스코프 가드 — engine=generic 루프에는 mvp test-guard 무개입 (타 엔진 무개입 원칙)
@test "test-guard(mvp): engine=generic loop -> exit 0 even for rm tests/" {
  activate_loop_engine generic
  run invoke_hook "$TEST_GUARD_MVP" '{"tool_input":{"command":"rm -rf tests/"}}'
  [ "$status" -eq 0 ]
}
