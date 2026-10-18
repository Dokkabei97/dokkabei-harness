#!/usr/bin/env bats
# =============================================================================
# mvp-headless.bats — MVP headless 러너 회귀 테스트
# 대상: plugins/mvp/bin/mvp-headless.sh
# 검증 축: 시작 거부(이중 가동·전제조건·headless-active 락) / 0회 반복 완료 종료 /
#          verified 마커 재검사 / 판정 규약 등가성(has_failure_marker) /
#          가드레일(max-iter·no-progress·E2E 시그니처·워치독) / 반복 중 loop-active
#          재검사 — claude 는 LOOP_CLAUDE_BIN 스텁으로 대체
# 규약: exit 0 = 완료·가드레일 도달, exit 1 = 시작 거부·충돌 방지 중단
# 주의: @test 이름은 ASCII 로 유지한다 — macOS 기본 bash 3.2 에서 bats 의
#       테스트명 인코딩이 한글(멀티바이트)을 깨뜨린다. 한국어 설명은 주석 참조.
# =============================================================================

load 'helpers'

# 워치독 env 는 helpers 의 make_project unset 목록에 없으므로 여기서 로컬 초기화
setup()    { make_project; unset LOOP_MAX_SECONDS LOOP_WATCHDOG_INTERVAL 2>/dev/null || true; }
teardown() { cleanup_project; }

# ── 시작 거부 (exit 1) ───────────────────────────────────────────────────────

# (1) 이중 가동 금지 — loop-active 존재 시 시작 거부 (Stop훅 엔진과 동시 가동 방지)
@test "headless: loop-active exists -> refuse to start (exit 1)" {
  activate_loop
  run invoke_runner "$MVP_HEADLESS"
  [ "$status" -eq 1 ]
  [[ "$output" == *"loop-active 존재"* ]]
}

# (2a) 전제조건 — prd.json 부재 시 명확한 에러 exit 1
@test "headless: missing prd.json -> exit 1 with clear error" {
  write_gate_script 'exit 0'
  write_stub_claude 'exit 0'
  run invoke_runner "$MVP_HEADLESS"
  [ "$status" -eq 1 ]
  [[ "$output" == *"prd.json 부재"* ]]
}

# (2b) 전제조건 — gate-cmd 부재 시 명확한 에러 exit 1
@test "headless: missing gate-cmd -> exit 1 with clear error" {
  write_prd S-01=false
  write_stub_claude 'exit 0'
  run invoke_runner "$MVP_HEADLESS"
  [ "$status" -eq 1 ]
  [[ "$output" == *"게이트 명령 없음"* ]]
}

# ── 정지조건 (완료 종료) ─────────────────────────────────────────────────────

# (3) 정지조건 이미 충족 — claude 호출 없이 iteration 0 에서 완료 종료
@test "headless: stop conditions already met -> completes at iteration 0 without claude" {
  write_gate_script 'exit 0'
  write_prd S-01=true
  mark_verified S-01
  write_progress '<promise>MVP_COMPLETE</promise>'
  write_stub_claude 'touch claude-ran; exit 0'
  run invoke_runner "$MVP_HEADLESS"
  [ "$status" -eq 0 ]
  [[ "$output" == *"정지조건"* ]]
  [[ "$output" == *"iteration 0"* ]]
  [ ! -f "$TEST_PROJ/claude-ran" ]
}

# (3b) verified 마커 재검사 — all-passes·promise 충족이어도 마커 없으면 완료로
#      판정하지 않는다 (recipe 대비 개선점 (c) — Stop훅 ② 최종 방어선과 등가)
@test "headless: passes true but verified marker missing -> not judged complete" {
  write_gate_script 'exit 0'
  write_prd S-01=true
  write_progress '<promise>MVP_COMPLETE</promise>'
  write_stub_claude 'exit 0'
  export LOOP_MAX_ITER=2
  run invoke_runner "$MVP_HEADLESS"
  [ "$status" -eq 0 ]
  [[ "$output" == *"max iterations"* ]]
  [[ "$output" != *"정지조건"* ]]
}

# ── 가드레일 ─────────────────────────────────────────────────────────────────

# (4) 스텁 claude(no-op) + 게이트 그린·미완 스토리 — max-iter 도달 종료 + loop-state 반영
@test "headless: stub claude no-op reaches max-iter -> exit 0 + loop-state updated" {
  write_gate_script 'exit 0'
  write_prd S-01=false
  write_stub_claude 'exit 0'
  export LOOP_MAX_ITER=2
  run invoke_runner "$MVP_HEADLESS"
  [ "$status" -eq 0 ]
  [[ "$output" == *"max iterations(2) 도달"* ]]
  [ "$(jq -r '.iteration' "$TEST_PROJ/.planning/loop-state.json")" = "2" ]
}

# (5) no-progress — 동일 실패 시그니처 연속 2회 → 중단 + BLOCKED.md 기록
#     (max-iter=3 이지만 no-progress 가 iteration 2 에서 먼저 멈춘다)
@test "headless: no-progress (same fail signature twice) -> exit 0 + BLOCKED.md" {
  write_gate_script 'echo "1 failed"; exit 1'
  write_prd S-01=false
  write_stub_claude 'exit 0'
  export LOOP_MAX_ITER=3
  run invoke_runner "$MVP_HEADLESS"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no-progress 감지"* ]]
  [[ "$output" != *"max iterations"* ]]
  [ -f "$TEST_PROJ/.planning/BLOCKED.md" ]
  grep -q "headless no-progress 차단" "$TEST_PROJ/.planning/BLOCKED.md"
}

