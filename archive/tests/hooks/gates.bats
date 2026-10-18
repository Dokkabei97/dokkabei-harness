#!/usr/bin/env bats
# =============================================================================
# gates.bats — 결정론 게이트 스크립트 회귀 테스트 (2차 범위)
# 대상: plugins/mvp/hooks/gates/{gate-prd,gate-design,gate-eval,gate-scaffold}.sh
#       plugins/feature-loop/hooks/gates/gate-tasks.sh
# 규약: 통과 exit 0 / 실패 exit 1 (gate-eval 만 "미측정" exit 2 구분)
# 주의: @test 이름은 ASCII — macOS 기본 bash 3.2 의 bats 한글 테스트명 인코딩
#       문제 회피. 한국어 설명은 주석 참조.
# =============================================================================

load 'helpers'

setup()    { make_project; }
teardown() { cleanup_project; }

# prd.md fixture — gate-prd 필수 헤딩 전부 포함 (prd-authoring 스킬 §2 표준 헤딩)
write_prd_md() {
  cat > "$TEST_PROJ/.planning/prd.md" <<'EOF'
# PRD
## 문제 정의
내용
## 페르소나
내용
## 범위
### In
내용
### Out
내용
## 유저 스토리
내용
## 성공 지표
내용
EOF
}

# ── gate-prd ────────────────────────────────────────────────────────────────

# 정상 — 필수 헤딩 + 스키마 + 스토리 수 3 + --initial(전건 false)
@test "gate-prd: valid prd.md/prd.json with --initial -> exit 0" {
  write_prd_md
  write_prd S-01=false S-02=false S-03=false
  run bash -c 'CLAUDE_PROJECT_DIR="$1" bash "$2" --initial' _ "$TEST_PROJ" "$GATE_PRD"
  [ "$status" -eq 0 ]
  [[ "$output" == *"통과"* ]]
}

# 필수 헤딩 누락 — 실패 항목 나열
@test "gate-prd: missing required heading -> exit 1" {
  write_prd_md
  # '## 성공 지표' 제거
  grep -v '^## 성공 지표' "$TEST_PROJ/.planning/prd.md" > "$TEST_PROJ/.planning/prd.md.tmp"
  mv "$TEST_PROJ/.planning/prd.md.tmp" "$TEST_PROJ/.planning/prd.md"
  write_prd S-01=false S-02=false S-03=false
  run invoke_hook "$GATE_PRD"
  [ "$status" -eq 1 ]
  [[ "$output" == *"필수 헤딩 누락"* ]]
  [[ "$output" == *"성공 지표"* ]]
}

# id 형식 위반 — ^S-[0-9]{2}$ 필수
@test "gate-prd: invalid story id format -> exit 1" {
  write_prd_md
  write_prd S-1=false S-02=false S-03=false
  run invoke_hook "$GATE_PRD"
  [ "$status" -eq 1 ]
  [[ "$output" == *"id 형식 위반"* ]]
}

# --initial 인데 passes:true 존재 — 초기 PRD 는 전건 false 필수
@test "gate-prd: --initial with passes true -> exit 1" {
  write_prd_md
  write_prd S-01=true S-02=false S-03=false
  mark_verified S-01
  run bash -c 'CLAUDE_PROJECT_DIR="$1" bash "$2" --initial' _ "$TEST_PROJ" "$GATE_PRD"
  [ "$status" -eq 1 ]
  [[ "$output" == *"--initial"* ]]
}

# 스토리 수 하한(3) 위반
@test "gate-prd: fewer than 3 stories -> exit 1" {
  write_prd_md
  write_prd S-01=false S-02=false
  run invoke_hook "$GATE_PRD"
  [ "$status" -eq 1 ]
  [[ "$output" == *"스토리 수 2"* ]]
}

# ── gate-tasks ──────────────────────────────────────────────────────────────

# 정상 — 스키마 + task 수 2
@test "gate-tasks: valid tasks.json -> exit 0" {
  write_tasks T-01=false T-02=false
  run invoke_hook "$GATE_TASKS"
  [ "$status" -eq 0 ]
  [[ "$output" == *"통과"* ]]
}

# task 수 하한(2) 위반
@test "gate-tasks: fewer than 2 tasks -> exit 1" {
  write_tasks T-01=false
  run invoke_hook "$GATE_TASKS"
  [ "$status" -eq 1 ]
  [[ "$output" == *"task 수 1"* ]]
}

# id 형식 위반 — ^T-[0-9]{2}$ 필수
@test "gate-tasks: invalid task id format -> exit 1" {
  write_tasks TASK-01=false T-02=false
  run invoke_hook "$GATE_TASKS"
  [ "$status" -eq 1 ]
  [[ "$output" == *"id 형식 위반"* ]]
}

