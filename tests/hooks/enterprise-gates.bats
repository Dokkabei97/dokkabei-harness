#!/usr/bin/env bats
# =============================================================================
# enterprise-gates.bats — enterprise 플러그인 결정론 게이트 회귀 테스트
# 대상: plugins/enterprise/hooks/gates/gate-{risk-register,control-matrix,
#       policy-suite,cert-readiness,calendar,budget,variance,screen}.sh
# 규약: 통과 exit 0 / 실패 exit 1. 게이트는 stdin 없이 인자 계약(invoke_gate).
#       날짜는 GATE_TODAY(YYYY-MM-DD) 주입으로 결정론화.
# 주의: @test 이름은 ASCII (macOS bash 3.2 bats 한글 인코딩 회피). 설명은 주석.
# 산술 케이스 필수: score≠l×i / Σweight≠1.0 / Σdept≠org±0.5% / variance 재계산 불일치.
# =============================================================================

load 'helpers'

setup()    { make_project; }
teardown() { cleanup_project; }

grc_dir() { mkdir -p "$TEST_PROJ/.planning/grc"; }
ent_dir() { mkdir -p "$TEST_PROJ/.planning/enterprise"; }

# ── risk-register fixture ─────────────────────────────────────────────────────
# R-001: l4×i5=20 critical(matrix[4][5]) + actions 有, R-002: l2×i3=6 medium
write_risk_register() {
  grc_dir
  cat > "$TEST_PROJ/.planning/grc/risk-register.json" <<'EOF'
{"appetite":"moderate","updated":"2026-07-01","risks":[
 {"id":"R-001","title":"ransomware","category":"security","likelihood":4,"impact":5,"score":20,"level":"critical","owner":"CISO","response":{"strategy":"mitigate","actions":["EDR"],"due":"2026-09-30"},"next_review":"2026-12-31"},
 {"id":"R-002","title":"fx","category":"financial","likelihood":2,"impact":3,"score":6,"level":"medium","owner":"CFO","response":{"strategy":"accept","actions":[],"due":"2026-09-30"},"next_review":"2026-12-31"}
]}
EOF
}
write_risk_verdict() {
  cat > "$TEST_PROJ/.planning/grc/verdict.json" <<'EOF'
{"items":[{"id":"R-001","verdict":"ACCEPT","reason":"ok"},{"id":"R-002","verdict":"ACCEPT","reason":"ok"}],
 "coverage":["경쟁사 사고 대비 반증","owner 실재성 확인"],"riskiest":"랜섬웨어"}
EOF
}

# ── gate-risk-register ────────────────────────────────────────────────────────

@test "gate-risk-register: valid register -> exit 0" {
  write_risk_register
  run bash -c 'CLAUDE_PROJECT_DIR="$1" GATE_TODAY=2026-07-10 bash "$2"' _ "$TEST_PROJ" "$ENTERPRISE_GATES/gate-risk-register.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"통과"* ]]
}

# score != likelihood x impact (ARITHMETIC)
@test "gate-risk-register: score != l*i -> exit 1" {
  write_risk_register
  sed 's/"score":20/"score":19/' "$TEST_PROJ/.planning/grc/risk-register.json" > "$TEST_PROJ/x" && mv "$TEST_PROJ/x" "$TEST_PROJ/.planning/grc/risk-register.json"
  run bash -c 'CLAUDE_PROJECT_DIR="$1" GATE_TODAY=2026-07-10 bash "$2"' _ "$TEST_PROJ" "$ENTERPRISE_GATES/gate-risk-register.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"score"* ]]
}

# level != 5x5 mapping
@test "gate-risk-register: level mismatch vs 5x5 matrix -> exit 1" {
  write_risk_register
  sed 's/"level":"critical"/"level":"high"/' "$TEST_PROJ/.planning/grc/risk-register.json" > "$TEST_PROJ/x" && mv "$TEST_PROJ/x" "$TEST_PROJ/.planning/grc/risk-register.json"
  run bash -c 'CLAUDE_PROJECT_DIR="$1" GATE_TODAY=2026-07-10 bash "$2"' _ "$TEST_PROJ" "$ENTERPRISE_GATES/gate-risk-register.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"5x5"* ]]
}

