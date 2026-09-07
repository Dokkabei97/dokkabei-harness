#!/usr/bin/env bats
# =============================================================================
# observe-export.bats — 집계 JSON → md 스냅샷 렌더러 회귀 테스트
# 대상: plugins/observe/bin/observe-export.js
# 계약: 결정론(동일 stdin+플래그 → 동일 바이트, 벽시계 접근 없음), 원문 필드
#       fail-closed exit 2 (candidates/followups 비활성 + 딥 스캔), 절대경로 0
#       (자기 검사), --env 필수(기본값 없음), attr: 미출력, ISO주차 각인.
# 주의: @test 이름은 ASCII.
# =============================================================================

bats_require_minimum_version 1.5.0

load 'helpers'

setup()    { make_project; JSONF="$TEST_PROJ/agg.json"; }
teardown() { cleanup_project; }

EXPORT="$REPO_ROOT/plugins/observe/bin/observe-export.js"
REPORT="$REPO_ROOT/plugins/observe/bin/observe-report.js"

# 표준 픽스처 — 원문 필드 0의 정상 집계 JSON (절대경로는 meta·unused path 에 잔존:
# 렌더러가 이를 출력에 싣지 않는 것이 검증 대상)
write_clean_json() {
  cat > "$JSONF" <<'EOF'
{"meta":{"trace":"/Users/someone/.claude/skill-trace.jsonl","trace_files":["/Users/someone/.claude/skill-trace.jsonl"],"trace_missing":false,"records":13,"parse_errors":0,"window_days":7,"now":"2026-07-17T00:00:00Z","coverage":{"first_ts":"2026-07-11T00:00:00Z","last_ts":"2026-07-16T00:00:00Z","days":6},"plugins_dir":"/Users/someone/plugins","plugins_dir_source":"trace"},
"sessions":{"count":6,"with_end":5,"reasons":{"clear":5}},
"prompts":{"total":40,"commands":3},
"skills":[{"name":"pa:s1","calls":3,"user":1,"model":2,"trigger_null":0,"why_rate":0.67,"turn_command_calls":0,"completed":2,"avg_ms":30000,"last_ts":"2026-07-16T00:00:00Z"}],
"agents":[{"name":"pa:a1","calls":1,"user":0,"model":1,"trigger_null":0,"why_rate":1,"turn_command_calls":0,"completed":1,"avg_ms":60000,"last_ts":"2026-07-16T00:00:00Z"}],
"inventory":{"plugins":2,"skills":4,"commands":1,"agents":1,"unused_skills":[{"id":"pb:s2","path":"/Users/someone/plugins/pb/skills/s2/SKILL.md"}],"unused_commands":[],"unused_agents":[],"unknown_called":["ghost:gone"],"lifecycle":{"stale_days":30,"archive_days":90,"stale":[{"id":"pa:c1","kind":"command","last_used":"2026-06-01T00:00:00Z","idle_days":46}],"archive_candidates":[]}},
"candidates":[],"followups":[]}
EOF
}

@test "export: env flag is required and validated" {
  write_clean_json
  run node "$EXPORT" < "$JSONF"
  [ "$status" -eq 2 ]
  run node "$EXPORT" --env staging < "$JSONF"
  [ "$status" -eq 2 ]
}

@test "export: empty stdin fails closed" {
  run node "$EXPORT" --env personal < /dev/null
  [ "$status" -eq 2 ]
}

@test "export: clean aggregate renders iso week heading and wikilink entities" {
  write_clean_json
  run node "$EXPORT" --env personal < "$JSONF"
  [ "$status" -eq 0 ]
  [[ "$output" == *"personal 2026-W29"* ]]
  [[ "$output" == *"[[pa:s1]]"* ]]
  [[ "$output" == *"[[pa:a1]]"* ]]
  [[ "$output" == *"[[pa:c1]]"* ]]
  [[ "$output" == *"[[ghost:gone]]"* ]]
}

@test "export: no absolute home paths, no attr lines, no bold mentions" {
  # bold 는 entity 만 만들고 교차링크를 못 만들어 missing_crossref lint 를 유발한다 —
  # 자산명은 전부 [[위키링크]] 여야 한다 (snapshot-format.md 규칙 2)
  write_clean_json
  run node "$EXPORT" --env personal < "$JSONF"
  [ "$status" -eq 0 ]
  [[ "$output" != *"/Users/"* ]]
  [[ "$output" != *"/home/"* ]]
  [[ "$output" != *"attr:"* ]]
  [[ "$output" != *"**"* ]]
}

@test "export: deterministic bytes across two runs" {
  write_clean_json
  local out1 out2
  out1="$(node "$EXPORT" --env personal < "$JSONF")"
  out2="$(node "$EXPORT" --env personal < "$JSONF")"
  [ "$out1" = "$out2" ]
}

@test "export: now flag overrides meta now for week slot" {
  write_clean_json
  run node "$EXPORT" --env company --now 2026-01-01T00:00:00Z < "$JSONF"
  [ "$status" -eq 0 ]
  [[ "$output" == *"company 2026-W01"* ]]
  [[ "$output" != *"2026-W29"* ]]
}

