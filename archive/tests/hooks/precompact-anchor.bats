#!/usr/bin/env bats
# =============================================================================
# precompact-anchor.bats — 루프 재개 앵커(PreCompact 훅) 회귀 테스트
# 대상: plugins/{mvp,feature-loop}/hooks/precompact-anchor.sh (동일 내용 공유 스크립트)
# 검증 축: 안전핀(loop-active 부재) / 엔진 자기 판별(prd.json vs tasks.json) /
#          engine 스코프 가드(타 엔진·타 플러그인 exit 0) / 5줄 상한 / jq 부재 degrade
# 규약: 항상 exit 0 (PreCompact exit 2 는 compaction 차단이므로 금지), 앵커는 stdout
# 주의: @test 이름은 ASCII 로 유지한다 — macOS 기본 bash 3.2 에서 bats 의
#       테스트명 인코딩이 한글(멀티바이트)을 깨뜨린다. 한국어 설명은 주석 참조.
# =============================================================================

load 'helpers'

setup()    { make_project; }
teardown() { cleanup_project; }

# mvp 루프 fixture — 마스터 md + prd.json + gate-cmd + loop-state
mvp_anchor_fixture() {
  : > "$TEST_PROJ/.planning/mvp-demo.md"
  write_prd S-01=true S-02=false
  write_gate_script 'exit 0'
  write_loop_state '{"iteration":3,"max_iter":24}'
}

# floop 루프 fixture — 마스터 md + tasks.json
floop_anchor_fixture() {
  : > "$TEST_PROJ/.planning/floop-demo.md"
  write_tasks T-01=false
  write_gate_script 'exit 0'
}

# ── 안전핀 ───────────────────────────────────────────────────────────────────

# (1) loop-active 부재 — 무출력 exit 0 (일반 세션 compaction 에 절대 개입 금지)
@test "precompact: no loop-active -> exit 0 with no output" {
  run invoke_hook_with_args "$PRECOMPACT_MVP" '{}' mvp
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# (2) loop-active 존재하나 판별 산출물(prd.json/tasks.json) 전무 — 무출력 exit 0
@test "precompact: loop-active but no artifacts -> exit 0 with no output" {
  activate_loop
  run invoke_hook_with_args "$PRECOMPACT_MVP" '{}' mvp
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ── mvp 앵커 — 5줄 이내 + 핵심 필드 ──────────────────────────────────────────

# (3) mvp fixture(레거시 loop-active, engine 줄 없음) — 앵커 5줄 이내 + 마스터 경로 +
#     passes:false 첫 id + 게이트 1행 + 반복 n/m + 규율 1줄
@test "precompact mvp: anchor within 5 lines with master path and next target" {
  activate_loop
  mvp_anchor_fixture
  run invoke_hook_with_args "$PRECOMPACT_MVP" '{"hook_event_name":"PreCompact","trigger":"auto"}' mvp
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -le 5 ]
  [[ "$output" == *"mvp-demo.md"* ]]
  [[ "$output" == *"S-02"* ]]
  [[ "$output" == *"bash gate.sh"* ]]
  [[ "$output" == *"3/24"* ]]
  [[ "$output" == *"테스트 삭제"* ]]
}

# (4) engine=mvp 명시 loop-active — 동일하게 앵커 출력
@test "precompact mvp: explicit engine=mvp line -> anchor emitted" {
  activate_loop_engine mvp
  mvp_anchor_fixture
  run invoke_hook_with_args "$PRECOMPACT_MVP" '{}' mvp
  [ "$status" -eq 0 ]
  [[ "$output" == *"[mvp-loop 재개 앵커]"* ]]
  [[ "$output" == *"mvp-demo.md"* ]]
}

# ── floop 판별 ───────────────────────────────────────────────────────────────

# (5) tasks.json 존재(prd.json 부재) — floop 엔진으로 자기 판별, floop 마스터 경로
@test "precompact floop: discriminated by tasks.json -> floop master path" {
  activate_loop
  floop_anchor_fixture
  run invoke_hook_with_args "$PRECOMPACT_FLOOP" '{}' floop
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -le 5 ]
  [[ "$output" == *"[floop-loop 재개 앵커]"* ]]
  [[ "$output" == *"floop-demo.md"* ]]
  [[ "$output" == *"T-01"* ]]
}

# (6) floop 마스터 md 부재 — tasks.json 경로로 폴백
@test "precompact floop: no master md -> falls back to tasks.json path" {
  activate_loop
  write_tasks T-01=false
  run invoke_hook_with_args "$PRECOMPACT_FLOOP" '{}' floop
  [ "$status" -eq 0 ]
  [[ "$output" == *"tasks.json"* ]]
}

# ── engine 스코프 가드 ───────────────────────────────────────────────────────

# (7) engine=floop 루프에서 mvp 쪽 등록 스크립트 — 무출력 exit 0 (중복 출력 방지)
@test "precompact guard: engine=floop loop -> mvp-registered copy silent exit 0" {
  activate_loop_engine floop
  mvp_anchor_fixture
  run invoke_hook_with_args "$PRECOMPACT_MVP" '{}' mvp
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# (8) engine=generic (harness /loop-run 소유) — 양쪽 다 무출력 exit 0
@test "precompact guard: engine=generic -> both copies silent exit 0" {
  activate_loop_engine generic
  mvp_anchor_fixture
  run invoke_hook_with_args "$PRECOMPACT_MVP" '{}' mvp
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  run invoke_hook_with_args "$PRECOMPACT_FLOOP" '{}' floop
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# (9) 레거시 loop-active + tasks.json 만 존재 — 자기 판별 floop ≠ mvp 등록분 → 무출력
@test "precompact guard: legacy floop artifacts -> mvp-registered copy silent" {
  activate_loop
  floop_anchor_fixture
  run invoke_hook_with_args "$PRECOMPACT_MVP" '{}' mvp
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ── jq 부재 graceful degrade ─────────────────────────────────────────────────

# (10) jq 부재 — 마스터 경로 1줄만 출력, exit 0
@test "precompact: no jq -> master path single line only" {
  activate_loop
  mvp_anchor_fixture
  run invoke_hook_without_jq_with_args "$PRECOMPACT_MVP" '{}' mvp
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 1 ]
  [[ "$output" == *"mvp-demo.md"* ]]
  [[ "$output" == *"jq 미설치"* ]]
}
