#!/usr/bin/env bats
# =============================================================================
# generic-loop.bats — generic 경량 루프 엔진(Stop 훅) 회귀 테스트
# 대상: plugins/harness/hooks/generic-loop-stop-hook.sh
# 검증 축: 안전핀 / engine 스코프(공유 계약 — 레거시 무주장·타 엔진 무개입·CRLF 방어) /
#          정지조건 ①(게이트 exit code + has_failure_marker 보정) ②(promise, AND 결합) /
#          가드레일(max-iter · no-progress · 시간 상한) / 턴 블록 상한(8 — stop_hook_active 카운터)
# 규약: exit 0 = 종료 허용, exit 2 = 종료 차단(stderr 재주입)
# 주의: @test 이름은 ASCII 로 유지한다 — macOS 기본 bash 3.2 에서 bats 의
#       테스트명 인코딩이 한글(멀티바이트)을 깨뜨려 "unknown test name" 이 된다.
#       한국어 설명은 각 테스트의 주석으로 제공한다.
# =============================================================================

load 'helpers'

setup()    { make_project; }
teardown() { cleanup_project; }

# ── 안전핀 · engine 스코프 (공유 계약 — loop-active engine 스코프) ────────────

# (a) 안전핀 — loop-active 부재 시 즉시 exit 0 (루프 미가동 세션의 종료는 방해 금지)
@test "safety-pin: no loop-active -> exit 0" {
  run invoke_hook "$GENERIC_HOOK"
  [ "$status" -eq 0 ]
}

# (b) 빈 loop-active(engine 줄 없음 = 레거시, archive 된 엔진 잔존물) — generic 훅은 무주장:
#     게이트 red 여도 판정 없이 조용히 exit 0, loop-active 유지
@test "engine scope: legacy empty loop-active -> silent exit 0 without claim" {
  activate_loop
  write_gate_script 'echo "1 failed"; exit 1'
  run invoke_hook "$GENERIC_HOOK"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -f "$TEST_PROJ/.planning/loop-active" ]
}

# (c) engine=mvp — 타 엔진 소유 루프에는 무개입 exit 0 (loop-active 유지)
@test "engine scope: engine=mvp loop-active -> silent exit 0" {
  activate_loop_engine mvp
  write_gate_script 'echo "1 failed"; exit 1'
  run invoke_hook "$GENERIC_HOOK"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -f "$TEST_PROJ/.planning/loop-active" ]
}

# (c') CRLF 로 기록된 engine=generic — tr -d '\r' 방어로 소유 인정(게이트 red 면 exit 2)
#      CRLF 로 기록된 loop-active 판정 확인
@test "engine scope: engine=generic with CRLF -> owned, gate red exit 2" {
  printf 'engine=generic\r\n' > "$TEST_PROJ/.planning/loop-active"
  write_gate_script 'echo "1 failed"; exit 1'
  run invoke_hook "$GENERIC_HOOK"
  [ "$status" -eq 2 ]
  [[ "$output" == *"결정론 게이트 실패"* ]]
}

# ── 정지조건 ① 게이트 판정 ───────────────────────────────────────────────────

# (d) engine=generic + 게이트 red(exit 1) — exit 2 재주입 + iteration 증가
@test "engine=generic + gate red: exit 2 + reinjection + iteration incremented" {
  activate_loop_engine generic
  write_gate_script 'echo "1 failed"; exit 1'
  run invoke_hook "$GENERIC_HOOK"
  [ "$status" -eq 2 ]
  [[ "$output" == *"작업 미완료"* ]]
  [[ "$output" == *"결정론 게이트 실패"* ]]
  [ "$(jq -r '.iteration' "$TEST_PROJ/.planning/loop-state.json")" = "1" ]
}

# (e) 게이트 green('0 failed' 출력 포함 — has_failure_marker 오탐 방지 확인) + promise
#     — 정지조건 2결합 충족으로 exit 0 + loop-active 해제
@test "gate green with '0 failed' output + promise: exit 0 + loop-active removed" {
  activate_loop_engine generic
  write_gate_script 'echo "2 passed, 0 failed"; exit 0'
  write_progress '작업 완료. <promise>LOOP_COMPLETE</promise>'
  run invoke_hook "$GENERIC_HOOK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"정지조건 충족"* ]]
  [ ! -f "$TEST_PROJ/.planning/loop-active" ]
}

