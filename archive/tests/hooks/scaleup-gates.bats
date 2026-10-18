#!/usr/bin/env bats
# =============================================================================
# scaleup-gates.bats — scaleup 결정론 게이트 회귀 테스트
# 대상: plugins/scaleup/hooks/gates/{gate-okr,gate-cadence,gate-headcount,
#       gate-board-deck,gate-meddpicc,gate-pipeline-hygiene}.sh
# 규약: 통과 exit 0 / 실패 exit 1. 경고(stderr "경고:")는 exit 무영향.
# 주의: @test 이름은 ASCII (macOS bash 3.2 bats 한글 인코딩 회피). 한국어 설명은 주석.
#       날짜 판정 케이스는 GATE_TODAY=2026-07-10 주입으로 결정론화.
# =============================================================================

load 'helpers'

setup()    { make_project; }
teardown() { cleanup_project; }

SU() { printf '%s' "$TEST_PROJ/.planning/scaleup"; }

# jq 부재 시뮬레이션 — PATH 를 빈 디렉토리로 바꿔 command -v jq 만 실패 (/bin/bash 절대경로).
# 게이트가 jq 검사 전에 외부 명령을 호출하지 않는지도 함께 검증한다.
run_gate_no_jq() {
  local gate="$1"; shift
  local emptybin="$TEST_PROJ/.emptybin"
  mkdir -p "$emptybin"
  CLAUDE_PROJECT_DIR="$TEST_PROJ" PATH="$emptybin" /bin/bash "$gate" "$@"
}

# ── fixture writers ──────────────────────────────────────────────────────────

write_okr() {
  mkdir -p "$(SU)/okr"
  cat > "$(SU)/okr/okr-2026Q3.json" <<'EOF'
{"quarter":"2026Q3","objectives":[{"id":"O1","title":"NRR 개선","owner":"CEO","krs":[
{"id":"O1-KR1","statement":"NRR 98%->110%","owner":"CS리드","baseline":98,"target":110,"unit":"%","due":"2026-09-30","confidence":0.7,"score":null}]}]}
EOF
}

write_checkin() {
  # $1 = date (기본 2026-07-08)
  mkdir -p "$(SU)/checkins"
  cat > "$(SU)/checkins/2026-W28.md" <<EOF
---
date: ${1:-2026-07-08}
week: 2026-W28
---
# 주간 체크인
## 스코어카드
| 지표 | 목표 | 실적 |
|------|------|------|
| NRR | 110% | 104% |
| MRR | 5억 | 4.8억 |
| 파이프라인 | 20억 | 18억 |
| 신규 로고 | 8 | 6 |
| CS티켓 | <50 | 61 |
EOF
}

write_headcount() {
  mkdir -p "$(SU)/org"
  cat > "$(SU)/org/headcount.json" <<'EOF'
{"fiscal_year":2027,"current_fte":28,"rows":[
{"role":"AE","dept":"Sales","level":"L4","start_quarter":"2027Q1","fte":2,"annual_cost":160000000,"milestone":"ARR 30억"},
{"role":"SDR","dept":"Sales","level":"L3","start_quarter":"2027Q2","fte":1,"annual_cost":60000000,"milestone":"파이프 2배"}]}
EOF
}

write_budget() {
  # $1 = personnel_total
  mkdir -p "$TEST_PROJ/.planning/enterprise"
  printf '{"personnel_total":%s}\n' "$1" > "$TEST_PROJ/.planning/enterprise/budget-2027.json"
}

write_deck() {
  # $1 = 파일명 stem (예: 2026Q2), $2 = "asks-ok" | "asks-baddate"
  mkdir -p "$(SU)/board"
  local asks
  if [ "${2:-asks-ok}" = "asks-baddate" ]; then
    asks='- 브릿지 승인 · 담당: CEO · 기한: 2026-8-31'
  else
    asks='- 시리즈 B 브릿지 승인 · 담당: CEO · 기한: 2026-08-31'
  fi
  cat > "$(SU)/board/${1}-deck.md" <<EOF
# ${1} 보드덱
## 실적 요약
내용
## KPI 스코어카드
내용
## 하이라이트·로우라이트
내용
## 재무·런웨이
내용
## 전략·OKR 진척
내용
## Asks
${asks}
EOF
}