# ── gate-design ─────────────────────────────────────────────────────────────

# 전 스토리 id 가 [story: S-xx] 태그로 매핑 — 통과
@test "gate-design: all story ids tagged in design-spec -> exit 0" {
  write_prd S-01=false S-02=false S-03=false
  printf '화면 A [story: S-01]\n화면 B [story: S-02]\n화면 C [story: S-03]\n' \
    > "$TEST_PROJ/.planning/design-spec.md"
  run invoke_hook "$GATE_DESIGN"
  [ "$status" -eq 0 ]
  [[ "$output" == *"통과"* ]]
}

# 매핑 태그 누락 — 누락 id 나열
@test "gate-design: missing story tag -> exit 1 with missing id" {
  write_prd S-01=false S-02=false S-03=false
  printf '화면 A [story: S-01]\n화면 B [story: S-02]\n' \
    > "$TEST_PROJ/.planning/design-spec.md"
  run invoke_hook "$GATE_DESIGN"
  [ "$status" -eq 1 ]
  [[ "$output" == *"매핑 태그 누락"* ]]
  [[ "$output" == *"S-03"* ]]
}

# ── gate-eval ───────────────────────────────────────────────────────────────

# report 부재 — "미측정" 구분 exit 2
@test "gate-eval: missing report -> exit 2 (unmeasured)" {
  run invoke_hook "$GATE_EVAL"
  [ "$status" -eq 2 ]
  [[ "$output" == *"미측정"* ]]
}

# value >= threshold — 통과
@test "gate-eval: value meets threshold -> exit 0" {
  mkdir -p "$TEST_PROJ/.planning/eval"
  printf '{"metric":"f1","value":0.85,"threshold":0.8,"n":50,"model":"test"}\n' \
    > "$TEST_PROJ/.planning/eval/report.json"
  run invoke_hook "$GATE_EVAL"
  [ "$status" -eq 0 ]
  [[ "$output" == *"통과"* ]]
}

# value < threshold — 실패
@test "gate-eval: value below threshold -> exit 1" {
  mkdir -p "$TEST_PROJ/.planning/eval"
  printf '{"metric":"f1","value":0.7,"threshold":0.8}\n' \
    > "$TEST_PROJ/.planning/eval/report.json"
  run invoke_hook "$GATE_EVAL"
  [ "$status" -eq 1 ]
  [[ "$output" == *"임계값"* ]]
}

# MVP_EVAL_F1_MIN env override — report 임계값보다 높은 기준으로 실패 전환
@test "gate-eval: MVP_EVAL_F1_MIN env overrides report threshold" {
  mkdir -p "$TEST_PROJ/.planning/eval"
  printf '{"metric":"f1","value":0.85,"threshold":0.8}\n' \
    > "$TEST_PROJ/.planning/eval/report.json"
  run bash -c 'CLAUDE_PROJECT_DIR="$1" MVP_EVAL_F1_MIN=0.9 bash "$2"' _ "$TEST_PROJ" "$GATE_EVAL"
  [ "$status" -eq 1 ]
  [[ "$output" == *"0.9"* ]]
}

# ── gate-scaffold ───────────────────────────────────────────────────────────

# git 클린 트리 + 초기 커밋 + .planning 필수 파일 + gate-cmd 그린 fixture
scaffold_fixture() {
  write_prd_md
  write_prd S-01=false S-02=false S-03=false
  write_gate_script 'exit 0'
  printf '설계\n' > "$TEST_PROJ/.planning/design-spec.md"
  printf '스택\n' > "$TEST_PROJ/.planning/stack-decision.md"
  printf '진행\n' > "$TEST_PROJ/.planning/progress.md"
  printf '마스터\n' > "$TEST_PROJ/.planning/mvp-test.md"
  mkdir -p "$TEST_PROJ/.planning/verified"
  # verified/ 는 빈 디렉토리 — git 추적을 위해 .gitkeep
  : > "$TEST_PROJ/.planning/verified/.gitkeep"
  git -C "$TEST_PROJ" init -q
  git -C "$TEST_PROJ" -c user.name=t -c user.email=t@t add -A
  git -C "$TEST_PROJ" -c user.name=t -c user.email=t@t commit -qm init
}

@test "gate-scaffold: clean tree + planning files + green gate-cmd -> exit 0" {
  scaffold_fixture
  run invoke_hook "$GATE_SCAFFOLD"
  [ "$status" -eq 0 ]
  [[ "$output" == *"통과"* ]]
}

@test "gate-scaffold: dirty working tree -> exit 1" {
  scaffold_fixture
  printf 'x\n' > "$TEST_PROJ/uncommitted.txt"
  run invoke_hook "$GATE_SCAFFOLD"
  [ "$status" -eq 1 ]
  [[ "$output" == *"미클린"* ]]
}