# (f) 게이트 exit 0 인데 출력에 "3 failed" — has_failure_marker 보정으로 red 판정 → exit 2
@test "gate exit 0 but output '3 failed': judged red by failure marker -> exit 2" {
  activate_loop_engine generic
  write_gate_script 'echo "3 failed"; exit 0'
  run invoke_hook "$GENERIC_HOOK"
  [ "$status" -eq 2 ]
  [[ "$output" == *"결정론 게이트 실패"* ]]
}

# (f') 게이트 green 인데 promise 부재 — ①만으로는 정지 불가(② AND 결합) → exit 2 재주입
#      + loop-active 유지 (promise 기록 지시 포함)
@test "gate green without promise: exit 2 + promise instruction + loop-active kept" {
  activate_loop_engine generic
  write_gate_script 'exit 0'
  run invoke_hook "$GENERIC_HOOK"
  [ "$status" -eq 2 ]
  [[ "$output" == *"LOOP_COMPLETE"* ]]
  [ -f "$TEST_PROJ/.planning/loop-active" ]
}

# (f'') 무음 red(exit 1, 출력 없음) + promise 존재 — 실패 표지가 없어도 exit code 우선
#       판정으로 red → exit 2 (출력 grep 단독 판정 돌연변이 적발)
@test "silent gate red exit 1 no output with promise: exit 2 by exit-code-first judgment" {
  activate_loop_engine generic
  write_gate_script 'exit 1'
  write_progress '작업 완료. <promise>LOOP_COMPLETE</promise>'
  run invoke_hook "$GENERIC_HOOK"
  [ "$status" -eq 2 ]
  [[ "$output" == *"결정론 게이트 실패"* ]]
  [[ "$output" == *"exit=1"* ]]
}

# ── 가드레일 ─────────────────────────────────────────────────────────────────

# (g) max-iter 도달 — exit 0 + loop-active 삭제 (미완 보고 포함)
@test "guardrail max-iter: exit 0 + loop-active removed" {
  activate_loop_engine generic
  write_gate_script 'exit 0'
  write_loop_state '{"iteration":3,"max_iter":3}'
  run invoke_hook "$GENERIC_HOOK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"max iterations"* ]]
  [ ! -f "$TEST_PROJ/.planning/loop-active" ]
}

# (h) no-progress — 동일 실패 시그니처 연속 2회(1회차 exit 2 후 같은 상태로 2회차)
#     → exit 0 + BLOCKED.md 기록(엔진 표기) + loop-active 삭제
@test "guardrail no-progress: same fail signature twice -> exit 0 + BLOCKED.md + loop-active removed" {
  activate_loop_engine generic
  write_gate_script 'echo "1 failed"; exit 1'
  run invoke_hook "$GENERIC_HOOK"
  [ "$status" -eq 2 ]
  run invoke_hook "$GENERIC_HOOK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no-progress 감지"* ]]
  [ -f "$TEST_PROJ/.planning/BLOCKED.md" ]
  grep -q "엔진: generic" "$TEST_PROJ/.planning/BLOCKED.md"
  [ ! -f "$TEST_PROJ/.planning/loop-active" ]
}

# (i) 시간 상한 — started_at 을 과거(epoch 1000000)로 조작해 MAX_MINUTES 초과
#     → exit 0 + loop-active 해제 (시간 상한 가드레일 실동작 확인)
@test "guardrail time-limit: started_at far in the past -> exit 0 + loop-active removed" {
  activate_loop_engine generic
  write_gate_script 'exit 0'
  write_loop_state '{"iteration":1,"started_at":1000000,"max_minutes":60}'
  run invoke_hook "$GENERIC_HOOK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"시간 상한 도달"* ]]
  [ ! -f "$TEST_PROJ/.planning/loop-active" ]
}

# ── 턴 블록 상한 (Claude Code 는 연속 8블록 후 9번째 exit 2 를 무시) ─────────────

# (j) 같은 턴 재진입(stop_hook_active=true) — turn_blocks 누적
@test "turn-block counter: reentry increments turn_blocks" {
  activate_loop_engine generic
  write_gate_script 'echo "1 failed"; exit 1'
  write_loop_state '{"iteration":2,"turn_blocks":3}'
  run invoke_hook "$GENERIC_HOOK" '{"stop_hook_active":true}'
  [ "$status" -eq 2 ]
  [ "$(jq -r '.turn_blocks' "$TEST_PROJ/.planning/loop-state.json")" = "4" ]
}