# critical risk with no actions -> exit 1
@test "gate-risk-register: critical with empty actions -> exit 1" {
  write_risk_register
  sed 's/"actions":\["EDR"\]/"actions":[]/' "$TEST_PROJ/.planning/grc/risk-register.json" > "$TEST_PROJ/x" && mv "$TEST_PROJ/x" "$TEST_PROJ/.planning/grc/risk-register.json"
  run bash -c 'CLAUDE_PROJECT_DIR="$1" GATE_TODAY=2026-07-10 bash "$2"' _ "$TEST_PROJ" "$ENTERPRISE_GATES/gate-risk-register.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"critical"* ]]
}

# next_review overdue -> exit 1
@test "gate-risk-register: next_review overdue -> exit 1" {
  write_risk_register
  run bash -c 'CLAUDE_PROJECT_DIR="$1" GATE_TODAY=2027-06-01 bash "$2"' _ "$TEST_PROJ" "$ENTERPRISE_GATES/gate-risk-register.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"next_review"* ]]
}

# --require-verdict with all ACCEPT + coverage -> exit 0
@test "gate-risk-register: --require-verdict all ACCEPT -> exit 0" {
  write_risk_register
  write_risk_verdict
  run bash -c 'CLAUDE_PROJECT_DIR="$1" GATE_TODAY=2026-07-10 bash "$2" --require-verdict' _ "$TEST_PROJ" "$ENTERPRISE_GATES/gate-risk-register.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"통과"* ]]
}

# --require-verdict missing verdict.json -> exit 1
@test "gate-risk-register: --require-verdict missing verdict -> exit 1" {
  write_risk_register
  run bash -c 'CLAUDE_PROJECT_DIR="$1" GATE_TODAY=2026-07-10 bash "$2" --require-verdict' _ "$TEST_PROJ" "$ENTERPRISE_GATES/gate-risk-register.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"verdict.json"* ]]
}

# --require-verdict ESCALATE (non-ACCEPT) -> exit 1
@test "gate-risk-register: --require-verdict ESCALATE -> exit 1" {
  write_risk_register
  write_risk_verdict
  sed 's/"id":"R-001","verdict":"ACCEPT"/"id":"R-001","verdict":"ESCALATE"/' "$TEST_PROJ/.planning/grc/verdict.json" > "$TEST_PROJ/x" && mv "$TEST_PROJ/x" "$TEST_PROJ/.planning/grc/verdict.json"
  run bash -c 'CLAUDE_PROJECT_DIR="$1" GATE_TODAY=2026-07-10 bash "$2" --require-verdict' _ "$TEST_PROJ" "$ENTERPRISE_GATES/gate-risk-register.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"non-ACCEPT"* ]]
}

# ── gate-control-matrix ───────────────────────────────────────────────────────

write_control_matrix() {
  grc_dir
  cat > "$TEST_PROJ/.planning/grc/control-matrix.json" <<'EOF'
{"controls":[
 {"id":"C-001","risk_ids":["R-001"],"name":"EDR","type":"preventive","line":1,"owner":"보안팀","frequency":"연","status":"planned"},
 {"id":"C-002","risk_ids":["R-001"],"name":"internal-audit","type":"detective","line":3,"owner":"감사실","frequency":"분기","status":"planned"}
]}
EOF
}

@test "gate-control-matrix: valid with register -> exit 0" {
  write_risk_register
  write_control_matrix
  run invoke_gate "$ENTERPRISE_GATES/gate-control-matrix.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"통과"* ]]
}