write_meddpicc() {
  # $1 = deal id, $2 = decision_process status (기본 verified)
  mkdir -p "$(SU)/gtm/deals/$1"
  cat > "$(SU)/gtm/deals/$1/meddpicc.json" <<EOF
{"deal_id":"$1","amount":500000000,"close_date":"2026-09-30","forecast_category":"commit","elements":{
"metrics":{"status":"verified","evidence":"ROI 3.2x"},
"economic_buyer":{"status":"identified","evidence":"CFO 미팅"},
"decision_criteria":{"status":"identified","evidence":"RFP"},
"decision_process":{"status":"${2:-verified}","evidence":"단계 합의"},
"paper_process":{"status":"identified","evidence":"법무 검토"},
"identify_pain":{"status":"verified","evidence":"연 8억 손실"},
"champion":{"status":"identified","evidence":"VP Eng"},
"competition":{"status":"identified","evidence":"경쟁사 A"}}}
EOF
}

write_pipeline() {
  # $1 = last_activity (기본 2026-07-05)
  mkdir -p "$(SU)/gtm/pipeline"
  cat > "$(SU)/gtm/pipeline/2026-07-10-audit.json" <<EOF
{"audited_at":"2026-07-10","stale_max_days":30,"deals":[
{"id":"D1","stage":"negotiation","amount":500000000,"close_date":"2026-08-31","forecast_category":"commit","last_activity":"${1:-2026-07-05}"},
{"id":"D2","stage":"proposal","amount":200000000,"close_date":"2026-09-30","forecast_category":"best_case","last_activity":"2026-07-01"}]}
EOF
}

# ── gate-okr ─────────────────────────────────────────────────────────────────

@test "gate-okr: valid okr tree -> exit 0" {
  write_okr
  run invoke_gate "$SCALEUP_GATES/gate-okr.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"통과"* ]]
}

@test "gate-okr: more than 5 objectives -> exit 1" {
  mkdir -p "$(SU)/okr"
  cat > "$(SU)/okr/okr-2026Q3.json" <<'EOF'
{"quarter":"2026Q3","objectives":[
{"id":"O1","title":"a","owner":"x","krs":[{"id":"O1-KR1","statement":"s","owner":"o","baseline":1,"target":2,"unit":"%","due":"2026-09-30","score":null}]},
{"id":"O2","title":"a","owner":"x","krs":[{"id":"O2-KR1","statement":"s","owner":"o","baseline":1,"target":2,"unit":"%","due":"2026-09-30","score":null}]},
{"id":"O3","title":"a","owner":"x","krs":[{"id":"O3-KR1","statement":"s","owner":"o","baseline":1,"target":2,"unit":"%","due":"2026-09-30","score":null}]},
{"id":"O4","title":"a","owner":"x","krs":[{"id":"O4-KR1","statement":"s","owner":"o","baseline":1,"target":2,"unit":"%","due":"2026-09-30","score":null}]},
{"id":"O5","title":"a","owner":"x","krs":[{"id":"O5-KR1","statement":"s","owner":"o","baseline":1,"target":2,"unit":"%","due":"2026-09-30","score":null}]},
{"id":"O6","title":"a","owner":"x","krs":[{"id":"O6-KR1","statement":"s","owner":"o","baseline":1,"target":2,"unit":"%","due":"2026-09-30","score":null}]}]}
EOF
  run invoke_gate "$SCALEUP_GATES/gate-okr.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"objectives"* ]]
}

@test "gate-okr: duplicate id -> exit 1" {
  mkdir -p "$(SU)/okr"
  cat > "$(SU)/okr/okr-2026Q3.json" <<'EOF'
{"quarter":"2026Q3","objectives":[{"id":"O1","title":"a","owner":"x","krs":[
{"id":"O1-KR1","statement":"s","owner":"o","baseline":1,"target":2,"unit":"%","due":"2026-09-30","score":null},
{"id":"O1-KR1","statement":"s2","owner":"o","baseline":1,"target":2,"unit":"%","due":"2026-09-30","score":null}]}]}
EOF
  run invoke_gate "$SCALEUP_GATES/gate-okr.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"중복"* ]]
}

