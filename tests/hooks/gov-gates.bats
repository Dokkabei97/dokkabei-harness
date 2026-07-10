#!/usr/bin/env bats
# =============================================================================
# gov-gates.bats — eng-gov 결정론 게이트 회귀 테스트
# 대상: plugins/eng-gov/hooks/gates/{gate-adr,gate-fitness,gate-secrets,
#       gate-supply-chain,gate-policy,gate-change-evidence,gate-threat-model,
#       gate-error-budget,run-registered}.sh
# 규약: 통과 exit 0 / 실패 exit 1 (gate-error-budget 만 "미측정" exit 2 구분).
#       위반은 stderr "[gate-X] 실패: …". 외부 도구는 <TOOL>_BIN env 로 존재/부재 주입
#       (부재: <TOOL>_BIN=/nonexistent/x, 존재: stub_tool). 날짜는 GATE_TODAY.
# 주의: @test 이름은 ASCII (macOS bash 3.2 bats 한글 테스트명 인코딩 회피).
#       한국어 설명은 주석 참조.
# =============================================================================

load 'helpers'

setup()    { make_project; mkdir -p "$TEST_PROJ/.planning/gov"; }
teardown() { cleanup_project; }

# ── 공통 fixture 헬퍼 ─────────────────────────────────────────────────────────

# syft-json 을 stdout 으로 뱉는 syft 스텁 주입 — $1 = compact SBOM JSON(단따옴표 없음)
make_syft_stub() {
  export SYFT_BIN="$(stub_tool syft "printf '%s' '$1'")"
}

# 임시 git repo + 1커밋 (HEAD 확보)
gov_git_init() {
  git -C "$TEST_PROJ" init -q
  git -C "$TEST_PROJ" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
}

# 현재 HEAD 기준 evidence.json 기록 — $1 = sha 제외 JSON(헬퍼가 .sha 주입)
write_evidence() {
  local sha dir
  sha="$(git -C "$TEST_PROJ" rev-parse HEAD)"
  dir="$TEST_PROJ/.planning/gov/change/$sha"
  mkdir -p "$dir"
  jq --arg s "$sha" '.sha=$s' <<<"$1" > "$dir/evidence.json"
}

# gates.json 기록 — $1 = JSON 문자열 그대로
write_gov_gates() {
  printf '%s\n' "$1" > "$TEST_PROJ/.planning/gov/gates.json"
}

# ── gate-adr ─────────────────────────────────────────────────────────────────

# 정상 — 파일명 규약·번호 유일·status enum·supersede 링크 실재
@test "gate-adr: valid ADRs -> exit 0" {
  mkdir -p "$TEST_PROJ/docs/decisions"
  printf '# 0001. First\nstatus: accepted\n' > "$TEST_PROJ/docs/decisions/0001-first.md"
  printf '# 0002. Second\nstatus: superseded\nsuperseded-by: 0001\n' > "$TEST_PROJ/docs/decisions/0002-second.md"
  run invoke_gate "$GOV_GATES/gate-adr.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"통과"* ]]
}

# docs/decisions 부재 — gov-init 안내
@test "gate-adr: missing docs/decisions -> exit 1" {
  run invoke_gate "$GOV_GATES/gate-adr.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"gov-init"* ]]
}

# ADR 번호 중복 — sort|uniq -d 적발
@test "gate-adr: duplicate ADR number -> exit 1" {
  mkdir -p "$TEST_PROJ/docs/decisions"
  printf 'status: accepted\n' > "$TEST_PROJ/docs/decisions/0001-a.md"
  printf 'status: accepted\n' > "$TEST_PROJ/docs/decisions/0001-b.md"
  run invoke_gate "$GOV_GATES/gate-adr.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"중복된 ADR 번호"* ]]
}