# critical risk with no mapped control -> exit 1
@test "gate-control-matrix: uncontrolled critical risk -> exit 1" {
  write_risk_register
  grc_dir
  cat > "$TEST_PROJ/.planning/grc/control-matrix.json" <<'EOF'
{"controls":[
 {"id":"C-001","risk_ids":["R-002"],"name":"fx-hedge","type":"preventive","line":2,"owner":"재무팀","frequency":"월","status":"planned"}
]}
EOF
  run invoke_gate "$ENTERPRISE_GATES/gate-control-matrix.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"무통제"* ]]
}

# implemented control missing evidence file -> exit 1
@test "gate-control-matrix: implemented control missing evidence -> exit 1" {
  write_risk_register
  grc_dir
  cat > "$TEST_PROJ/.planning/grc/control-matrix.json" <<'EOF'
{"controls":[
 {"id":"C-001","risk_ids":["R-001"],"name":"EDR","type":"preventive","line":1,"owner":"보안팀","frequency":"연","status":"implemented","evidence_path":"evidence/nope.md"}
]}
EOF
  run invoke_gate "$ENTERPRISE_GATES/gate-control-matrix.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"evidence_path"* ]]
}

# dangling risk_ids not in register -> exit 1
@test "gate-control-matrix: dangling risk_ids -> exit 1" {
  write_risk_register
  grc_dir
  cat > "$TEST_PROJ/.planning/grc/control-matrix.json" <<'EOF'
{"controls":[
 {"id":"C-001","risk_ids":["R-001","R-999"],"name":"EDR","type":"preventive","line":1,"owner":"보안팀","frequency":"연","status":"planned"},
 {"id":"C-002","risk_ids":["R-001"],"name":"audit","type":"detective","line":3,"owner":"감사실","frequency":"분기","status":"planned"}
]}
EOF
  run invoke_gate "$ENTERPRISE_GATES/gate-control-matrix.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"R-999"* ]]
}

# ── gate-policy-suite ─────────────────────────────────────────────────────────

write_policies() {
  mkdir -p "$TEST_PROJ/.planning/grc/policies"
  cat > "$TEST_PROJ/.planning/grc/policies/code-of-conduct.md" <<'EOF'
---
owner: 준법팀
review_date: 2027-01-01
---
# 행동강령
EOF
  cat > "$TEST_PROJ/.planning/grc/policies/whistleblowing-policy.md" <<'EOF'
---
owner: 감사실
review_date: 2027-01-01
---
# 내부신고 규정
EOF
  cat > "$TEST_PROJ/.planning/grc/policy-index.json" <<'EOF'
{"policies":["code-of-conduct.md","whistleblowing-policy.md"]}
EOF
}

@test "gate-policy-suite: valid suite -> exit 0" {
  write_policies
  run bash -c 'CLAUDE_PROJECT_DIR="$1" GATE_TODAY=2026-07-10 bash "$2"' _ "$TEST_PROJ" "$ENTERPRISE_GATES/gate-policy-suite.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"통과"* ]]
}

# review_date overdue -> exit 1
@test "gate-policy-suite: review_date overdue -> exit 1" {
  write_policies
  run bash -c 'CLAUDE_PROJECT_DIR="$1" GATE_TODAY=2027-06-01 bash "$2"' _ "$TEST_PROJ" "$ENTERPRISE_GATES/gate-policy-suite.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"review_date"* ]]
}

# missing required doc (whistleblowing) -> exit 1
@test "gate-policy-suite: missing required doc -> exit 1" {
  mkdir -p "$TEST_PROJ/.planning/grc/policies"
  cat > "$TEST_PROJ/.planning/grc/policies/code-of-conduct.md" <<'EOF'
---
owner: 준법팀
review_date: 2027-01-01
---
# 행동강령
EOF
  cat > "$TEST_PROJ/.planning/grc/policy-index.json" <<'EOF'
{"policies":["code-of-conduct.md"]}
EOF
  run bash -c 'CLAUDE_PROJECT_DIR="$1" GATE_TODAY=2026-07-10 bash "$2"' _ "$TEST_PROJ" "$ENTERPRISE_GATES/gate-policy-suite.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"whistleblowing-policy.md"* ]]
}