@test "gate-okr: --scored with null score -> exit 1" {
  write_okr
  run invoke_gate "$SCALEUP_GATES/gate-okr.sh" --scored
  [ "$status" -eq 1 ]
  [[ "$output" == *"score"* ]]
}

@test "gate-okr: --require-verdict non-ADOPT -> exit 1" {
  write_okr
  cat > "$(SU)/okr/verdict.json" <<'EOF'
{"items":[{"id":"O1-KR1","verdict":"REWRITE","reason":"활동형"}],"coverage":["task 위장 output 반증"],"riskiest":"x"}
EOF
  run invoke_gate "$SCALEUP_GATES/gate-okr.sh" --require-verdict
  [ "$status" -eq 1 ]
  [[ "$output" == *"ADOPT 아닌"* ]]
}

@test "gate-okr: --require-verdict all ADOPT -> exit 0" {
  write_okr
  cat > "$(SU)/okr/verdict.json" <<'EOF'
{"items":[{"id":"O1-KR1","verdict":"ADOPT","reason":"outcome형"}],"coverage":["task 위장 output 반증"],"riskiest":"x"}
EOF
  run invoke_gate "$SCALEUP_GATES/gate-okr.sh" --require-verdict
  [ "$status" -eq 0 ]
  [[ "$output" == *"통과"* ]]
}

@test "gate-okr: jq missing -> exit 1" {
  write_okr
  run run_gate_no_jq "$SCALEUP_GATES/gate-okr.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"jq 미설치"* ]]
}

# ── gate-cadence ─────────────────────────────────────────────────────────────

@test "gate-cadence: recent checkin + scorecard -> exit 0" {
  export GATE_TODAY=2026-07-10
  write_checkin
  run invoke_gate "$SCALEUP_GATES/gate-cadence.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"통과"* ]]
}

@test "gate-cadence: checkin older than 7 days -> exit 1 (GATE_TODAY)" {
  export GATE_TODAY=2026-07-20
  write_checkin 2026-07-08
  run invoke_gate "$SCALEUP_GATES/gate-cadence.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"7일 초과"* ]]
}

@test "gate-cadence: missing scorecard heading -> exit 1" {
  export GATE_TODAY=2026-07-10
  mkdir -p "$(SU)/checkins"
  cat > "$(SU)/checkins/2026-W28.md" <<'EOF'
---
date: 2026-07-08
---
# 주간 체크인
블로커 없음
EOF
  run invoke_gate "$SCALEUP_GATES/gate-cadence.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"스코어카드"* ]]
}

@test "gate-cadence: missing frontmatter date -> exit 1" {
  export GATE_TODAY=2026-07-10
  mkdir -p "$(SU)/checkins"
  printf '# 체크인\n## 스코어카드\n- x\n' > "$(SU)/checkins/2026-W28.md"
  run invoke_gate "$SCALEUP_GATES/gate-cadence.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"date"* ]]
}

# ── gate-headcount ───────────────────────────────────────────────────────────

@test "gate-headcount: valid rows, no budget -> exit 0 with warning" {
  write_headcount
  run invoke_gate "$SCALEUP_GATES/gate-headcount.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"통과"* ]]
  [[ "$output" == *"budget-*.json 부재"* ]]
}

@test "gate-headcount: fte <= 0 -> exit 1" {
  mkdir -p "$(SU)/org"
  cat > "$(SU)/org/headcount.json" <<'EOF'
{"fiscal_year":2027,"current_fte":10,"rows":[
{"role":"AE","dept":"Sales","level":"L4","start_quarter":"2027Q1","fte":0,"annual_cost":80000000,"milestone":"x"}]}
EOF
  run invoke_gate "$SCALEUP_GATES/gate-headcount.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"fte"* ]]
}