# (5b) no-progress 시그니처 범위 — 단위 게이트는 그린이지만 E2E 가 연속 2회 동일하게
#      레드면, E2E 출력('E2E:' 접두 결합)도 시그니처에 포함되어(Stop훅과 동일 규약)
#      no-progress 로 멈춘다. E2E 는 all-passes 도달 시에만 실행된다.
@test "headless: e2e red twice with same signature -> no-progress stop" {
  write_gate_script 'exit 0'
  write_e2e_script 'echo "2 failed"; exit 1'
  write_prd S-01=true
  mark_verified S-01
  write_progress '<promise>MVP_COMPLETE</promise>'
  write_stub_claude 'exit 0'
  export LOOP_MAX_ITER=4
  run invoke_runner "$MVP_HEADLESS"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no-progress 감지"* ]]
  [[ "$output" != *"max iterations"* ]]
  [[ "$output" != *"정지조건"* ]]
  [ -f "$TEST_PROJ/.planning/BLOCKED.md" ]
}

# ── 판정 규약 등가성 (Stop훅 has_failure_marker 보정 — 회귀 방지) ─────────────

# (6) 게이트가 exit 0 이어도 출력에 실패 표지("3 failed")가 있으면 Stop훅과 동일하게
#     레드로 판정한다 — 나머지 전건(all-passes·마커·promise) 충족이어도 미완료
@test "headless: gate exit 0 with failure marker in output -> not judged complete" {
  write_gate_script 'echo "3 failed"; exit 0'
  write_prd S-01=true
  mark_verified S-01
  write_progress '<promise>MVP_COMPLETE</promise>'
  write_stub_claude 'exit 0'
  export LOOP_MAX_ITER=2
  run invoke_runner "$MVP_HEADLESS"
  [ "$status" -eq 0 ]
  [[ "$output" != *"정지조건"* ]]
  [[ "$output" == *"max iterations"* ]]
}

# ── 이중 가동 방지 (headless-active 락 · 반복 중 loop-active 재검사) ──────────

# (7) headless-active 락에 살아있는 PID 기록 — 크론 중첩 실행 방지로 시작 거부,
#     타 러너 소유 락은 보존한다
@test "headless: live headless-active lock -> refuse to start (exit 1)" {
  write_gate_script 'exit 0'
  write_prd S-01=false
  write_stub_claude 'exit 0'
  echo "$$" > "$TEST_PROJ/.planning/headless-active"
  run invoke_runner "$MVP_HEADLESS"
  [ "$status" -eq 1 ]
  [[ "$output" == *"headless-active 락 존재"* ]]
  [ -f "$TEST_PROJ/.planning/headless-active" ]
}

# (7b) 스테일 락(죽은 PID) — 제거 후 정상 진행(완료 판정까지), 종료 시 자기 락도
#      EXIT trap 으로 정리한다
@test "headless: stale headless-active lock -> removed and run proceeds" {
  write_gate_script 'exit 0'
  write_prd S-01=true
  mark_verified S-01
  write_progress '<promise>MVP_COMPLETE</promise>'
  write_stub_claude 'exit 0'
  ( : ) &
  local dead_pid=$!
  wait "$dead_pid" || true
  echo "$dead_pid" > "$TEST_PROJ/.planning/headless-active"
  run invoke_runner "$MVP_HEADLESS"
  [ "$status" -eq 0 ]
  [[ "$output" == *"스테일 headless-active 락"* ]]
  [[ "$output" == *"정지조건"* ]]
  [ ! -f "$TEST_PROJ/.planning/headless-active" ]
}

# (8) 반복 중 loop-active 출현(러너 가동 중 /mvp-run 으로 Stop훅 루프를 켠 상황) —
#     다음 반복 시작 시 재검사가 감지해 충돌 방지 중단(exit 1)
@test "headless: loop-active appears mid-loop -> abort with exit 1" {
  write_gate_script 'exit 0'
  write_prd S-01=false
  write_stub_claude 'touch .planning/loop-active'
  export LOOP_MAX_ITER=3
  run invoke_runner "$MVP_HEADLESS"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Stop훅 엔진 활성 감지"* ]]
}

# ── 워치독 (반복 도중 시간 상한 발동) ────────────────────────────────────────

# (9) 행(hang)하는 claude — 워치독이 전역 시간 상한(LOOP_MAX_SECONDS, 테스트용
#     override) 초과를 반복 도중 감지해 TERM→KILL 후 시간 상한 경로로 종료(exit 0).
#     스텁은 exec sleep — TERM 이 sleep 프로세스에 직접 전달되어 고아 프로세스가
#     출력 파이프를 물고 남지 않는다(bats run 캡처 지연 방지). 총 소요 수 초 이내.
@test "headless: watchdog kills hung claude at LOOP_MAX_SECONDS -> exit 0" {
  write_gate_script 'exit 0'
  write_prd S-01=false
  write_stub_claude 'exec sleep 30'
  export LOOP_MAX_SECONDS=2
  export LOOP_WATCHDOG_INTERVAL=1
  run invoke_runner "$MVP_HEADLESS"
  [ "$status" -eq 0 ]
  [[ "$output" == *"시간 상한"* ]]
  [[ "$output" == *"강제 종료"* ]]
  [ ! -f "$TEST_PROJ/.planning/headless-active" ]
}