# index <-> file diff -> exit 1
@test "gate-policy-suite: index vs file mismatch -> exit 1" {
  write_policies
  cat > "$TEST_PROJ/.planning/grc/policies/extra.md" <<'EOF'
---
owner: 준법팀
review_date: 2027-01-01
---
# 추가정책
EOF
  run bash -c 'CLAUDE_PROJECT_DIR="$1" GATE_TODAY=2026-07-10 bash "$2"' _ "$TEST_PROJ" "$ENTERPRISE_GATES/gate-policy-suite.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"불일치"* ]]
}

# ── gate-cert-readiness ───────────────────────────────────────────────────────
# REF(101항목)에서 cert-gap 생성: core->implemented, non-core->n/a

write_cert_gap() {
  grc_dir
  local ref="$REPO_ROOT/plugins/enterprise/skills/k-grc-context/references/isms-p-items.json"
  jq '{framework:"ISMS-P",revision:"2026",items:[.items[] | {id, part, title, status:(if .core then "implemented" else "n/a" end), evidence_path:"", owner:"보안팀"}]}' \
    "$ref" > "$TEST_PROJ/.planning/grc/cert-gap.json"
}

@test "gate-cert-readiness: valid full 101-item gap -> exit 0" {
  write_cert_gap
  run invoke_gate "$ENTERPRISE_GATES/gate-cert-readiness.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"통과"* ]]
}

# incomplete id set (drop one item) -> exit 1
@test "gate-cert-readiness: incomplete id set -> exit 1" {
  write_cert_gap
  jq '.items |= .[1:]' "$TEST_PROJ/.planning/grc/cert-gap.json" > "$TEST_PROJ/x" && mv "$TEST_PROJ/x" "$TEST_PROJ/.planning/grc/cert-gap.json"
  run invoke_gate "$ENTERPRISE_GATES/gate-cert-readiness.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"101"* ]]
}

# core item planned -> exit 1
@test "gate-cert-readiness: core item planned -> exit 1" {
  write_cert_gap
  jq '(.items[] | select(.id=="1.1.1") | .status) |= "planned"' "$TEST_PROJ/.planning/grc/cert-gap.json" > "$TEST_PROJ/x" && mv "$TEST_PROJ/x" "$TEST_PROJ/.planning/grc/cert-gap.json"
  run invoke_gate "$ENTERPRISE_GATES/gate-cert-readiness.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"core"* ]]
}

# evidenced without evidence file -> exit 1
@test "gate-cert-readiness: evidenced missing evidence file -> exit 1" {
  write_cert_gap
  jq '(.items[] | select(.id=="1.1.1") | .status) |= "evidenced" | (.items[] | select(.id=="1.1.1") | .evidence_path) |= "evidence/nope.md"' \
    "$TEST_PROJ/.planning/grc/cert-gap.json" > "$TEST_PROJ/x" && mv "$TEST_PROJ/x" "$TEST_PROJ/.planning/grc/cert-gap.json"
  run invoke_gate "$ENTERPRISE_GATES/gate-cert-readiness.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"evidence_path"* ]]
}

# ── gate-calendar ─────────────────────────────────────────────────────────────

write_calendar() {
  grc_dir
  cat > "$TEST_PROJ/.planning/grc/compliance-calendar.json" <<'EOF'
{"duties":[
 {"id":"D-001","title":"사업보고서","basis":"자본시장법","due":"2026-12-31","owner":"IR","recurrence":"annual","status":"open","evidence_path":""},
 {"id":"D-002","title":"중대재해 교육","basis":"중대재해법","due":"2026-06-30","owner":"안전팀","recurrence":"quarterly","status":"done","evidence_path":"evidence/edu.pdf"}
]}
EOF
}

