#!/usr/bin/env bats
# =============================================================================
# mvp-loop-stop-hook.bats — MVP 루프 엔진(Stop 훅) 회귀 테스트
# 대상: plugins/mvp/hooks/mvp-loop-stop-hook.sh
# 검증 축: 안전핀 / graceful degrade / 가드레일(max-iter·시간 상한·no-progress) /
#          정지조건 ①(게이트+all-passes+verified 마커) ②ᴱ(E2E) ③(promise)
# 규약: exit 0 = 종료 허용, exit 2 = 종료 차단(stderr 재주입)
# 주의: @test 이름은 ASCII 로 유지한다 — macOS 기본 bash 3.2 에서 bats 의
#       테스트명 인코딩이 한글(멀티바이트)을 깨뜨려 "unknown test name" 이 된다.
#       한국어 설명은 각 테스트의 주석으로 제공한다.
# =============================================================================

load 'helpers'

setup()    { make_project; }
teardown() { cleanup_project; }

# ── 안전핀 · graceful degrade ────────────────────────────────────────────────

# (1) 안전핀 — loop-active 부재 시 즉시 exit 0 (루프 미가동 세션의 종료는 방해 금지)
@test "safety-pin: no loop-active -> exit 0" {
  run invoke_hook "$MVP_HOOK"
  [ "$status" -eq 0 ]
}

# (2) jq 부재 — exit 0 + 안내 stderr + loop-active 유지 (해제는 /mvp-stop 몫)
@test "no jq: exit 0 + guidance on stderr + loop-active kept" {
  activate_loop
  run invoke_hook_without_jq "$MVP_HOOK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"jq 미설치"* ]]
  [ -f "$TEST_PROJ/.planning/loop-active" ]
}

# (3) gate-cmd 부재 — 판정 불가로 exit 0 + 안내
@test "no gate-cmd: exit 0 + guidance on stderr" {
  activate_loop
  run invoke_hook "$MVP_HOOK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"게이트 명령 없음"* ]]
}

# ── engine 스코프 가드 (공유 계약 1) ─────────────────────────────────────────

# (G1) engine=floop 루프 — mvp 훅은 타 엔진 소유로 보고 무개입 exit 0 (loop-active 유지)
@test "engine guard: engine=floop loop-active -> mvp hook silent exit 0" {
  activate_loop_engine floop
  write_gate_script 'echo "1 failed"; exit 1'
  write_prd S-01=false
  run invoke_hook "$MVP_HOOK"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -f "$TEST_PROJ/.planning/loop-active" ]
}

# (G2) engine=mvp 명시 — 자기 것으로 정상 판정 (게이트 red 면 exit 2 차단)
@test "engine guard: engine=mvp loop-active -> normal judgment (gate red blocks)" {
  activate_loop_engine mvp
  write_gate_script 'echo "1 failed"; exit 1'
  write_prd S-01=false
  run invoke_hook "$MVP_HOOK"
  [ "$status" -eq 2 ]
  [[ "$output" == *"결정론 게이트 실패"* ]]
}

# (G3) engine 줄 없는 레거시 loop-active — 기존대로 자기 것으로 판정 진행
#      (가드에서 조용히 exit 0 하지 않고 gate-cmd 부재 안내까지 도달함을 확인)
@test "engine guard: legacy loop-active without engine line -> judgment proceeds" {
  activate_loop
  run invoke_hook "$MVP_HOOK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"게이트 명령 없음"* ]]
}

# ── 가드레일 ─────────────────────────────────────────────────────────────────

# (4) max-iter 도달 — exit 0 + loop-active 삭제
@test "guardrail max-iter: exit 0 + loop-active removed" {
  activate_loop
  write_gate_script 'exit 0'
  write_loop_state '{"iteration":3,"max_iter":3}'
  run invoke_hook "$MVP_HOOK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"max iterations"* ]]
  [ ! -f "$TEST_PROJ/.planning/loop-active" ]
}

# (5) 시간 상한 — started_at 을 과거로 조작(2시간 전, 상한 10분) → exit 0 + loop-active 삭제
@test "guardrail time limit: past started_at -> exit 0 + loop-active removed" {
  activate_loop
  write_gate_script 'exit 0'
  write_loop_state "{\"iteration\":1,\"started_at\":$(( $(date +%s) - 7200 )),\"max_minutes\":10}"
  run invoke_hook "$MVP_HOOK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"시간 상한 도달"* ]]
  [ ! -f "$TEST_PROJ/.planning/loop-active" ]
}

# (12) no-progress — 동일 실패 시그니처 연속 2회(1회차 exit 2 후 같은 상태로 2회차)
#      → exit 0 + BLOCKED.md 기록 + loop-active 삭제
@test "guardrail no-progress: same fail signature twice -> exit 0 + BLOCKED.md + loop-active removed" {
  activate_loop
  write_gate_script 'echo "1 failed"; exit 1'
  write_prd S-01=false
  run invoke_hook "$MVP_HOOK"
  [ "$status" -eq 2 ]
  run invoke_hook "$MVP_HOOK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no-progress 감지"* ]]
  [ -f "$TEST_PROJ/.planning/BLOCKED.md" ]
  grep -q "no-progress 차단" "$TEST_PROJ/.planning/BLOCKED.md"
  [ ! -f "$TEST_PROJ/.planning/loop-active" ]
}

# ── 정지조건 ① 게이트 판정 ───────────────────────────────────────────────────