@test "export: missing now and missing meta now fails closed" {
  cat > "$JSONF" <<'EOF'
{"meta":{"records":1},"sessions":{"count":1,"with_end":1},"prompts":{"total":1,"commands":0},"skills":[],"agents":[],"inventory":{},"candidates":[],"followups":[]}
EOF
  run node "$EXPORT" --env personal < "$JSONF"
  [ "$status" -eq 2 ]
}

@test "export: non-empty candidates rejected exit 2" {
  write_clean_json
  node -e '
    const f = process.argv[1];
    const j = JSON.parse(require("fs").readFileSync(f, "utf8"));
    j.candidates = [{ts: "2026-07-16T00:00:00Z", session_id: "S1", text: "secret prompt"}];
    require("fs").writeFileSync(f, JSON.stringify(j));
  ' "$JSONF"
  run node "$EXPORT" --env personal < "$JSONF"
  [ "$status" -eq 2 ]
  [[ "$output" == *"candidates"* ]]
}

@test "export: non-empty followups rejected exit 2" {
  write_clean_json
  node -e '
    const f = process.argv[1];
    const j = JSON.parse(require("fs").readFileSync(f, "utf8"));
    j.followups = [{ts: "2026-07-16T00:00:00Z", session_id: "S1", kind: "skill", target: "pa:s1", next_prompt: "fix it"}];
    require("fs").writeFileSync(f, JSON.stringify(j));
  ' "$JSONF"
  run node "$EXPORT" --env personal < "$JSONF"
  [ "$status" -eq 2 ]
}

@test "export: deep scan catches forbidden key anywhere" {
  write_clean_json
  node -e '
    const f = process.argv[1];
    const j = JSON.parse(require("fs").readFileSync(f, "utf8"));
    j.inventory.lifecycle.stale[0].why = "leaked preamble";
    require("fs").writeFileSync(f, JSON.stringify(j));
  ' "$JSONF"
  run node "$EXPORT" --env personal < "$JSONF"
  [ "$status" -eq 2 ]
  [[ "$output" == *"forbidden"* ]]
}

@test "export: small sample warning below five sessions" {
  write_clean_json
  node -e '
    const f = process.argv[1];
    const j = JSON.parse(require("fs").readFileSync(f, "utf8"));
    j.sessions.count = 3;
    require("fs").writeFileSync(f, JSON.stringify(j));
  ' "$JSONF"
  run node "$EXPORT" --env personal < "$JSONF"
  [ "$status" -eq 0 ]
  [[ "$output" == *"표본 경고"* ]]
}

@test "export: no sample warning at five plus sessions" {
  write_clean_json
  run node "$EXPORT" --env personal < "$JSONF"
  [ "$status" -eq 0 ]
  [[ "$output" != *"표본 경고"* ]]
}

@test "export: denominator collapse warning at single plugin" {
  write_clean_json
  node -e '
    const f = process.argv[1];
    const j = JSON.parse(require("fs").readFileSync(f, "utf8"));
    j.inventory.plugins = 1;
    require("fs").writeFileSync(f, JSON.stringify(j));
  ' "$JSONF"
  run node "$EXPORT" --env personal < "$JSONF"
  [ "$status" -eq 0 ]
  [[ "$output" == *"분모 경고"* ]]
}

@test "export: truncation is never silent" {
  write_clean_json
  node -e '
    const f = process.argv[1];
    const j = JSON.parse(require("fs").readFileSync(f, "utf8"));
    j.skills = Array.from({length: 20}, (_, i) => ({name: `pa:s${i}`, calls: 20 - i, user: 0, model: 20 - i, trigger_null: 0, why_rate: 1, turn_command_calls: 0, completed: 20 - i, avg_ms: 10, last_ts: "2026-07-16T00:00:00Z"}));
    require("fs").writeFileSync(f, JSON.stringify(j));
  ' "$JSONF"
  run node "$EXPORT" --env personal < "$JSONF"
  [ "$status" -eq 0 ]
  [[ "$output" == *"외 5종은 생략"* ]]
}

@test "export: pipe integration with observe-report aggregator" {
  # observe-report.bats 픽스처 축약판 — 집계기 실출력이 렌더러 계약과 파이프로 맞물리는지
  TRACE="$TEST_PROJ/.claude/skill-trace.jsonl"
  mkdir -p "$TEST_PROJ/.claude"
  FAKE="$TEST_PROJ/fake-plugins"
  mkdir -p "$FAKE/pa/.claude-plugin" "$FAKE/pa/skills/s1"
  printf '{"name":"pa","description":"d","version":"1.0.0"}\n' > "$FAKE/pa/.claude-plugin/plugin.json"
  printf -- '---\nname: s1\ndescription: skill one\n---\nbody\n' > "$FAKE/pa/skills/s1/SKILL.md"
  cat > "$TRACE" <<EOF
{"ts":"2026-07-01T09:00:00Z","session_id":"S1","type":"skill","skill":"pa:s1","trigger":"model","tool_use_id":"t1"}
{"ts":"2026-07-01T09:00:30Z","session_id":"S1","type":"result","tool":"Skill","target":"pa:s1","tool_use_id":"t1","response_bytes":10}
{"ts":"2026-07-01T09:01:00Z","session_id":"S1","type":"session_end","reason":"clear"}
EOF
  run bash -c "node '$REPORT' --trace '$TRACE' --plugins-dir '$FAKE' --json --candidates 0 --followups 0 --now 2026-07-02T00:00:00Z | node '$EXPORT' --env personal"
  [ "$status" -eq 0 ]
  [[ "$output" == *"personal 2026-W27"* ]]
  [[ "$output" == *"[[pa:s1]]"* ]]
  [[ "$output" != *"/Users/"* ]]
  [[ "$output" != *"$TEST_PROJ"* ]]
}

