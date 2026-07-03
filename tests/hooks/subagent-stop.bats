#!/usr/bin/env bats
# =============================================================================
# subagent-stop.bats — verifier 결과 기록 집행(SubagentStop 훅) 회귀 테스트
# 대상: plugins/{mvp,feature-loop}/hooks/subagent-stop-verify.sh (동일 내용 공유 스크립트)
# 검증 축 (공유 계약 2):
#   안전핀 2종(loop-active 부재 / verify-round 부재·비어있음) /
#   pending+verified → 허용+정리 / pending+refuted → 허용+정리 /
#   미기록 round=1 → exit 2 재주입 / round=2 → 허용+정리(최대 2라운드) /
#   engine 스코프 가드 / blocked 카운터 자가치유(동일 pending 차단 2회 제한 →
#   초과 시 스테일 자동 정리)
# 규약: exit 0 = 종료 허용, exit 2 = 종료 차단(stderr 재주입)
# 주의: @test 이름은 ASCII 로 유지한다 — macOS 기본 bash 3.2 에서 bats 의
#       테스트명 인코딩이 한글(멀티바이트)을 깨뜨린다. 한국어 설명은 주석 참조.
# =============================================================================

load 'helpers'

setup()    { make_project; }
teardown() { cleanup_project; }

# ── 안전핀 2종 ───────────────────────────────────────────────────────────────

# (1) loop-active 부재 — 일반 세션 서브에이전트 종료는 절대 방해 금지
@test "subagent-stop safety-pin: no loop-active -> exit 0" {
  write_verify_round V-01 1
  run invoke_hook_with_args "$SUBAGENT_STOP_MVP" '{}' mvp
  [ "$status" -eq 0 ]
}

# (2) verify-round/ 부재 — 검증 디스패치 없음, 개입 없음
@test "subagent-stop safety-pin: no verify-round dir -> exit 0" {
  activate_loop_engine mvp
  run invoke_hook_with_args "$SUBAGENT_STOP_MVP" '{}' mvp
  [ "$status" -eq 0 ]
}

# (3) verify-round/ 존재하나 비어있음 — 개입 없음
@test "subagent-stop safety-pin: empty verify-round dir -> exit 0" {
  activate_loop_engine mvp
  mkdir -p "$TEST_PROJ/.planning/verify-round"
  run invoke_hook_with_args "$SUBAGENT_STOP_MVP" '{}' mvp
  [ "$status" -eq 0 ]
}

# ── 결과 기록 완료 — 허용 + pending 정리 ─────────────────────────────────────

# (4) pending + verified/{id}(반증 실패=통과) — exit 0 + verify-round/{id} 제거
@test "subagent-stop: pending + verified marker -> exit 0 + pending removed" {
  activate_loop_engine mvp
  write_verify_round V-01 1
  mark_verified V-01
  run invoke_hook_with_args "$SUBAGENT_STOP_MVP" '{}' mvp
  [ "$status" -eq 0 ]
  [ ! -f "$TEST_PROJ/.planning/verify-round/V-01" ]
}

# (5) pending + refuted/{id}(반증 성공 근거) — exit 0 + verify-round/{id} 제거
@test "subagent-stop: pending + refuted marker -> exit 0 + pending removed" {
  activate_loop_engine mvp
  write_verify_round V-01 1
  mark_refuted V-01 '재현: 입력 X 에서 기대 Y, 실제 Z'
  run invoke_hook_with_args "$SUBAGENT_STOP_MVP" '{}' mvp
  [ "$status" -eq 0 ]
  [ ! -f "$TEST_PROJ/.planning/verify-round/V-01" ]
}

# ── 미기록 pending — 라운드별 판정 ───────────────────────────────────────────

# (6) 둘 다 없음 + round=1 — exit 2 + verified/refuted 기록 지시 재주입, pending 유지
@test "subagent-stop: no marker at round=1 -> exit 2 with marker instruction" {
  activate_loop_engine mvp
  write_verify_round V-01 1
  run invoke_hook_with_args "$SUBAGENT_STOP_MVP" '{}' mvp
  [ "$status" -eq 2 ]
  [[ "$output" == *"V-01"* ]]
  [[ "$output" == *"verified/"* ]]
  [[ "$output" == *"refuted/"* ]]
  [[ "$output" == *"구체 근거"* ]]
  [ -f "$TEST_PROJ/.planning/verify-round/V-01" ]
}

# (7) 둘 다 없음 + round=2 — 최대 2라운드 규약으로 exit 0 + pending 제거
@test "subagent-stop: no marker at round=2 -> exit 0 + pending removed (max 2 rounds)" {
  activate_loop_engine mvp
  write_verify_round V-01 2
  run invoke_hook_with_args "$SUBAGENT_STOP_MVP" '{}' mvp
  [ "$status" -eq 0 ]
  [ ! -f "$TEST_PROJ/.planning/verify-round/V-01" ]
}