# (6) 게이트 red(exit 1) — exit 2 + stderr 재주입 지시 + loop-state.json iteration 증가
@test "gate red(exit 1): exit 2 + reinjection message + iteration incremented" {
  activate_loop
  write_gate_script 'echo "1 failed"; exit 1'
  write_prd S-01=false
  run invoke_hook "$MVP_HOOK"
  [ "$status" -eq 2 ]
  [[ "$output" == *"작업 미완료"* ]]
  [[ "$output" == *"결정론 게이트 실패"* ]]
  [ "$(jq -r '.iteration' "$TEST_PROJ/.planning/loop-state.json")" = "1" ]
}

# (7a) 게이트 exit 0 인데 출력에 "1 failed" — 보수적 red 판정 → exit 2
@test "gate exit 0 but output '1 failed': judged red -> exit 2" {
  activate_loop
  write_gate_script 'echo "1 failed"; exit 0'
  write_prd S-01=false
  run invoke_hook "$MVP_HOOK"
  [ "$status" -eq 2 ]
  [[ "$output" == *"결정론 게이트 실패"* ]]
}

# (7b) 게이트 exit 0 + 출력이 "0 failed" 뿐 — green 판정 (has_failure_marker 오탐 방지 검증).
#      all-passes 미충족으로 차단은 되지만, 게이트 축 실패 메시지는 없어야 한다.
@test "gate exit 0 with only '0 failed' output: judged green (no false positive)" {
  activate_loop
  write_gate_script 'echo "2 passed, 0 failed"; exit 0'
  write_prd S-01=false
  run invoke_hook "$MVP_HOOK"
  [ "$status" -eq 2 ]
  [[ "$output" != *"결정론 게이트 실패"* ]]
  [[ "$output" == *"미완 스토리"* ]]
}

# ── 정지조건 ① all-passes · verified 마커 ────────────────────────────────────

# (8) 게이트 green + all-passes false — exit 2 + 미완 스토리 id 포함
@test "gate green + all-passes false: exit 2 + unpassed story ids listed" {
  activate_loop
  write_gate_script 'exit 0'
  write_prd S-01=true S-02=false
  mark_verified S-01
  run invoke_hook "$MVP_HOOK"
  [ "$status" -eq 2 ]
  [[ "$output" == *"미완 스토리: S-02"* ]]
}

# (9) all-passes true 이지만 verified 마커 부재 — exit 2 + 마커 지시
#     (prd-guard 를 Bash 리다이렉션으로 우회한 상황의 최종 방어선 검증)
@test "all-passes true but verified markers missing: exit 2 + marker instruction" {
  activate_loop
  write_gate_script 'exit 0'
  write_prd S-01=true S-02=true
  run invoke_hook "$MVP_HOOK"
  [ "$status" -eq 2 ]
  [[ "$output" == *"verified 마커 없는 passes:true 스토리"* ]]
  [[ "$output" == *"S-01"* ]]
  [[ "$output" == *"S-02"* ]]
}

# ── 정지조건 ③ promise · 정상 종료 ───────────────────────────────────────────

# (10) 마커까지 충족 + promise 부재 — exit 2 + promise 기록 지시
@test "markers satisfied but promise missing: exit 2 + promise instruction" {
  activate_loop
  write_gate_script 'exit 0'
  write_prd S-01=true
  mark_verified S-01
  run invoke_hook "$MVP_HOOK"
  [ "$status" -eq 2 ]
  [[ "$output" == *"<promise>MVP_COMPLETE</promise>"* ]]
  [[ "$output" == *"정확히 기록하라"* ]]
}

# (11) 전부 충족 — exit 0 + loop-active 삭제
@test "all stop conditions met: exit 0 + loop-active removed" {
  activate_loop
  write_gate_script 'exit 0'
  write_prd S-01=true S-02=true
  mark_verified S-01 S-02
  write_progress '작업 완료. <promise>MVP_COMPLETE</promise>'
  run invoke_hook "$MVP_HOOK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"정지조건 충족"* ]]
  [ ! -f "$TEST_PROJ/.planning/loop-active" ]
}

# ── ②ᴱ E2E 수용 게이트 ──────────────────────────────────────────────────────

# (13a) e2e-gate-cmd 존재 + all-passes 에서 E2E red — exit 2 + E2E 실패 지시
@test "e2e gate red at all-passes: exit 2 + e2e failure instruction" {
  activate_loop
  write_gate_script 'exit 0'
  write_e2e_script 'echo "e2e broken"; exit 1'
  write_prd S-01=true
  mark_verified S-01
  write_progress '<promise>MVP_COMPLETE</promise>'
  run invoke_hook "$MVP_HOOK"
  [ "$status" -eq 2 ]
  [[ "$output" == *"E2E 수용 게이트 실패"* ]]
}

# (13b) E2E green + promise — exit 0 (종료 메시지에 E2E 그린 명시)
@test "e2e gate green + promise: exit 0 with e2e note" {
  activate_loop
  write_gate_script 'exit 0'
  write_e2e_script 'exit 0'
  write_prd S-01=true
  mark_verified S-01
  write_progress '<promise>MVP_COMPLETE</promise>'
  run invoke_hook "$MVP_HOOK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"E2E 그린"* ]]
  [ ! -f "$TEST_PROJ/.planning/loop-active" ]
}

# (13c) all-passes 미도달이면 E2E 게이트는 실행되지 않는다 (루프 속도 보존)
@test "e2e gate is skipped before all-passes" {
  activate_loop
  write_gate_script 'exit 0'
  write_e2e_script 'touch e2e-ran; exit 0'
  write_prd S-01=false
  run invoke_hook "$MVP_HOOK"
  [ "$status" -eq 2 ]
  [ ! -f "$TEST_PROJ/e2e-ran" ]
}
