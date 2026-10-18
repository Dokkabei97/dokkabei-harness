#!/usr/bin/env bats
# =============================================================================
# capture-baseline.bats — Stage A baseline 캡처 스크립트 회귀 테스트
# 대상: plugins/feature-loop/hooks/gates/capture-baseline.sh
# 검증 축: extract_fail_count 규약 — green→0 / "N failed" red→N / 카운트 없는
#          red→-1 / gate-cmd 부재→exit 1. baseline.json 산출 필드 확인.
# 주의: @test 이름은 ASCII — macOS 기본 bash 3.2 의 bats 한글 테스트명 인코딩
#       문제 회피. 한국어 설명은 주석 참조.
# =============================================================================

load 'helpers'

setup()    { make_project; }
teardown() { cleanup_project; }

# green 기준선 — baseline_exit 0 / fail_count 0
@test "green gate-cmd: baseline_exit 0 + fail_count 0" {
  write_gate_script 'echo "5 passed"; exit 0'
  run invoke_hook "$CAPTURE_BASELINE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"클린 기준선 캡처"* ]]
  [ "$(jq -r '.baseline_exit' "$TEST_PROJ/.planning/baseline.json")" = "0" ]
  [ "$(jq -r '.fail_count' "$TEST_PROJ/.planning/baseline.json")" = "0" ]
}

# red 기준선 + "3 failed" 출력 — fail_count 3 추출 (경고만, exit 0)
@test "red gate-cmd with '3 failed': fail_count 3" {
  write_gate_script 'echo "3 failed, 2 passed"; exit 1'
  run invoke_hook "$CAPTURE_BASELINE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"기존 실패 3개"* ]]
  [ "$(jq -r '.baseline_exit' "$TEST_PROJ/.planning/baseline.json")" = "1" ]
  [ "$(jq -r '.fail_count' "$TEST_PROJ/.planning/baseline.json")" = "3" ]
}

# red 기준선 + 카운트 없는 출력 — fail_count -1 (exit code 로만 보수 판정 예고)
@test "red gate-cmd without count: fail_count -1" {
  write_gate_script 'echo "segfault"; exit 2'
  run invoke_hook "$CAPTURE_BASELINE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"파싱 불가"* ]]
  [ "$(jq -r '.fail_count' "$TEST_PROJ/.planning/baseline.json")" = "-1" ]
}

# gate-cmd 부재 — exit 1 + baseline.json 미생성
@test "no gate-cmd: exit 1 and no baseline.json" {
  run invoke_hook "$CAPTURE_BASELINE"
  [ "$status" -eq 1 ]
  [[ "$output" == *"gate-cmd 없음"* ]]
  [ ! -f "$TEST_PROJ/.planning/baseline.json" ]
}

# 인자로 게이트 명령 직접 전달 — .planning/gate-cmd 없이도 캡처 가능
@test "gate command passed as argument overrides file lookup" {
  run bash -c 'CLAUDE_PROJECT_DIR="$1" bash "$2" "exit 0"' _ "$TEST_PROJ" "$CAPTURE_BASELINE"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.baseline_exit' "$TEST_PROJ/.planning/baseline.json")" = "0" ]
  [ "$(jq -r '.gate_cmd' "$TEST_PROJ/.planning/baseline.json")" = "exit 0" ]
}