# 깨진 supersede 링크 — 대상 미실재
@test "gate-adr: broken supersede link -> exit 1" {
  mkdir -p "$TEST_PROJ/docs/decisions"
  printf 'status: accepted\n' > "$TEST_PROJ/docs/decisions/0001-a.md"
  printf 'status: superseded\nsuperseded-by: 9999\n' > "$TEST_PROJ/docs/decisions/0002-b.md"
  run invoke_gate "$GOV_GATES/gate-adr.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"superseded-by"* ]]
}

# status 필드 누락
@test "gate-adr: missing status field -> exit 1" {
  mkdir -p "$TEST_PROJ/docs/decisions"
  printf '# no status here\n' > "$TEST_PROJ/docs/decisions/0001-a.md"
  run invoke_gate "$GOV_GATES/gate-adr.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"status"* ]]
}

# 파일명 규약 위반 (^NNNN- 아님)
@test "gate-adr: bad filename convention -> exit 1" {
  mkdir -p "$TEST_PROJ/docs/decisions"
  printf 'status: accepted\n' > "$TEST_PROJ/docs/decisions/intro.md"
  run invoke_gate "$GOV_GATES/gate-adr.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"파일명 규약 위반"* ]]
}

# ── gate-fitness ─────────────────────────────────────────────────────────────

# 설정 0건 — 공허 통과
@test "gate-fitness: no config -> void pass exit 0" {
  run invoke_gate "$GOV_GATES/gate-fitness.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"검사 대상 없음"* ]]
}

# dependency-cruiser 설정 + 스텁 exit 0 전파
@test "gate-fitness: dep-cruiser config + green stub -> exit 0" {
  : > "$TEST_PROJ/.dependency-cruiser.js"
  export DEPCRUISE_BIN="$(stub_tool depcruise 'exit 0')"
  run invoke_gate "$GOV_GATES/gate-fitness.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"통과"* ]]
}

# dependency-cruiser 설정 + 스텁 exit 1 전파 (위반)
@test "gate-fitness: dep-cruiser config + failing stub -> exit 1" {
  : > "$TEST_PROJ/.dependency-cruiser.js"
  export DEPCRUISE_BIN="$(stub_tool depcruise 'exit 1')"
  run invoke_gate "$GOV_GATES/gate-fitness.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"dependency-cruiser"* ]]
}

# 설정 있고 도구 부재 — fail-closed
@test "gate-fitness: config present but tool absent -> exit 1" {
  : > "$TEST_PROJ/.dependency-cruiser.js"
  export DEPCRUISE_BIN=/nonexistent/depcruise
  run invoke_gate "$GOV_GATES/gate-fitness.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"미설치"* ]]
}

# import-linter 설정 + 스텁 exit 1 전파
@test "gate-fitness: import-linter config + failing stub -> exit 1" {
  : > "$TEST_PROJ/.importlinter"
  export LINT_IMPORTS_BIN="$(stub_tool lint-imports 'exit 1')"
  run invoke_gate "$GOV_GATES/gate-fitness.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"import-linter"* ]]
}

# ── gate-secrets ─────────────────────────────────────────────────────────────

# 도구 부재 — fail-closed 설치 안내
@test "gate-secrets: gitleaks absent -> exit 1" {
  export GITLEAKS_BIN=/nonexistent/gitleaks
  run invoke_gate "$GOV_GATES/gate-secrets.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"미설치"* ]]
}

# 스텁 exit 0 — 시크릿 없음 통과
@test "gate-secrets: clean stub -> exit 0" {
  export GITLEAKS_BIN="$(stub_tool gitleaks 'exit 0')"
  run invoke_gate "$GOV_GATES/gate-secrets.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"통과"* ]]
}

# 스텁 exit 1 — 신규 시크릿 탐지 exit 전파
@test "gate-secrets: leak stub -> exit 1" {
  export GITLEAKS_BIN="$(stub_tool gitleaks 'exit 1')"
  run invoke_gate "$GOV_GATES/gate-secrets.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"시크릿"* ]]
}

