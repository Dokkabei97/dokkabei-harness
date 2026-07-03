#!/usr/bin/env bats
# =============================================================================
# workflow-snapshot.bats — workflow 플러그인 HANDOFF 자동 스냅샷 훅 회귀 테스트
# 대상: plugins/workflow/hooks/session-snapshot.sh (PreCompact/SessionEnd 공용)
# 검증 축: 소유권 가드(loop-active) / git repo 가드 / 마커 섹션 생성·갱신
#          (마커 밖 수동 작성 내용 보존) / git 명령 실패 내성 (항상 exit 0)
# 규약: helpers.bash 는 수정하지 않는다 — git fixture 는 본 파일 로컬 함수로 정의.
# 주의: @test 이름은 ASCII 로 유지한다 — macOS 기본 bash 3.2 에서 bats 의
#       테스트명 인코딩이 한글(멀티바이트)을 깨뜨려 "unknown test name" 이 된다.
#       한국어 설명은 각 테스트의 주석으로 제공한다.
# =============================================================================

load 'helpers'

setup()    { make_project; }
teardown() { cleanup_project; }

SNAPSHOT_HOOK="$REPO_ROOT/plugins/workflow/hooks/session-snapshot.sh"
BEGIN_MARK='<!-- auto-snapshot -->'
END_MARK='<!-- /auto-snapshot -->'

# ── 로컬 fixture (helpers.bash 무수정 규약) ──────────────────────────────────

# 임시 프로젝트를 git repo 로 초기화 + 최초 커밋 1개 (identity 는 -c 로 주입)
init_git_repo() {
  git -C "$TEST_PROJ" init -q
  git -C "$TEST_PROJ" -c user.email=hook@test -c user.name=hook-test \
    commit -q --allow-empty -m "init: snapshot test fixture"
}

# 수동 작성 HANDOFF.md 생성 — 마커 없는 순수 수동 문서
write_manual_handoff() {
  { printf '# HANDOFF - 수동 작성\n'
    printf 'MANUAL-TOP 수동 상단 내용\n'; } > "$TEST_PROJ/HANDOFF.md"
}

# 마커 섹션이 이미 있는 HANDOFF.md 생성 — 위/아래에 수동 내용, 사이에 구 스냅샷
write_handoff_with_marker() {
  { printf '# HANDOFF - 수동 작성\n'
    printf 'MANUAL-TOP 수동 상단 내용\n'
    printf '\n'
    printf '%s\n' "$BEGIN_MARK"
    printf 'OLD-SNAP-CONTENT 구 스냅샷 내용\n'
    printf '%s\n' "$END_MARK"
    printf '\n'
    printf 'MANUAL-BOTTOM 수동 하단 내용\n'; } > "$TEST_PROJ/HANDOFF.md"
}

# 마커 정확 라인(-xF) 개수 계수 — $1 마커 문자열
count_marker() {
  grep -cxF "$1" "$TEST_PROJ/HANDOFF.md"
}

# ── 안전핀 (무동작 경로) ─────────────────────────────────────────────────────

# (1) git repo 가 아닌 디렉토리 — exit 0 + 무출력 + HANDOFF.md 미생성
@test "snapshot: non-git dir -> exit 0, no output, no HANDOFF.md" {
  run invoke_hook "$SNAPSHOT_HOOK"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -f "$TEST_PROJ/HANDOFF.md" ]
}

# (2) loop-active 존재 — 루프 세션은 mvp/floop 앵커 소관: exit 0 + 기존 파일 무접촉
@test "snapshot: loop-active present -> exit 0, HANDOFF.md untouched" {
  init_git_repo
  activate_loop
  write_manual_handoff
  local before; before="$(cat "$TEST_PROJ/HANDOFF.md")"
  run invoke_hook "$SNAPSHOT_HOOK"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$(cat "$TEST_PROJ/HANDOFF.md")" = "$before" ]
  ! grep -qxF "$BEGIN_MARK" "$TEST_PROJ/HANDOFF.md"
}

# ── 마커 섹션 생성 ───────────────────────────────────────────────────────────

# (3) HANDOFF.md 부재 — 마커 섹션만으로 생성 (첫 줄 = 시작 마커, 끝 줄 = 종료 마커)
@test "snapshot: no HANDOFF.md -> created with marker section only" {
  init_git_repo
  run invoke_hook "$SNAPSHOT_HOOK"
  [ "$status" -eq 0 ]
  [ -f "$TEST_PROJ/HANDOFF.md" ]
  [ "$(head -n 1 "$TEST_PROJ/HANDOFF.md")" = "$BEGIN_MARK" ]
  [ "$(tail -n 1 "$TEST_PROJ/HANDOFF.md")" = "$END_MARK" ]
  grep -q "기록 시각" "$TEST_PROJ/HANDOFF.md"
  grep -q "최근 커밋" "$TEST_PROJ/HANDOFF.md"
}