# (k) 새 턴(stop_hook_active=false) — 이전 턴 카운터가 커도 리셋 후 차단
@test "turn-block counter: new turn resets turn_blocks and blocks" {
  activate_loop_engine generic
  write_gate_script 'echo "1 failed"; exit 1'
  write_loop_state '{"iteration":9,"turn_blocks":8}'
  run invoke_hook "$GENERIC_HOOK" '{"stop_hook_active":false}'
  [ "$status" -eq 2 ]
  [ "$(jq -r '.turn_blocks' "$TEST_PROJ/.planning/loop-state.json")" = "1" ]
}

# (l) 이번 턴 8회 차단 후 9번째 호출 — 차단 대신 progress.md 핸드오프 + exit 0,
#     loop-active 유지(다음 턴 재개)
@test "turn-block cap: 8 blocks in turn -> handoff to progress.md + exit 0 + loop-active kept" {
  activate_loop_engine generic
  write_gate_script 'echo "1 failed"; exit 1'
  write_loop_state '{"iteration":8,"turn_blocks":8}'
  run invoke_hook "$GENERIC_HOOK" '{"stop_hook_active":true}'
  [ "$status" -eq 0 ]
  [[ "$output" == *"턴을 넘긴다"* ]]
  grep -q "턴 블록 상한 핸드오프" "$TEST_PROJ/.planning/progress.md"
  [ -f "$TEST_PROJ/.planning/loop-active" ]
}

# (m) 상한 도달 턴이어도 정지조건 충족이면 정상 종료가 우선
@test "turn-block cap: stop condition met takes precedence over handoff" {
  activate_loop_engine generic
  write_gate_script 'exit 0'
  write_progress '<promise>LOOP_COMPLETE</promise>'
  write_loop_state '{"iteration":8,"turn_blocks":8}'
  run invoke_hook "$GENERIC_HOOK" '{"stop_hook_active":true}'
  [ "$status" -eq 0 ]
  [[ "$output" == *"정지조건 충족"* ]]
  [ ! -f "$TEST_PROJ/.planning/loop-active" ]
}

# ── test-guard (PreToolUse: Bash) — 루프 중 테스트 삭제 차단 ───────────────────

rm_cmd() { printf '{"tool_input":{"command":"%s"}}' "$1"; }

@test "test-guard: rm -rf tests/ while generic loop active -> exit 2" {
  activate_loop_engine generic
  run invoke_hook "$TEST_GUARD" "$(rm_cmd 'rm -rf tests/')"
  [ "$status" -eq 2 ]
  [[ "$output" == *"테스트 삭제 금지"* ]]
}

@test "test-guard: rm foo.spec.ts -> exit 2" {
  activate_loop_engine generic
  run invoke_hook "$TEST_GUARD" "$(rm_cmd 'rm src/foo.spec.ts')"
  [ "$status" -eq 2 ]
}

@test "test-guard: rm latest.log -> exit 0 (no false positive)" {
  activate_loop_engine generic
  run invoke_hook "$TEST_GUARD" "$(rm_cmd 'rm latest.log')"
  [ "$status" -eq 0 ]
}

@test "test-guard: loop inactive -> exit 0 even for rm tests/" {
  run invoke_hook "$TEST_GUARD" "$(rm_cmd 'rm -rf tests/')"
  [ "$status" -eq 0 ]
}

@test "test-guard: legacy or foreign engine loop-active -> exit 0" {
  activate_loop
  run invoke_hook "$TEST_GUARD" "$(rm_cmd 'rm -rf tests/')"
  [ "$status" -eq 0 ]
  activate_loop_engine wiki
  run invoke_hook "$TEST_GUARD" "$(rm_cmd 'rm -rf tests/')"
  [ "$status" -eq 0 ]
}

@test "test-guard: jq missing -> exit 0 with notice (fail-open)" {
  activate_loop_engine generic
  run invoke_hook_without_jq "$TEST_GUARD" "$(rm_cmd 'rm -rf tests/')"
  [ "$status" -eq 0 ]
  [[ "$output" == *"jq 미설치"* ]]
}