# baseline 존재 + 스텁 exit 0 — baseline 적용 메시지
@test "gate-secrets: baseline present + clean stub -> exit 0" {
  printf '[]\n' > "$TEST_PROJ/.planning/gov/gitleaks-baseline.json"
  export GITLEAKS_BIN="$(stub_tool gitleaks 'exit 0')"
  run invoke_gate "$GOV_GATES/gate-secrets.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"baseline"* ]]
}

# ── gate-supply-chain ────────────────────────────────────────────────────────

# syft·grype 부재 — fail-closed
@test "gate-supply-chain: tools absent -> exit 1" {
  export SYFT_BIN=/nonexistent/syft
  export GRYPE_BIN=/nonexistent/grype
  run invoke_gate "$GOV_GATES/gate-supply-chain.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"미설치"* ]]
}

# 정상 — SBOM 생성 + grype 0 + 허용 라이선스
@test "gate-supply-chain: clean sbom + grype 0 + allowed license -> exit 0" {
  make_syft_stub '{"artifacts":[{"licenses":[{"value":"MIT"}]}]}'
  export GRYPE_BIN="$(stub_tool grype 'exit 0')"
  run invoke_gate "$GOV_GATES/gate-supply-chain.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"통과"* ]]
}

# grype 취약점 — exit 전파
@test "gate-supply-chain: grype high vuln -> exit 1" {
  make_syft_stub '{"artifacts":[{"licenses":[{"value":"MIT"}]}]}'
  export GRYPE_BIN="$(stub_tool grype 'exit 1')"
  run invoke_gate "$GOV_GATES/gate-supply-chain.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"grype"* ]]
}

# 금지 라이선스 — denylist 대조 실패
@test "gate-supply-chain: denied license -> exit 1" {
  make_syft_stub '{"artifacts":[{"licenses":[{"value":"GPL-3.0"}]}]}'
  export GRYPE_BIN="$(stub_tool grype 'exit 0')"
  run invoke_gate "$GOV_GATES/gate-supply-chain.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"금지 라이선스"* ]]
}

# ── gate-policy ──────────────────────────────────────────────────────────────

# 대상 0건 — 공허 통과 (도구 요구 없음)
@test "gate-policy: no targets -> void pass exit 0" {
  export CONFTEST_BIN=/nonexistent/conftest
  run invoke_gate "$GOV_GATES/gate-policy.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"검사 대상 없음"* ]]
}

# 대상 존재 + conftest 부재 — fail-closed
@test "gate-policy: target present but conftest absent -> exit 1" {
  printf 'FROM scratch\n' > "$TEST_PROJ/Dockerfile"
  export CONFTEST_BIN=/nonexistent/conftest
  run invoke_gate "$GOV_GATES/gate-policy.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"미설치"* ]]
}

# 대상 + 정책 디렉토리 + conftest 스텁 exit 0 — 통과
@test "gate-policy: target + policy dir + green conftest -> exit 0" {
  printf 'FROM scratch\n' > "$TEST_PROJ/Dockerfile"
  mkdir -p "$TEST_PROJ/.planning/gov/policy"
  export CONFTEST_BIN="$(stub_tool conftest 'exit 0')"
  run invoke_gate "$GOV_GATES/gate-policy.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"통과"* ]]
}

# 대상 + 정책 디렉토리 + conftest 스텁 exit 1 — exit 전파
@test "gate-policy: target + policy dir + failing conftest -> exit 1" {
  printf 'FROM scratch\n' > "$TEST_PROJ/Dockerfile"
  mkdir -p "$TEST_PROJ/.planning/gov/policy"
  export CONFTEST_BIN="$(stub_tool conftest 'exit 1')"
  run invoke_gate "$GOV_GATES/gate-policy.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"정책 위반"* ]]
}

# 대상 존재하나 정책 디렉토리 부재
@test "gate-policy: target present but no policy dir -> exit 1" {
  printf 'FROM scratch\n' > "$TEST_PROJ/Dockerfile"
  export CONFTEST_BIN="$(stub_tool conftest 'exit 0')"
  run invoke_gate "$GOV_GATES/gate-policy.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"정책 디렉토리"* ]] || [[ "$output" == *"policy"* ]]
}

