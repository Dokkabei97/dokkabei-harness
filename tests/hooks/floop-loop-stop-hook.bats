#!/usr/bin/env bats
# =============================================================================
# floop-loop-stop-hook.bats — 브라운필드 루프 엔진(Stop 훅) 회귀 테스트
# 대상: plugins/feature-loop/hooks/floop-loop-stop-hook.sh
# 검증 축: ②ᴿ baseline 회귀 게이트 (mvp 판과 겹치는 축은 mvp-loop-stop-hook.bats 담당)
#   - baseline 부재  : 순수 green 요구 (MVP 동작 100% 호환)
#   - baseline green : 현재 red = 신규 회귀 → 차단
#   - baseline red   : fail_count <= 기준선이면 통과, 증가·파싱 불가는 차단
# 규약: exit 0 = 종료 허용, exit 2 = 종료 차단(stderr 재주입)
# 주의: @test 이름은 ASCII 로 유지한다 — macOS 기본 bash 3.2 에서 bats 의
#       테스트명 인코딩이 한글(멀티바이트)을 깨뜨린다. 한국어 설명은 주석 참조.
# =============================================================================

load 'helpers'

setup()    { make_project; }
teardown() { cleanup_project; }

# floop 정지조건 전건 충족 fixture — 게이트 축만 남기고 나머지(all-passes·마커·promise)를
# 그린으로 고정한다. baseline 축의 통과/차단이 최종 exit code 로 그대로 드러난다.
floop_green_rest() {
  write_tasks T-01=true T-02=true
  mark_verified T-01 T-02
  write_progress '<promise>FEATURE_COMPLETE</promise>'
}

# ── engine 스코프 가드 (공유 계약 1) ─────────────────────────────────────────

# (G1) engine=mvp 루프 — floop 훅은 타 엔진 소유로 보고 무개입 exit 0 (loop-active 유지)
@test "engine guard: engine=mvp loop-active -> floop hook silent exit 0" {
  activate_loop_engine mvp
  write_gate_script 'echo "1 failed"; exit 1'
  write_tasks T-01=false
  run invoke_hook "$FLOOP_HOOK"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -f "$TEST_PROJ/.planning/loop-active" ]
}

# (G2) engine=floop 명시 — 자기 것으로 정상 판정 (게이트 red 면 exit 2 차단)
@test "engine guard: engine=floop loop-active -> normal judgment (gate red blocks)" {
  activate_loop_engine floop
  write_gate_script 'echo "1 failed"; exit 1'
  write_tasks T-01=false
  run invoke_hook "$FLOOP_HOOK"
  [ "$status" -eq 2 ]
  [[ "$output" == *"결정론 게이트 실패"* ]]
}

# (G3) engine 줄 없는 레거시 loop-active — 기존대로 자기 것으로 판정 진행
@test "engine guard: legacy loop-active without engine line -> judgment proceeds" {
  activate_loop
  run invoke_hook "$FLOOP_HOOK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"게이트 명령 없음"* ]]
}

# ── (14) baseline 부재 — MVP 동작 호환 ───────────────────────────────────────

# baseline 부재 + 게이트 red → 순수 green 요구로 차단
@test "no baseline: gate red -> exit 2 (pure green required, mvp-compatible)" {
  activate_loop
  write_gate_script 'echo "1 failed"; exit 1'
  write_tasks T-01=false
  run invoke_hook "$FLOOP_HOOK"
  [ "$status" -eq 2 ]
  [[ "$output" == *"결정론 게이트 실패"* ]]
}

# baseline 부재 + 전건 충족 → 정상 종료 (mvp 동작과 동일)
@test "no baseline: all conditions met -> exit 0 + loop-active removed" {
  activate_loop
  write_gate_script 'exit 0'
  floop_green_rest
  run invoke_hook "$FLOOP_HOOK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"정지조건 충족"* ]]
  [ ! -f "$TEST_PROJ/.planning/loop-active" ]
}

# ── (15) baseline green — 현재 red 는 신규 회귀 ──────────────────────────────

@test "baseline green + current red: blocked as regression" {
  activate_loop
  write_gate_script 'echo "1 failed"; exit 1'
  write_baseline '{"baseline_exit":0,"fail_count":0}'
  floop_green_rest
  run invoke_hook "$FLOOP_HOOK"
  [ "$status" -eq 2 ]
  [[ "$output" == *"baseline 회귀 감지"* ]]
  [[ "$output" == *"클린 기준선(green) 대비 현재 게이트 레드"* ]]
}

# ── (16) baseline red(fail_count=3) — 신규 실패 0 이면 통과 ──────────────────

# 현재 실패 3개(동수) → 회귀 0 판정으로 게이트 축 통과 → 나머지 그린이면 정상 종료
@test "baseline red(fc=3) + current 3 failed: gate axis passes -> exit 0" {
  activate_loop
  write_gate_script 'echo "3 failed"; exit 1'
  write_baseline '{"baseline_exit":1,"fail_count":3}'
  floop_green_rest
  run invoke_hook "$FLOOP_HOOK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"정지조건 충족"* ]]
  [ ! -f "$TEST_PROJ/.planning/loop-active" ]
}

# 현재 실패 4개(증가) → 신규 회귀 1개 차단
@test "baseline red(fc=3) + current 4 failed: blocked as new regression" {
  activate_loop
  write_gate_script 'echo "4 failed"; exit 1'
  write_baseline '{"baseline_exit":1,"fail_count":3}'
  floop_green_rest
  run invoke_hook "$FLOOP_HOOK"
  [ "$status" -eq 2 ]
  [[ "$output" == *"baseline 회귀 감지"* ]]
  [[ "$output" == *"신규 회귀 1개 발생"* ]]
}

# 현재 전부 green(기존 실패까지 해소) → 당연히 회귀 0, 정상 종료
@test "baseline red(fc=3) + current green: improvement passes -> exit 0" {
  activate_loop
  write_gate_script 'exit 0'
  write_baseline '{"baseline_exit":1,"fail_count":3}'
  floop_green_rest
  run invoke_hook "$FLOOP_HOOK"
  [ "$status" -eq 0 ]
  [ ! -f "$TEST_PROJ/.planning/loop-active" ]
}

# ── (17) baseline red + 현재 실패 수 파싱 불가 — 보수적 차단 ──────────────────

@test "baseline red + current fail count unparseable: conservative block" {
  activate_loop
  write_gate_script 'echo "boom: something went wrong"; exit 1'
  write_baseline '{"baseline_exit":1,"fail_count":3}'
  floop_green_rest
  run invoke_hook "$FLOOP_HOOK"
  [ "$status" -eq 2 ]
  [[ "$output" == *"파싱 불가"* ]]
  [[ "$output" == *"보수적으로 차단"* ]]
}

# ── floop 고유 문구 스모크 — promise 미기록 시 FEATURE_COMPLETE 지시 ──────────

@test "promise missing: instruction references FEATURE_COMPLETE" {
  activate_loop
  write_gate_script 'exit 0'
  write_tasks T-01=true
  mark_verified T-01
  run invoke_hook "$FLOOP_HOOK"
  [ "$status" -eq 2 ]
  [[ "$output" == *"<promise>FEATURE_COMPLETE</promise>"* ]]
}
