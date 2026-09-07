#!/usr/bin/env bats
# =============================================================================
# feed-gate.bats — wiki-harness-feed 2차 결정론 게이트 회귀 테스트
# 대상: plugins/wiki-ops/skills/wiki-harness-feed/bin/feed-gate.sh
# 계약: 통과 exit 0 / 차단 exit 1(소견 목록 출력) / 사용법·파일 오류 exit 2.
#       패턴 = document-latest 마스킹 표(정형 비밀) + 홈 경로 준식별자($HOME 포함).
# 주의: @test 이름은 ASCII.
# =============================================================================

bats_require_minimum_version 1.5.0

load 'helpers'

setup()    { make_project; SNAP="$TEST_PROJ/snapshot.md"; }
teardown() { cleanup_project; }

GATE="$REPO_ROOT/plugins/wiki-ops/skills/wiki-harness-feed/bin/feed-gate.sh"

write_clean_snapshot() {
  cat > "$SNAP" <<'EOF'
# 하네스 건강 스냅샷 — personal 2026-W29

이 문서는 개인(personal) 환경의 2026-W29 주간 하네스 사용 집계 스냅샷이다.
[[pa:s1]] — personal 2026-W29 주간 호출 3회 (user 1 / model 2), 완주 2회, 평균 30000ms, why 표착률 67%.
EOF
}

@test "gate: usage error without argument" {
  run bash "$GATE"
  [ "$status" -eq 2 ]
}

@test "gate: missing file is exit 2" {
  run bash "$GATE" "$TEST_PROJ/nope.md"
  [ "$status" -eq 2 ]
}

@test "gate: clean snapshot passes" {
  write_clean_snapshot
  run bash "$GATE" "$SNAP"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS"* ]]
}

@test "gate: credential assignment blocked" {
  write_clean_snapshot
  echo "db_password = hunter2" >> "$SNAP"
  run bash "$GATE" "$SNAP"
  [ "$status" -eq 1 ]
  [[ "$output" == *"credential-assignment"* ]]
}

@test "gate: bearer token blocked" {
  write_clean_snapshot
  echo "Authorization: Bearer abc123.def-456" >> "$SNAP"
  run bash "$GATE" "$SNAP"
  [ "$status" -eq 1 ]
  [[ "$output" == *"bearer-token"* ]]
}

@test "gate: ssh private key blocked" {
  write_clean_snapshot
  echo "-----BEGIN RSA PRIVATE KEY-----" >> "$SNAP"
  run bash "$GATE" "$SNAP"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ssh-private-key"* ]]
}

@test "gate: private ip ranges blocked" {
  write_clean_snapshot
  echo "server at 10.0.12.7 and 172.16.0.1 and 192.168.1.1" >> "$SNAP"
  run bash "$GATE" "$SNAP"
  [ "$status" -eq 1 ]
  [[ "$output" == *"private-ip-10"* ]]
  [[ "$output" == *"private-ip-172"* ]]
  [[ "$output" == *"private-ip-192"* ]]
}

@test "gate: absolute home path blocked" {
  write_clean_snapshot
  echo "trace at /Users/someone/.claude/skill-trace.jsonl" >> "$SNAP"
  run bash "$GATE" "$SNAP"
  [ "$status" -eq 1 ]
  [[ "$output" == *"home-path"* ]]
}

@test "gate: home env literal blocked" {
  write_clean_snapshot
  printf 'log dir was %s/logs\n' "$HOME" >> "$SNAP"
  run bash "$GATE" "$SNAP"
  [ "$status" -eq 1 ]
}

@test "gate: multiple findings all reported with count" {
  write_clean_snapshot
  {
    echo "api_key: sk-live-000"
    echo "host 192.168.0.10"
  } >> "$SNAP"
  run bash "$GATE" "$SNAP"
  [ "$status" -eq 1 ]
  [[ "$output" == *"2 finding(s)"* ]]
}

# ── 적대적 리뷰 확정 결함 회귀 (2026-07 반증 리뷰) ───────────────────────────

@test "gate: massive match count exits 1 not sigpipe 141" {
  write_clean_snapshot
  local i
  for i in $(seq 1 200000); do echo "server 10.0.0.1 leaked"; done >> "$SNAP"
  run bash "$GATE" "$SNAP"
  [ "$status" -eq 1 ]
  [[ "$output" == *"finding(s)"* ]]
}

@test "gate: attr line blocked" {
  write_clean_snapshot
  echo "attr: pa:s1 | completion_rate = 0.83" >> "$SNAP"
  run bash "$GATE" "$SNAP"
  [ "$status" -eq 1 ]
  [[ "$output" == *"attr-line"* ]]
}

@test "gate: volumes and mnt paths blocked" {
  write_clean_snapshot
  echo "shared at /Volumes/company-share/q3.md and /mnt/data/x" >> "$SNAP"
  run bash "$GATE" "$SNAP"
  [ "$status" -eq 1 ]
  [[ "$output" == *"home-path"* ]]
}

@test "gate: korean prose with colons does not false positive" {
  write_clean_snapshot
  {
    echo "표본 — personal 2026-W29 기준 레코드 89건, 세션 12개(종결 8)."
    echo "계측 경계 — 헤드리스 실행의 user-slash 커맨드는 skill 레코드를 남기지 않는다."
  } >> "$SNAP"
  run bash "$GATE" "$SNAP"
  [ "$status" -eq 0 ]
}