@test "gate-calendar: valid calendar -> exit 0" {
  write_calendar
  run bash -c 'CLAUDE_PROJECT_DIR="$1" GATE_TODAY=2026-07-10 bash "$2"' _ "$TEST_PROJ" "$ENTERPRISE_GATES/gate-calendar.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"통과"* ]]
}

# open duty overdue -> exit 1
@test "gate-calendar: overdue open duty -> exit 1" {
  write_calendar
  run bash -c 'CLAUDE_PROJECT_DIR="$1" GATE_TODAY=2027-06-01 bash "$2"' _ "$TEST_PROJ" "$ENTERPRISE_GATES/gate-calendar.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"도과"* ]]
}

# done duty missing evidence -> exit 1
@test "gate-calendar: done duty missing evidence -> exit 1" {
  write_calendar
  sed 's#"evidence_path":"evidence/edu.pdf"#"evidence_path":""#' "$TEST_PROJ/.planning/grc/compliance-calendar.json" > "$TEST_PROJ/x" && mv "$TEST_PROJ/x" "$TEST_PROJ/.planning/grc/compliance-calendar.json"
  run bash -c 'CLAUDE_PROJECT_DIR="$1" GATE_TODAY=2026-07-10 bash "$2"' _ "$TEST_PROJ" "$ENTERPRISE_GATES/gate-calendar.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"evidence_path"* ]]
}

# D-14 warning still passes (exit 0) — due within 14 days
@test "gate-calendar: D-14 warning does not fail -> exit 0" {
  grc_dir
  cat > "$TEST_PROJ/.planning/grc/compliance-calendar.json" <<'EOF'
{"duties":[
 {"id":"D-001","title":"임박의무","basis":"자본시장법","due":"2026-07-20","owner":"IR","recurrence":"annual","status":"open","evidence_path":""}
]}
EOF
  run bash -c 'CLAUDE_PROJECT_DIR="$1" GATE_TODAY=2026-07-10 bash "$2"' _ "$TEST_PROJ" "$ENTERPRISE_GATES/gate-calendar.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"D-14"* ]]
}

# ── gate-budget ───────────────────────────────────────────────────────────────

write_budget() {
  ent_dir
  cat > "$TEST_PROJ/.planning/enterprise/budget-2027.json" <<'EOF'
{"fiscal_year":2027,"org_total_krw":1000,"personnel_total_krw":600,
 "scenarios":{"base":1000,"best":1200,"worst":800},
 "clap":{"challenge":"매출2배","levers":"엔터프라이즈세일즈","allocation":"R&D40%","assumptions":"환율1300","plan":"분기QBR"},
 "departments":[{"name":"R&D","total_krw":600,"personnel_krw":400,"owner":"CTO"},{"name":"Sales","total_krw":400,"personnel_krw":200,"owner":"CRO"}],
 "assumptions":["환율1300","성장30%","이탈5%"]}
EOF
}

@test "gate-budget: valid budget -> exit 0" {
  write_budget
  run invoke_gate "$ENTERPRISE_GATES/gate-budget.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"통과"* ]]
}

# sum(dept) != org beyond 0.5% (ARITHMETIC)
@test "gate-budget: dept sum != org_total -> exit 1" {
  write_budget
  sed 's/"total_krw":400,"personnel_krw":200/"total_krw":600,"personnel_krw":200/' "$TEST_PROJ/.planning/enterprise/budget-2027.json" > "$TEST_PROJ/x" && mv "$TEST_PROJ/x" "$TEST_PROJ/.planning/enterprise/budget-2027.json"
  run invoke_gate "$ENTERPRISE_GATES/gate-budget.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"±0.5%"* ]]
}

# within 0.5% tolerance still passes
@test "gate-budget: dept sum within 0.5% -> exit 0" {
  write_budget
  sed 's/"total_krw":400,"personnel_krw":200/"total_krw":404,"personnel_krw":200/' "$TEST_PROJ/.planning/enterprise/budget-2027.json" > "$TEST_PROJ/x" && mv "$TEST_PROJ/x" "$TEST_PROJ/.planning/enterprise/budget-2027.json"
  run invoke_gate "$ENTERPRISE_GATES/gate-budget.sh"
  [ "$status" -eq 0 ]
}