# (4) 마커 없는 수동 HANDOFF.md — 말미에 섹션 추가, 수동 내용은 그대로 (앞자리 유지)
@test "snapshot: manual HANDOFF.md without marker -> section appended, manual kept" {
  init_git_repo
  write_manual_handoff
  run invoke_hook "$SNAPSHOT_HOOK"
  [ "$status" -eq 0 ]
  [ "$(head -n 1 "$TEST_PROJ/HANDOFF.md")" = "# HANDOFF - 수동 작성" ]
  grep -qF "MANUAL-TOP 수동 상단 내용" "$TEST_PROJ/HANDOFF.md"
  [ "$(count_marker "$BEGIN_MARK")" -eq 1 ]
  [ "$(count_marker "$END_MARK")" -eq 1 ]
  # 수동 내용이 마커 섹션보다 앞에 있어야 한다
  local manual_line begin_line
  manual_line="$(grep -nF 'MANUAL-TOP' "$TEST_PROJ/HANDOFF.md" | cut -d: -f1)"
  begin_line="$(grep -nxF "$BEGIN_MARK" "$TEST_PROJ/HANDOFF.md" | cut -d: -f1)"
  [ "$manual_line" -lt "$begin_line" ]
}

# ── 마커 섹션 갱신 (수동 내용 보존) ──────────────────────────────────────────

# (5) 마커 쌍 존재 — 섹션만 교체: 구 스냅샷 제거, 마커 밖 위/아래 수동 내용 보존
@test "snapshot: existing marker section -> replaced in place, outside text preserved" {
  init_git_repo
  write_handoff_with_marker
  run invoke_hook "$SNAPSHOT_HOOK"
  [ "$status" -eq 0 ]
  grep -qF "MANUAL-TOP 수동 상단 내용" "$TEST_PROJ/HANDOFF.md"
  grep -qF "MANUAL-BOTTOM 수동 하단 내용" "$TEST_PROJ/HANDOFF.md"
  ! grep -qF "OLD-SNAP-CONTENT" "$TEST_PROJ/HANDOFF.md"
  grep -q "기록 시각" "$TEST_PROJ/HANDOFF.md"
  [ "$(count_marker "$BEGIN_MARK")" -eq 1 ]
  [ "$(count_marker "$END_MARK")" -eq 1 ]
  # 위치 불변: 상단 수동 → 마커 섹션 → 하단 수동 순서 유지
  local top begin end bottom
  top="$(grep -nF 'MANUAL-TOP' "$TEST_PROJ/HANDOFF.md" | cut -d: -f1)"
  begin="$(grep -nxF "$BEGIN_MARK" "$TEST_PROJ/HANDOFF.md" | cut -d: -f1)"
  end="$(grep -nxF "$END_MARK" "$TEST_PROJ/HANDOFF.md" | cut -d: -f1)"
  bottom="$(grep -nF 'MANUAL-BOTTOM' "$TEST_PROJ/HANDOFF.md" | cut -d: -f1)"
  [ "$top" -lt "$begin" ] && [ "$begin" -lt "$end" ] && [ "$end" -lt "$bottom" ]
}

# (6) 재실행 멱등성 — 두 번 실행해도 마커 쌍은 1개 (섹션 증식 금지)
@test "snapshot: run twice -> still exactly one marker pair" {
  init_git_repo
  run invoke_hook "$SNAPSHOT_HOOK"
  [ "$status" -eq 0 ]
  run invoke_hook "$SNAPSHOT_HOOK"
  [ "$status" -eq 0 ]
  [ "$(count_marker "$BEGIN_MARK")" -eq 1 ]
  [ "$(count_marker "$END_MARK")" -eq 1 ]
}

# ── 스냅샷 내용 ──────────────────────────────────────────────────────────────

# (7) 미완 마커 계수 — .planning/prd.json 의 passes:false 개수를 기록 (helpers 재사용)
@test "snapshot: passes:false in prd.json counted" {
  init_git_repo
  write_prd S-01=false S-02=true S-03=false
  run invoke_hook "$SNAPSHOT_HOOK"
  [ "$status" -eq 0 ]
  grep -qF "미완 마커(passes:false): 2건" "$TEST_PROJ/HANDOFF.md"
}

# ── 실패 내성 ────────────────────────────────────────────────────────────────

# (8) git 명령 일부 실패(커밋 없는 repo 에서 git log 실패) — exit 0 + 스냅샷은 기록
@test "snapshot: git log failure (no commits) -> exit 0, snapshot still written" {
  git -C "$TEST_PROJ" init -q   # 커밋 없음 → git log exit 128
  run invoke_hook "$SNAPSHOT_HOOK"
  [ "$status" -eq 0 ]
  [ -f "$TEST_PROJ/HANDOFF.md" ]
  grep -qF "(커밋 없음)" "$TEST_PROJ/HANDOFF.md"
  [ "$(count_marker "$BEGIN_MARK")" -eq 1 ]
}