# (8) round 값 비정상(파싱 불가) — 1라운드로 간주해 보수적 재주입
@test "subagent-stop: unparseable round treated as round 1 -> exit 2" {
  activate_loop_engine mvp
  mkdir -p "$TEST_PROJ/.planning/verify-round"
  printf 'garbage\n' > "$TEST_PROJ/.planning/verify-round/V-01"
  run invoke_hook_with_args "$SUBAGENT_STOP_MVP" '{}' mvp
  [ "$status" -eq 2 ]
  [[ "$output" == *"V-01"* ]]
}

# (9) 혼재 — 해소된 id 는 정리하고 미기록 round=1 id 로 차단
@test "subagent-stop: resolved id cleaned while unresolved id blocks" {
  activate_loop_engine mvp
  write_verify_round V-01 1
  write_verify_round V-02 1
  mark_verified V-01
  run invoke_hook_with_args "$SUBAGENT_STOP_MVP" '{}' mvp
  [ "$status" -eq 2 ]
  [ ! -f "$TEST_PROJ/.planning/verify-round/V-01" ]
  [ -f "$TEST_PROJ/.planning/verify-round/V-02" ]
  [[ "$output" == *"V-02"* ]]
}

# ── blocked 카운터 자가치유 — 동일 pending 차단 2회 제한 ─────────────────────

# (6b) 무관 서브에이전트 종료 반복 — 1·2회째는 차단(blocked 카운터 증가),
#      3회째는 스테일로 간주해 pending 자동 정리 + exit 0 (자력 탈출 경로)
@test "subagent-stop self-heal: third block attempt -> stale cleanup + exit 0" {
  activate_loop_engine mvp
  write_verify_round V-01 1
  run invoke_hook_with_args "$SUBAGENT_STOP_MVP" '{}' mvp
  [ "$status" -eq 2 ]
  grep -q '^blocked=1$' "$TEST_PROJ/.planning/verify-round/V-01"
  run invoke_hook_with_args "$SUBAGENT_STOP_MVP" '{}' mvp
  [ "$status" -eq 2 ]
  grep -q '^blocked=2$' "$TEST_PROJ/.planning/verify-round/V-01"
  run invoke_hook_with_args "$SUBAGENT_STOP_MVP" '{}' mvp
  [ "$status" -eq 0 ]
  [[ "$output" == *"스테일 verify-round/V-01"* ]]
  [[ "$output" == *"재디스패치"* ]]
  [ ! -f "$TEST_PROJ/.planning/verify-round/V-01" ]
}

# (6c) verifier 가 2회째 종료 전에 refuted 를 남긴 경우 — 정상 해소로 허용 + 정리
#      (blocked 카운터는 마커 기록을 방해하지 않는다)
@test "subagent-stop self-heal: refuted written after first block -> exit 0 + pending removed" {
  activate_loop_engine mvp
  write_verify_round V-01 1
  run invoke_hook_with_args "$SUBAGENT_STOP_MVP" '{}' mvp
  [ "$status" -eq 2 ]
  mark_refuted V-01 '재현: 입력 X 에서 기대 Y, 실제 Z'
  run invoke_hook_with_args "$SUBAGENT_STOP_MVP" '{}' mvp
  [ "$status" -eq 0 ]
  [ ! -f "$TEST_PROJ/.planning/verify-round/V-01" ]
}

# ── engine 스코프 가드 · floop 등록분 스모크 ─────────────────────────────────

# (10) engine=floop 루프 — mvp 등록분은 개입하지 않는다 (pending 유지)
@test "subagent-stop guard: engine=floop loop -> mvp-registered copy exit 0" {
  activate_loop_engine floop
  write_verify_round V-01 1
  run invoke_hook_with_args "$SUBAGENT_STOP_MVP" '{}' mvp
  [ "$status" -eq 0 ]
  [ -f "$TEST_PROJ/.planning/verify-round/V-01" ]
}

# (11) engine 줄 없는 레거시 loop-active — 자기 것으로 간주해 집행 (기존 규약 호환)
@test "subagent-stop guard: legacy loop-active without engine line -> enforced" {
  activate_loop
  write_verify_round V-01 1
  run invoke_hook_with_args "$SUBAGENT_STOP_MVP" '{}' mvp
  [ "$status" -eq 2 ]
}

# (12) floop 등록분 — engine=floop 루프에서 동일 계약으로 집행
@test "subagent-stop floop copy: engine=floop pending without marker -> exit 2" {
  activate_loop_engine floop
  write_verify_round T-01 1
  run invoke_hook_with_args "$SUBAGENT_STOP_FLOOP" '{}' floop
  [ "$status" -eq 2 ]
  [[ "$output" == *"T-01"* ]]
}

# (13) 방어적 stdin — 비 JSON 페이로드가 와도 안전핀·판정은 파일 기반으로 동작
@test "subagent-stop: broken stdin payload does not break file-based judgment" {
  activate_loop_engine mvp
  write_verify_round V-01 1
  mark_verified V-01
  run invoke_hook_with_args "$SUBAGENT_STOP_MVP" 'not-a-json{{{' mvp
  [ "$status" -eq 0 ]
  [ ! -f "$TEST_PROJ/.planning/verify-round/V-01" ]
}
