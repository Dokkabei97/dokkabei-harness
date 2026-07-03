#!/usr/bin/env bats
# =============================================================================
# generic-loop.bats — generic 경량 루프 엔진(Stop 훅) 회귀 테스트
# 대상: plugins/harness/hooks/generic-loop-stop-hook.sh
# 검증 축: 안전핀 / engine 스코프(공유 계약 — 레거시 무주장·타 엔진 무개입·CRLF 방어) /
#          정지조건 ①(게이트 exit code + has_failure_marker 보정) ②(promise, AND 결합) /
#          가드레일(max-iter · no-progress · 시간 상한)
# 규약: exit 0 = 종료 허용, exit 2 = 종료 차단(stderr 재주입)
# 주의: @test 이름은 ASCII 로 유지한다 — macOS 기본 bash 3.2 에서 bats 의
#       테스트명 인코딩이 한글(멀티바이트)을 깨뜨려 "unknown test name" 이 된다.
#       한국어 설명은 각 테스트의 주석으로 제공한다.
# =============================================================================

load 'helpers'

# 대상 훅 절대 경로 — helpers.bash 는 mvp/floop 계열만 정의하므로 로컬로 지정한다
GENERIC_HOOK="$REPO_ROOT/plugins/harness/hooks/generic-loop-stop-hook.sh"

setup()    { make_project; }
teardown() { cleanup_project; }

# ── 안전핀 · engine 스코프 (공유 계약 — loop-active engine 스코프) ────────────

# (a) 안전핀 — loop-active 부재 시 즉시 exit 0 (루프 미가동 세션의 종료는 방해 금지)
@test "safety-pin: no loop-active -> exit 0" {
  run invoke_hook "$GENERIC_HOOK"
  [ "$status" -eq 0 ]
}

# (b) 빈 loop-active(engine 줄 없음 = 레거시, mvp/floop 소유) — generic 훅은 무주장:
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
#      mvp/floop 훅과의 CRLF 판정 대칭성 확인
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