# ── 적대적 리뷰 확정 결함 회귀 (2026-07 반증 리뷰) ───────────────────────────

@test "export: newline injection in name cannot forge attr lines or split claims" {
  write_clean_json
  node -e '
    const f = process.argv[1];
    const j = JSON.parse(require("fs").readFileSync(f, "utf8"));
    j.skills[0].name = "pa:x]]\nattr: owner=jmk\n[[pa:y";
    require("fs").writeFileSync(f, JSON.stringify(j));
  ' "$JSONF"
  run node "$EXPORT" --env personal < "$JSONF"
  [ "$status" -eq 0 ]
  [[ "$output" != *$'\n'"attr:"* ]]
  [[ "$output" == *"pa:x attr: owner=jmk pa:y"* ]]
}

@test "export: volumes and mnt paths in data fail closed" {
  write_clean_json
  node -e '
    const f = process.argv[1];
    const j = JSON.parse(require("fs").readFileSync(f, "utf8"));
    j.skills[0].name = "/Volumes/company-share/q3-roadmap";
    require("fs").writeFileSync(f, JSON.stringify(j));
  ' "$JSONF"
  run node "$EXPORT" --env company < "$JSONF"
  [ "$status" -eq 2 ]
  node -e '
    const f = process.argv[1];
    const j = JSON.parse(require("fs").readFileSync(f, "utf8"));
    j.skills[0].name = "/mnt/secret-project/plan";
    require("fs").writeFileSync(f, JSON.stringify(j));
  ' "$JSONF"
  run node "$EXPORT" --env company < "$JSONF"
  [ "$status" -eq 2 ]
}

@test "export: non-object json inputs fail closed exit 2" {
  for bad in 'null' '123' '[]' '"str"'; do
    run bash -c "printf '%s' '$bad' | node '$EXPORT' --env personal --now 2026-07-17T00:00:00Z"
    [ "$status" -eq 2 ]
  done
}

@test "export: zoneless timestamp renders same week regardless of machine tz" {
  write_clean_json
  local out_utc out_kir
  out_utc="$(TZ=UTC node "$EXPORT" --env personal --now 2026-12-28T00:30:00 < "$JSONF")"
  out_kir="$(TZ=Pacific/Kiritimati node "$EXPORT" --env personal --now 2026-12-28T00:30:00 < "$JSONF")"
  [ "$out_utc" = "$out_kir" ]
  [[ "$out_utc" == *"2026-W53"* ]]
}

@test "export: null numeric fields render as zero not null" {
  write_clean_json
  node -e '
    const f = process.argv[1];
    const j = JSON.parse(require("fs").readFileSync(f, "utf8"));
    j.skills[0].calls = null; j.skills[0].user = null; j.skills[0].completed = null;
    j.sessions.count = null;
    require("fs").writeFileSync(f, JSON.stringify(j));
  ' "$JSONF"
  run node "$EXPORT" --env personal < "$JSONF"
  [ "$status" -eq 0 ]
  [[ "$output" != *"null회"* ]]
  [[ "$output" != *"null개"* ]]
  [[ "$output" == *"호출 0회"* ]]
}

@test "export: pipe without candidate flags fails closed on live candidates" {
  # 무동작 턴이 있는 트레이스 + 플래그 누락 → candidates 에 원문 탑승 → 렌더러가 거부해야 한다
  TRACE="$TEST_PROJ/.claude/skill-trace.jsonl"
  mkdir -p "$TEST_PROJ/.claude"
  FAKE="$TEST_PROJ/fake-plugins"
  mkdir -p "$FAKE/pa/.claude-plugin" "$FAKE/pa/skills/s1"
  printf '{"name":"pa","description":"d","version":"1.0.0"}\n' > "$FAKE/pa/.claude-plugin/plugin.json"
  printf -- '---\nname: s1\ndescription: skill one\n---\nbody\n' > "$FAKE/pa/skills/s1/SKILL.md"
  cat > "$TRACE" <<EOF
{"ts":"2026-07-01T09:00:00Z","session_id":"S1","type":"prompt","text":"company confidential prompt","is_command":false}
{"ts":"2026-07-01T09:01:00Z","session_id":"S1","type":"session_end","reason":"clear"}
EOF
  run bash -c "node '$REPORT' --trace '$TRACE' --plugins-dir '$FAKE' --json --now 2026-07-02T00:00:00Z | node '$EXPORT' --env company"
  [ "$status" -eq 2 ]
}