# ── gate-change-evidence ─────────────────────────────────────────────────────

# 정상 — HEAD 매칭 + author≠approver + gates 그린
@test "gate-change-evidence: valid evidence -> exit 0" {
  gov_git_init
  write_evidence '{"branch":"main","author":"alice","approver":"bob","risk_tier":"normal","risk_reasons":[],"gates":[{"gate":"gate-adr","exit":0,"ran_at":1}]}'
  run invoke_gate "$GOV_GATES/gate-change-evidence.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"통과"* ]]
}

# author == approver — 자기 승인 금지
@test "gate-change-evidence: author equals approver -> exit 1" {
  gov_git_init
  write_evidence '{"author":"alice","approver":"alice","risk_tier":"normal","gates":[{"gate":"gate-adr","exit":0}]}'
  run invoke_gate "$GOV_GATES/gate-change-evidence.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"4-eyes"* ]]
}

# high 인데 gate-secrets/supply-chain 기록 누락
@test "gate-change-evidence: high tier missing required gate record -> exit 1" {
  gov_git_init
  write_evidence '{"author":"alice","approver":"bob","risk_tier":"high","gates":[{"gate":"gate-adr","exit":0}]}'
  run invoke_gate "$GOV_GATES/gate-change-evidence.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"high"* ]]
}

# evidence.json 부재
@test "gate-change-evidence: missing evidence.json -> exit 1" {
  gov_git_init
  run invoke_gate "$GOV_GATES/gate-change-evidence.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"evidence.json 없음"* ]]
}

# gates[] 에 exit != 0 기록 존재
@test "gate-change-evidence: recorded gate not green -> exit 1" {
  gov_git_init
  write_evidence '{"author":"alice","approver":"bob","risk_tier":"normal","gates":[{"gate":"gate-adr","exit":1}]}'
  run invoke_gate "$GOV_GATES/gate-change-evidence.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"그린"* ]]
}

# ── gate-threat-model ────────────────────────────────────────────────────────

# 정상(threagile 미설치 degraded) — 미완화 critical 0건 + 경고
@test "gate-threat-model: no unmitigated critical, threagile absent -> exit 0 with warning" {
  mkdir -p "$TEST_PROJ/.planning/gov/threat"
  printf 'threagile: model\n' > "$TEST_PROJ/.planning/gov/threat/threagile.yaml"
  printf '[{"severity":"critical","status":"mitigated"},{"severity":"high","status":"unchecked"}]\n' \
    > "$TEST_PROJ/.planning/gov/threat/risks.json"
  export THREAGILE_BIN=/nonexistent/threagile
  run invoke_gate "$GOV_GATES/gate-threat-model.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"통과"* ]]
  [[ "$output" == *"경고"* ]]
}

# 미완화 critical 존재
@test "gate-threat-model: unmitigated critical -> exit 1" {
  mkdir -p "$TEST_PROJ/.planning/gov/threat"
  printf 'threagile: model\n' > "$TEST_PROJ/.planning/gov/threat/threagile.yaml"
  printf '[{"severity":"critical","status":"unchecked"}]\n' \
    > "$TEST_PROJ/.planning/gov/threat/risks.json"
  export THREAGILE_BIN=/nonexistent/threagile
  run invoke_gate "$GOV_GATES/gate-threat-model.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"미완화 critical"* ]]
}

# threagile.yaml 부재
@test "gate-threat-model: missing threagile.yaml -> exit 1" {
  run invoke_gate "$GOV_GATES/gate-threat-model.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"gov-threat"* ]]
}