@test "gate-headcount: budget mismatch > 5 percent -> exit 1 (cross-file)" {
  write_headcount
  write_budget 300000000
  run invoke_gate "$SCALEUP_GATES/gate-headcount.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"편차 > 5%"* ]]
}

@test "gate-headcount: budget within 5 percent -> exit 0" {
  write_headcount
  write_budget 225000000
  run invoke_gate "$SCALEUP_GATES/gate-headcount.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"통과"* ]]
}

@test "gate-headcount: jq missing -> exit 1" {
  write_headcount
  run run_gate_no_jq "$SCALEUP_GATES/gate-headcount.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"jq 미설치"* ]]
}

# ── gate-board-deck ──────────────────────────────────────────────────────────

@test "gate-board-deck: valid deck -> exit 0" {
  write_deck 2026Q2 asks-ok
  run invoke_gate "$SCALEUP_GATES/gate-board-deck.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"통과"* ]]
}

@test "gate-board-deck: missing required heading -> exit 1" {
  mkdir -p "$(SU)/board"
  cat > "$(SU)/board/2026Q2-deck.md" <<'EOF'
# deck
## 실적 요약
## KPI 스코어카드
## 하이라이트·로우라이트
## 재무·런웨이
## Asks
- x · 담당: CEO · 기한: 2026-08-31
EOF
  run invoke_gate "$SCALEUP_GATES/gate-board-deck.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"필수 헤딩 누락"* ]]
  [[ "$output" == *"전략·OKR 진척"* ]]
}

@test "gate-board-deck: asks with bad date format -> exit 1" {
  write_deck 2026Q2 asks-baddate
  run invoke_gate "$SCALEUP_GATES/gate-board-deck.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Asks"* ]]
}

@test "gate-board-deck: heading diff from prior quarter -> exit 1" {
  write_deck 2026Q2 asks-ok
  # 전분기 덱에 추가 헤딩 삽입 → H2 목록 불일치
  cat > "$(SU)/board/2026Q1-deck.md" <<'EOF'
# deck
## 실적 요약
## KPI 스코어카드
## 하이라이트·로우라이트
## 재무·런웨이
## 전략·OKR 진척
## 부록
## Asks
- x · 담당: CEO · 기한: 2026-05-31
EOF
  run invoke_gate "$SCALEUP_GATES/gate-board-deck.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"구조 일관성"* ]]
}

# ── gate-meddpicc ────────────────────────────────────────────────────────────

@test "gate-meddpicc: valid deal -> exit 0" {
  export GATE_TODAY=2026-07-10
  write_meddpicc acme
  run invoke_gate "$SCALEUP_GATES/gate-meddpicc.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"통과"* ]]
}

@test "gate-meddpicc: wrong element key set -> exit 1" {
  export GATE_TODAY=2026-07-10
  mkdir -p "$(SU)/gtm/deals/acme"
  cat > "$(SU)/gtm/deals/acme/meddpicc.json" <<'EOF'
{"deal_id":"acme","amount":1,"close_date":"2026-09-30","forecast_category":"commit","elements":{
"metrics":{"status":"verified","evidence":"e"},"economic_buyer":{"status":"identified","evidence":"e"}}}
EOF
  run invoke_gate "$SCALEUP_GATES/gate-meddpicc.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"8요소"* ]]
}

@test "gate-meddpicc: more than 3 unknown -> exit 1" {
  export GATE_TODAY=2026-07-10
  mkdir -p "$(SU)/gtm/deals/acme"
  cat > "$(SU)/gtm/deals/acme/meddpicc.json" <<'EOF'
{"deal_id":"acme","amount":1,"close_date":"2026-09-30","forecast_category":"commit","elements":{
"metrics":{"status":"unknown","evidence":""},
"economic_buyer":{"status":"unknown","evidence":""},
"decision_criteria":{"status":"unknown","evidence":""},
"decision_process":{"status":"unknown","evidence":""},
"paper_process":{"status":"identified","evidence":"e"},
"identify_pain":{"status":"verified","evidence":"e"},
"champion":{"status":"identified","evidence":"e"},
"competition":{"status":"identified","evidence":"e"}}}
EOF
  run invoke_gate "$SCALEUP_GATES/gate-meddpicc.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown"* ]]
}