# scenarios order violation -> exit 1
@test "gate-budget: scenarios worst>base -> exit 1" {
  write_budget
  sed 's/"worst":800/"worst":1100/' "$TEST_PROJ/.planning/enterprise/budget-2027.json" > "$TEST_PROJ/x" && mv "$TEST_PROJ/x" "$TEST_PROJ/.planning/enterprise/budget-2027.json"
  run invoke_gate "$ENTERPRISE_GATES/gate-budget.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"worst"* ]]
}

# clap missing a key -> exit 1
@test "gate-budget: clap missing key -> exit 1" {
  write_budget
  jq 'del(.clap.plan)' "$TEST_PROJ/.planning/enterprise/budget-2027.json" > "$TEST_PROJ/x" && mv "$TEST_PROJ/x" "$TEST_PROJ/.planning/enterprise/budget-2027.json"
  run invoke_gate "$ENTERPRISE_GATES/gate-budget.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"clap"* ]]
}

# assumptions < 3 -> exit 1
@test "gate-budget: fewer than 3 assumptions -> exit 1" {
  write_budget
  jq '.assumptions |= .[0:2]' "$TEST_PROJ/.planning/enterprise/budget-2027.json" > "$TEST_PROJ/x" && mv "$TEST_PROJ/x" "$TEST_PROJ/.planning/enterprise/budget-2027.json"
  run invoke_gate "$ENTERPRISE_GATES/gate-budget.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"assumptions"* ]]
}

# ── gate-variance ─────────────────────────────────────────────────────────────

write_variance() {
  mkdir -p "$TEST_PROJ/.planning/enterprise/variance"
  cat > "$TEST_PROJ/.planning/enterprise/variance/2026Q2.json" <<'EOF'
{"period":"2026Q2","threshold_pct":10,"lines":[
 {"item":"revenue","plan":1000,"actual":1050,"variance":50,"variance_pct":5,"derp":{"describe":"","explain":"","respond":"","prevent":""}},
 {"item":"personnel","plan":600,"actual":720,"variance":120,"variance_pct":20,"derp":{"describe":"증가","explain":"채용가속","respond":"동결","prevent":"게이트"}}
]}
EOF
}

@test "gate-variance: valid variance -> exit 0" {
  write_variance
  run invoke_gate "$ENTERPRISE_GATES/gate-variance.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"통과"* ]]
}

# variance != actual - plan (ARITHMETIC)
@test "gate-variance: variance recalculation mismatch -> exit 1" {
  write_variance
  sed 's/"variance":50/"variance":40/' "$TEST_PROJ/.planning/enterprise/variance/2026Q2.json" > "$TEST_PROJ/x" && mv "$TEST_PROJ/x" "$TEST_PROJ/.planning/enterprise/variance/2026Q2.json"
  run invoke_gate "$ENTERPRISE_GATES/gate-variance.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"재계산"* ]]
}

# threshold-exceeding line with blank DERP -> exit 1
@test "gate-variance: threshold-exceed line blank DERP -> exit 1" {
  write_variance
  jq '(.lines[] | select(.item=="personnel") | .derp.describe) |= ""' "$TEST_PROJ/.planning/enterprise/variance/2026Q2.json" > "$TEST_PROJ/x" && mv "$TEST_PROJ/x" "$TEST_PROJ/.planning/enterprise/variance/2026Q2.json"
  run invoke_gate "$ENTERPRISE_GATES/gate-variance.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"DERP"* ]]
}

# ── gate-screen ───────────────────────────────────────────────────────────────