# threagile 스텁 존재 — degraded 경고 없이 기존 risks.json 판정
@test "gate-threat-model: threagile stub present -> exit 0 without degraded warning" {
  mkdir -p "$TEST_PROJ/.planning/gov/threat"
  printf 'threagile: model\n' > "$TEST_PROJ/.planning/gov/threat/threagile.yaml"
  printf '[{"severity":"critical","status":"accepted"}]\n' \
    > "$TEST_PROJ/.planning/gov/threat/risks.json"
  export THREAGILE_BIN="$(stub_tool threagile 'exit 0')"
  run invoke_gate "$GOV_GATES/gate-threat-model.sh"
  [ "$status" -eq 0 ]
  [[ "$output" != *"미설치"* ]]
}

# ── gate-error-budget (3분기) ────────────────────────────────────────────────

# 통과 — remaining >= min
@test "gate-error-budget: remaining above min -> exit 0" {
  mkdir -p "$TEST_PROJ/.planning/gov/slo"
  printf 'error_budget_min_pct: 20\n' > "$TEST_PROJ/.planning/gov/slo/thresholds.yaml"
  printf '{"error_budget_remaining_pct":50}\n' > "$TEST_PROJ/.planning/gov/slo/budget.json"
  run invoke_gate "$GOV_GATES/gate-error-budget.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"통과"* ]]
}

# 소진 — remaining < min
@test "gate-error-budget: remaining below min -> exit 1" {
  mkdir -p "$TEST_PROJ/.planning/gov/slo"
  printf 'error_budget_min_pct: 20\n' > "$TEST_PROJ/.planning/gov/slo/thresholds.yaml"
  printf '{"error_budget_remaining_pct":10}\n' > "$TEST_PROJ/.planning/gov/slo/budget.json"
  run invoke_gate "$GOV_GATES/gate-error-budget.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"소진"* ]]
}

# 미측정 — budget.json 부재 exit 2
@test "gate-error-budget: missing budget.json -> exit 2 (unmeasured)" {
  mkdir -p "$TEST_PROJ/.planning/gov/slo"
  printf 'error_budget_min_pct: 20\n' > "$TEST_PROJ/.planning/gov/slo/thresholds.yaml"
  run invoke_gate "$GOV_GATES/gate-error-budget.sh"
  [ "$status" -eq 2 ]
  [[ "$output" == *"미측정"* ]]
}

# thresholds.yaml 부재
@test "gate-error-budget: missing thresholds.yaml -> exit 1" {
  run invoke_gate "$GOV_GATES/gate-error-budget.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"gov-slo"* ]]
}

# ── run-registered ───────────────────────────────────────────────────────────

# 활성 게이트 전부 그린
@test "run-registered: all enabled green -> exit 0" {
  write_gov_gates '{"version":1,"gates":[{"id":"g1","cmd":"exit 0","enabled":true,"reason":"always"},{"id":"g2","cmd":"exit 0","enabled":true,"reason":"always"}]}'
  run invoke_gate "$GOV_GATES/run-registered.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"통과"* ]]
}

# disabled 게이트는 red 여도 무시
@test "run-registered: disabled red gate ignored -> exit 0" {
  write_gov_gates '{"version":1,"gates":[{"id":"g1","cmd":"exit 0","enabled":true,"reason":"always"},{"id":"g2","cmd":"exit 1","enabled":false,"reason":"tool missing"}]}'
  run invoke_gate "$GOV_GATES/run-registered.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"통과"* ]]
}

# 활성 게이트 하나 red — exit 1 + 해당 id 나열
@test "run-registered: one enabled red -> exit 1" {
  write_gov_gates '{"version":1,"gates":[{"id":"g1","cmd":"exit 0","enabled":true,"reason":"always"},{"id":"g2","cmd":"exit 1","enabled":true,"reason":"always"}]}'
  run invoke_gate "$GOV_GATES/run-registered.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"g2"* ]]
}

# gates.json 부재 — gov-init 안내
@test "run-registered: missing gates.json -> exit 1" {
  run invoke_gate "$GOV_GATES/run-registered.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"gov-init"* ]]
}