@test "gate-meddpicc: close_date past TODAY -> exit 1 (GATE_TODAY)" {
  export GATE_TODAY=2026-10-01
  write_meddpicc acme
  run invoke_gate "$SCALEUP_GATES/gate-meddpicc.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"close_date"* ]]
}

@test "gate-meddpicc: --require-verdict missing verdict -> exit 1" {
  export GATE_TODAY=2026-07-10
  write_meddpicc acme
  run invoke_gate "$SCALEUP_GATES/gate-meddpicc.sh" --require-verdict
  [ "$status" -eq 1 ]
  [[ "$output" == *"verdict.json 없음"* ]]
}

@test "gate-meddpicc: --require-verdict valid -> exit 0" {
  export GATE_TODAY=2026-07-10
  write_meddpicc acme
  cat > "$(SU)/gtm/deals/acme/verdict.json" <<'EOF'
{"items":[{"id":"acme","verdict":"DOWNGRADE","reason":"EB 실권 미확인"}],"coverage":["EB 실권 반증","do-nothing 경쟁"],"riskiest":"x"}
EOF
  run invoke_gate "$SCALEUP_GATES/gate-meddpicc.sh" --require-verdict
  [ "$status" -eq 0 ]
  [[ "$output" == *"통과"* ]]
}

@test "gate-meddpicc: jq missing -> exit 1" {
  export GATE_TODAY=2026-07-10
  write_meddpicc acme
  run run_gate_no_jq "$SCALEUP_GATES/gate-meddpicc.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"jq 미설치"* ]]
}

# ── gate-pipeline-hygiene ────────────────────────────────────────────────────

@test "gate-pipeline-hygiene: valid audit -> exit 0" {
  export GATE_TODAY=2026-07-10
  write_pipeline
  run invoke_gate "$SCALEUP_GATES/gate-pipeline-hygiene.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"통과"* ]]
}

@test "gate-pipeline-hygiene: stage enum violation -> exit 1" {
  export GATE_TODAY=2026-07-10
  mkdir -p "$(SU)/gtm/pipeline"
  cat > "$(SU)/gtm/pipeline/2026-07-10-audit.json" <<'EOF'
{"audited_at":"2026-07-10","stale_max_days":30,"deals":[
{"id":"D1","stage":"demo","amount":500000000,"close_date":"2026-08-31","forecast_category":"commit","last_activity":"2026-07-05"}]}
EOF
  run invoke_gate "$SCALEUP_GATES/gate-pipeline-hygiene.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"stage enum 위반"* ]]
}

@test "gate-pipeline-hygiene: open deal past close_date -> exit 1 (GATE_TODAY)" {
  export GATE_TODAY=2026-09-01
  mkdir -p "$(SU)/gtm/pipeline"
  cat > "$(SU)/gtm/pipeline/2026-07-10-audit.json" <<'EOF'
{"audited_at":"2026-07-10","stale_max_days":30,"deals":[
{"id":"D1","stage":"negotiation","amount":500000000,"close_date":"2026-08-31","forecast_category":"commit","last_activity":"2026-08-25"}]}
EOF
  run invoke_gate "$SCALEUP_GATES/gate-pipeline-hygiene.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"close_date < TODAY"* ]]
}

@test "gate-pipeline-hygiene: stale open deal -> exit 1" {
  export GATE_TODAY=2026-07-10
  write_pipeline 2026-05-01
  run invoke_gate "$SCALEUP_GATES/gate-pipeline-hygiene.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"stale_max_days"* ]]
  [[ "$output" == *"D1"* ]]
}

@test "gate-pipeline-hygiene: jq missing -> exit 1" {
  export GATE_TODAY=2026-07-10
  write_pipeline
  run run_gate_no_jq "$SCALEUP_GATES/gate-pipeline-hygiene.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"jq 미설치"* ]]
}