write_screen() {
  mkdir -p "$TEST_PROJ/.planning/enterprise/screen"
  cat > "$TEST_PROJ/.planning/enterprise/screen/acme.json" <<'EOF'
{"target":"acme","categories":[
 {"name":"strategic","weight":0.3,"score":4},
 {"name":"market","weight":0.2,"score":3},
 {"name":"finance","weight":0.2,"score":3},
 {"name":"execution","weight":0.15,"score":4},
 {"name":"risk","weight":0.15,"score":2}],
 "disqualifiers":["부채비율 300% 초과"],"stop_rule":"score<2.5 중단","annual_revenue_krw":10000000000}
EOF
}
write_screen_verdict() {
  cat > "$TEST_PROJ/.planning/enterprise/screen/verdict.json" <<'EOF'
{"items":[{"id":"acme","verdict":"APPROVE","reason":"ok"}],
 "coverage":["synergy substitution 반증","stop_rule 실효성"],"riskiest":"통합비용"}
EOF
}

@test "gate-screen: valid screen -> exit 0" {
  write_screen
  run invoke_gate "$ENTERPRISE_GATES/gate-screen.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"통과"* ]]
}

# sum(weight) != 1.0 (ARITHMETIC)
@test "gate-screen: weight sum != 1.0 -> exit 1" {
  write_screen
  sed 's/"weight":0.3/"weight":0.5/' "$TEST_PROJ/.planning/enterprise/screen/acme.json" > "$TEST_PROJ/x" && mv "$TEST_PROJ/x" "$TEST_PROJ/.planning/enterprise/screen/acme.json"
  run invoke_gate "$ENTERPRISE_GATES/gate-screen.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Σweight"* ]]
}

# categories length != 5 -> exit 1
@test "gate-screen: categories length not 5 -> exit 1" {
  write_screen
  jq '.categories |= .[0:4]' "$TEST_PROJ/.planning/enterprise/screen/acme.json" > "$TEST_PROJ/x" && mv "$TEST_PROJ/x" "$TEST_PROJ/.planning/enterprise/screen/acme.json"
  run invoke_gate "$ENTERPRISE_GATES/gate-screen.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"길이"* ]]
}

# merger threshold warning still passes
@test "gate-screen: merger threshold cross warns but passes -> exit 0" {
  write_screen
  sed 's/"annual_revenue_krw":10000000000/"annual_revenue_krw":40000000000/' "$TEST_PROJ/.planning/enterprise/screen/acme.json" > "$TEST_PROJ/x" && mv "$TEST_PROJ/x" "$TEST_PROJ/.planning/enterprise/screen/acme.json"
  run invoke_gate "$ENTERPRISE_GATES/gate-screen.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"기업결합"* ]]
}

# --require-verdict APPROVE -> exit 0
@test "gate-screen: --require-verdict APPROVE -> exit 0" {
  write_screen
  write_screen_verdict
  run invoke_gate "$ENTERPRISE_GATES/gate-screen.sh" --require-verdict
  [ "$status" -eq 0 ]
  [[ "$output" == *"통과"* ]]
}

# --require-verdict REJECT (non-APPROVE) -> exit 1
@test "gate-screen: --require-verdict REJECT -> exit 1" {
  write_screen
  write_screen_verdict
  sed 's/"verdict":"APPROVE"/"verdict":"REJECT"/' "$TEST_PROJ/.planning/enterprise/screen/verdict.json" > "$TEST_PROJ/x" && mv "$TEST_PROJ/x" "$TEST_PROJ/.planning/enterprise/screen/verdict.json"
  run invoke_gate "$ENTERPRISE_GATES/gate-screen.sh" --require-verdict
  [ "$status" -eq 1 ]
  [[ "$output" == *"non-APPROVE"* ]]
}

# jq absence -> reasoned exit 1
@test "gate-budget: jq missing -> reasoned exit 1" {
  write_budget
  run bash -c 'CLAUDE_PROJECT_DIR="$1" PATH="$2" /bin/bash "$3"' _ "$TEST_PROJ" "$TEST_PROJ/.emptybin" "$ENTERPRISE_GATES/gate-budget.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"jq"* ]]
}
