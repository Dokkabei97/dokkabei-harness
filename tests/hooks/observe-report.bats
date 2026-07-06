#!/usr/bin/env bats
# =============================================================================
# observe-report.bats — skill-trace 집계기 회귀 테스트
# 대상: plugins/observe/bin/observe-report.js
# 계약: 결정론 집계 전용(LLM 판단 없음). tolerant reader(깨진 라인·미지 type 무시),
#       트레이스 부재 시에도 exit 0 + trace_missing 플래그. 인벤토리 분모는
#       --plugins-dir > 트레이스 session_start.plugin_root > 자기 위치 역산 순.
# 주의: @test 이름은 ASCII.
# =============================================================================

bats_require_minimum_version 1.5.0

load 'helpers'

setup()    { make_project; TRACE="$TEST_PROJ/.claude/skill-trace.jsonl"; mkdir -p "$TEST_PROJ/.claude"; }
teardown() { cleanup_project; }

REPORT="$REPO_ROOT/plugins/observe/bin/observe-report.js"

# 가짜 플러그인 트리 — pa(스킬 s1·커맨드 c1·에이전트 a1), pb(스킬 s2, 전부 미호출)
make_fake_plugins() {
  FAKE="$TEST_PROJ/fake-plugins"
  local p
  for p in pa pb; do
    mkdir -p "$FAKE/$p/.claude-plugin"
    printf '{"name":"%s","description":"d","version":"1.0.0"}\n' "$p" > "$FAKE/$p/.claude-plugin/plugin.json"
  done
  mkdir -p "$FAKE/pa/skills/s1" "$FAKE/pa/commands" "$FAKE/pa/agents" "$FAKE/pb/skills/s2"
  printf -- '---\nname: s1\ndescription: skill one\n---\nbody\n' > "$FAKE/pa/skills/s1/SKILL.md"
  printf -- '---\nname: c1\ndescription: command one\n---\nbody\n' > "$FAKE/pa/commands/c1.md"
  printf -- '---\nname: a1\ndescription: agent one\n---\nbody\n' > "$FAKE/pa/agents/a1.md"
  printf -- '---\nname: s2\ndescription: skill two\n---\nbody\n' > "$FAKE/pb/skills/s2/SKILL.md"
}

# 표준 픽스처 트레이스 — 세션 1개: 스킬 2회(user/model)·에이전트 1회·result join·
# 무동작 턴 1건(후보)·커맨드 턴 1건(분모 제외)·미지 type 1건·깨진 라인 1건
write_fixture_trace() {
  cat > "$TRACE" <<EOF
{"ts":"2026-07-01T09:00:00Z","session_id":"S1","type":"session_start","source":"startup","plugin_root":"$FAKE/pa"}
{"ts":"2026-07-01T09:01:00Z","session_id":"S1","type":"prompt","text":"review my query","is_command":false}
{"ts":"2026-07-01T09:01:10Z","session_id":"S1","type":"skill","skill":"pa:s1","args":"","trigger":"model","why":"fits","why_source":"preamble","tool_use_id":"t1"}
{"ts":"2026-07-01T09:01:40Z","session_id":"S1","type":"result","tool":"Skill","target":"pa:s1","tool_use_id":"t1","response_bytes":10}
{"ts":"2026-07-01T09:02:00Z","session_id":"S1","type":"prompt","text":"/c1 run it","is_command":true}
{"ts":"2026-07-01T09:02:10Z","session_id":"S1","type":"skill","skill":"pa:c1","args":"run it","trigger":"user","why":null,"why_source":null}
{"ts":"2026-07-01T09:03:00Z","session_id":"S1","type":"prompt","text":"what is the meaning of life","is_command":false}
{"ts":"2026-07-01T09:04:00Z","session_id":"S1","type":"prompt","text":"delegate the triage","is_command":false}
{"ts":"2026-07-01T09:04:10Z","session_id":"S1","type":"agent","agent":"pa:a1","description":"triage","tool_use_id":"t2"}
{"ts":"2026-07-01T09:05:10Z","session_id":"S1","type":"result","tool":"Agent","target":"pa:a1","tool_use_id":"t2","response_bytes":99}
{"ts":"2026-07-01T09:06:00Z","session_id":"S1","type":"skill","skill":"ghost:gone","args":"","trigger":"model"}
{"ts":"2026-07-01T09:07:00Z","session_id":"S1","type":"future_record_type","x":1}
broken-line{{{
{"ts":"2026-07-01T09:08:00Z","session_id":"S1","type":"session_end","reason":"clear"}
EOF
}

run_report() { # $@ 추가 옵션
  run node "$REPORT" --trace "$TRACE" --plugins-dir "$FAKE" --json "$@"
}

# JSON 출력에서 jq 스타일 경로 값 추출 (node 로 파싱 — 훅과 동일 런타임)
jget() { # $1 = JS 식 (r 이 리포트 객체)
  printf '%s' "$output" | node -e '
    let buf = ""; process.stdin.on("data", (c) => buf += c);
    process.stdin.on("end", () => {
      const r = JSON.parse(buf);
      process.stdout.write(String(eval(process.argv[1])));
    });
  ' "$1"
}

@test "report: missing trace -> exit 0, trace_missing true" {
  make_fake_plugins
  run_report
  [ "$status" -eq 0 ]
  [ "$(jget 'r.meta.trace_missing')" = "true" ]
  [ "$(jget 'r.meta.records')" = "0" ]
}

@test "report: tolerant reader counts records, skips broken lines" {
  make_fake_plugins; write_fixture_trace
  run_report
  [ "$status" -eq 0 ]
  [ "$(jget 'r.meta.records')" = "13" ]
  [ "$(jget 'r.meta.parse_errors')" = "1" ]
}

@test "report: skill aggregation with trigger split and result join" {
  make_fake_plugins; write_fixture_trace
  run_report
  local s1; s1="$(jget 'JSON.stringify(r.skills.find(s=>s.name==="pa:s1"))')"
  [[ "$s1" == *'"calls":1'* ]]
  [[ "$s1" == *'"model":1'* ]]
  [[ "$s1" == *'"completed":1'* ]]
  [[ "$s1" == *'"avg_ms":30000'* ]]
  local c1; c1="$(jget 'JSON.stringify(r.skills.find(s=>s.name==="pa:c1"))')"
  [[ "$c1" == *'"user":1'* ]]
}

@test "report: agent aggregation with duration join" {
  make_fake_plugins; write_fixture_trace
  run_report
  local a1; a1="$(jget 'JSON.stringify(r.agents.find(a=>a.name==="pa:a1"))')"
  [[ "$a1" == *'"calls":1'* ]]
  [[ "$a1" == *'"completed":1'* ]]
  [[ "$a1" == *'"avg_ms":60000'* ]]
}

@test "report: unused assets exclude called ones, unknown called listed" {
  make_fake_plugins; write_fixture_trace
  run_report
  [ "$(jget 'r.inventory.plugins')" = "2" ]
  [ "$(jget 'r.inventory.unused_skills.map(u=>u.id).join(",")')" = "pb:s2" ]
  [ "$(jget 'r.inventory.unused_commands.length')" = "0" ]
  [ "$(jget 'r.inventory.unused_agents.length')" = "0" ]
  [ "$(jget 'r.inventory.unknown_called.join(",")')" = "ghost:gone" ]
}

@test "report: no-action turn becomes candidate, command turn excluded" {
  make_fake_plugins; write_fixture_trace
  run_report
  [ "$(jget 'r.candidates.length')" = "1" ]
  [ "$(jget 'r.candidates[0].text')" = "what is the meaning of life" ]
  [ "$(jget 'r.prompts.total')" = "4" ]
  [ "$(jget 'r.prompts.commands')" = "1" ]
}

@test "report: open last turn without session_end is not a candidate" {
  make_fake_plugins
  cat > "$TRACE" <<EOF
{"ts":"2026-07-01T09:00:00Z","session_id":"S2","type":"prompt","text":"still working on this","is_command":false}
EOF
  run_report
  [ "$status" -eq 0 ]
  [ "$(jget 'r.candidates.length')" = "0" ]
}

@test "report: sessions summary with end reason" {
  make_fake_plugins; write_fixture_trace
  run_report
  [ "$(jget 'r.sessions.count')" = "1" ]
  [ "$(jget 'r.sessions.with_end')" = "1" ]
  [ "$(jget 'r.sessions.reasons.clear')" = "1" ]
}

@test "report: plugins-dir derived from trace session_start plugin_root" {
  make_fake_plugins; write_fixture_trace
  run node "$REPORT" --trace "$TRACE" --json
  [ "$status" -eq 0 ]
  [ "$(jget 'r.meta.plugins_dir_source')" = "trace" ]
  [ "$(jget 'r.meta.plugins_dir')" = "$FAKE" ]
}

@test "report: window filter drops old records" {
  make_fake_plugins; write_fixture_trace
  run_report --window 1
  [ "$status" -eq 0 ]
  [ "$(jget 'r.meta.records')" = "0" ]
}

@test "report: rotated .1 file merged before main" {
  make_fake_plugins
  printf '%s\n' '{"ts":"2026-07-01T09:00:00Z","session_id":"S1","type":"skill","skill":"pa:s1","trigger":"model"}' > "$TRACE.1"
  printf '%s\n' '{"ts":"2026-07-01T09:01:00Z","session_id":"S1","type":"skill","skill":"pa:s1","trigger":"user"}' > "$TRACE"
  run_report
  [ "$(jget 'r.meta.records')" = "2" ]
  [ "$(jget 'r.skills[0].calls')" = "2" ]
}

@test "report: text mode prints korean summary headers" {
  make_fake_plugins; write_fixture_trace
  run node "$REPORT" --trace "$TRACE" --plugins-dir "$FAKE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"observe"* ]]
  [[ "$output" == *"13"* ]]
}

# ── 리뷰 확정 결함 회귀 (2026-07 반증 리뷰) ──────────────────────────────────

@test "report: prompt-only command usage credits unused_commands" {
  make_fake_plugins
  cat > "$TRACE" <<EOF
{"ts":"2026-07-01T09:00:00Z","session_id":"S1","type":"prompt","text":"/c1 release it","is_command":true}
{"ts":"2026-07-01T09:05:00Z","session_id":"S1","type":"session_end","reason":"clear"}
EOF
  run_report
  [ "$status" -eq 0 ]
  [ "$(jget 'r.inventory.unused_commands.length')" = "0" ]
}

@test "report: namespaced call does not credit same-name asset in other plugin" {
  make_fake_plugins
  # pa 에도 s2 동명 스킬을 만들어 tail 충돌 구성
  mkdir -p "$FAKE/pa/skills/s2"
  printf -- '---\nname: s2\ndescription: dup name\n---\nbody\n' > "$FAKE/pa/skills/s2/SKILL.md"
  cat > "$TRACE" <<EOF
{"ts":"2026-07-01T09:00:00Z","session_id":"S1","type":"skill","skill":"pa:s2","trigger":"model"}
EOF
  run_report
  [ "$status" -eq 0 ]
  [ "$(jget 'r.inventory.unused_skills.map(u=>u.id).sort().join(",")')" = "pa:s1,pb:s2" ]
  [ "$(jget 'r.inventory.unknown_called.length')" = "0" ]
}

@test "report: bare call still credits by tail, namespaced unknown not hidden by tail" {
  make_fake_plugins
  cat > "$TRACE" <<EOF
{"ts":"2026-07-01T09:00:00Z","session_id":"S1","type":"skill","skill":"s2","trigger":"model"}
{"ts":"2026-07-01T09:01:00Z","session_id":"S1","type":"skill","skill":"other:s1","trigger":"model"}
EOF
  run_report
  [ "$status" -eq 0 ]
  local unused; unused="$(jget 'r.inventory.unused_skills.map(u=>u.id).sort().join(",")')"
  [ "$unused" = "pa:s1" ]
  [ "$(jget 'r.inventory.unknown_called.join(",")')" = "other:s1" ]
}

@test "report: result join falls back to session+target when tool_use_id absent" {
  make_fake_plugins
  cat > "$TRACE" <<EOF
{"ts":"2026-07-01T09:00:00Z","session_id":"S1","type":"skill","skill":"pa:s1","trigger":"model"}
{"ts":"2026-07-01T09:00:20Z","session_id":"S1","type":"result","tool":"Skill","target":"pa:s1"}
EOF
  run_report
  [ "$(jget 'r.skills[0].completed')" = "1" ]
  [ "$(jget 'r.skills[0].avg_ms')" = "20000" ]
}

@test "report: candidates cap enforced, zero returns none" {
  make_fake_plugins
  {
    local i
    for i in 1 2 3; do
      printf '{"ts":"2026-07-01T09:0%s:00Z","session_id":"S1","type":"prompt","text":"idle turn %s","is_command":false}\n' "$i" "$i"
    done
    printf '%s\n' '{"ts":"2026-07-01T09:09:00Z","session_id":"S1","type":"session_end","reason":"clear"}'
  } > "$TRACE"
  run_report --candidates 2
  [ "$(jget 'r.candidates.length')" = "2" ]
  [ "$(jget 'r.candidates[0].text')" = "idle turn 3" ]
  run_report --candidates 0
  [ "$(jget 'r.candidates.length')" = "0" ]
}

@test "report: pending isolation across interleaved sessions" {
  make_fake_plugins
  cat > "$TRACE" <<EOF
{"ts":"2026-07-01T09:00:00Z","session_id":"S1","type":"prompt","text":"s1 idle question","is_command":false}
{"ts":"2026-07-01T09:00:10Z","session_id":"S2","type":"prompt","text":"s2 active question","is_command":false}
{"ts":"2026-07-01T09:00:20Z","session_id":"S2","type":"skill","skill":"pa:s1","trigger":"model"}
{"ts":"2026-07-01T09:01:00Z","session_id":"S1","type":"session_end","reason":"clear"}
{"ts":"2026-07-01T09:02:00Z","session_id":"S2","type":"session_end","reason":"clear"}
EOF
  run_report
  [ "$(jget 'r.candidates.length')" = "1" ]
  [ "$(jget 'r.candidates[0].text')" = "s1 idle question" ]
}

@test "report: null json line tolerated as parse error, no crash" {
  make_fake_plugins
  cat > "$TRACE" <<EOF
null
{"ts":"2026-07-01T09:00:00Z","session_id":"S1","type":"skill","skill":"pa:s1","trigger":"model"}
EOF
  run_report --window 30000
  [ "$status" -eq 0 ]
  [ "$(jget 'r.meta.parse_errors')" = "1" ]
  [ "$(jget 'r.meta.records')" = "1" ]
}

@test "report: plugin_root derived from full trace even when windowed out" {
  make_fake_plugins
  cat > "$TRACE" <<EOF
{"ts":"2020-01-01T09:00:00Z","session_id":"S0","type":"session_start","source":"startup","plugin_root":"$FAKE/pa"}
{"ts":"2026-07-01T09:00:00Z","session_id":"S1","type":"skill","skill":"pa:s1","trigger":"model"}
EOF
  run node "$REPORT" --trace "$TRACE" --json --window 30000
  [ "$status" -eq 0 ]
  [ "$(jget 'r.meta.plugins_dir_source')" = "trace" ]
  [ "$(jget 'r.meta.plugins_dir')" = "$FAKE" ]
}

@test "report: self fallback when no flag and no plugin_root in trace" {
  make_fake_plugins
  printf '%s\n' '{"ts":"2026-07-01T09:00:00Z","session_id":"S1","type":"skill","skill":"pa:s1","trigger":"model"}' > "$TRACE"
  run node "$REPORT" --trace "$TRACE" --json
  [ "$status" -eq 0 ]
  [ "$(jget 'r.meta.plugins_dir_source')" = "self" ]
  [ "$(jget 'r.meta.plugins_dir')" = "$REPO_ROOT/plugins" ]
}

@test "report: version-indirect cache layout climbs to marketplace root" {
  # 설치 캐시 레이아웃 cache/<마켓플레이스>/<플러그인>/<버전>/ 재현 —
  # plugin_root 가 버전 디렉토리를 가리켜도 분모는 마켓플레이스 전체여야 한다 (분모 붕괴 회귀)
  MP="$TEST_PROJ/mp"
  mkdir -p "$MP/pluginA/1.0.0/.claude-plugin" "$MP/pluginA/1.0.0/skills/x" "$MP/pluginA/1.0.0/commands"
  printf '{"name":"pluginA","description":"d","version":"1.0.0"}\n' > "$MP/pluginA/1.0.0/.claude-plugin/plugin.json"
  printf -- '---\nname: x\ndescription: skill x\n---\nbody\n' > "$MP/pluginA/1.0.0/skills/x/SKILL.md"
  printf -- '---\nname: y\ndescription: command y\n---\nbody\n' > "$MP/pluginA/1.0.0/commands/y.md"
  # 구버전 잔존 디렉토리 — 최신(1.0.0)만 분모로 선택돼야 한다 (이중 계상 금지)
  mkdir -p "$MP/pluginA/0.9.0/.claude-plugin" "$MP/pluginA/0.9.0/skills/old"
  printf '{"name":"pluginA","description":"d","version":"0.9.0"}\n' > "$MP/pluginA/0.9.0/.claude-plugin/plugin.json"
  printf -- '---\nname: old\ndescription: old skill\n---\nbody\n' > "$MP/pluginA/0.9.0/skills/old/SKILL.md"
  # 두 번째 플러그인 — plugin_root 소유자 외 플러그인도 열거되는지 확인
  mkdir -p "$MP/pluginB/2.1.0/.claude-plugin" "$MP/pluginB/2.1.0/skills/z"
  printf '{"name":"pluginB","description":"d","version":"2.1.0"}\n' > "$MP/pluginB/2.1.0/.claude-plugin/plugin.json"
  printf -- '---\nname: z\ndescription: skill z\n---\nbody\n' > "$MP/pluginB/2.1.0/skills/z/SKILL.md"
  cat > "$TRACE" <<EOF
{"ts":"2026-07-01T09:00:00Z","session_id":"S1","type":"session_start","source":"startup","plugin_root":"$MP/pluginA/1.0.0"}
{"ts":"2026-07-01T09:01:00Z","session_id":"S1","type":"skill","skill":"pluginA:x","trigger":"model"}
EOF
  run node "$REPORT" --trace "$TRACE" --json
  [ "$status" -eq 0 ]
  [ "$(jget 'r.meta.plugins_dir_source')" = "trace" ]
  [ "$(jget 'r.meta.plugins_dir')" = "$MP" ]
  [ "$(jget 'r.inventory.plugins')" = "2" ]
  [ "$(jget 'r.inventory.skills')" = "2" ]
  [ "$(jget 'r.inventory.commands')" = "1" ]
  [ "$(jget 'r.inventory.unused_skills.map(u=>u.id).sort().join(",")')" = "pluginB:z" ]
  [ "$(jget 'r.inventory.unknown_called.length')" = "0" ]
}

@test "report: crlf frontmatter and broken plugin.json tolerated" {
  make_fake_plugins
  # pb 의 plugin.json 을 깨뜨려도 디렉터리명 폴백으로 계속 열거돼야 한다
  printf 'not-json{{{' > "$FAKE/pb/.claude-plugin/plugin.json"
  # CRLF frontmatter 스킬 추가
  mkdir -p "$FAKE/pa/skills/s3"
  printf -- '---\r\nname: s3\r\ndescription: crlf skill\r\n---\r\nbody\n' > "$FAKE/pa/skills/s3/SKILL.md"
  run_report
  [ "$status" -eq 0 ]
  [ "$(jget 'r.inventory.plugins')" = "2" ]
  [[ "$(jget 'r.inventory.unused_skills.map(u=>u.id).sort().join(",")')" == *"pa:s3"* ]]
  [[ "$(jget 'r.inventory.unused_skills.map(u=>u.id).sort().join(",")')" == *"pb:s2"* ]]
}

@test "report: lifecycle stale classification with injected now" {
  make_fake_plugins; write_fixture_trace
  # 픽스처 ts = 2026-07-01, now = 45일 후 → 사용 자산 3종(s1/c1/a1) 전부 stale (30 <= 45 < 90)
  run_report --now 2026-08-15T00:00:00Z
  [ "$status" -eq 0 ]
  [ "$(jget 'r.meta.now')" = "2026-08-15T00:00:00.000Z" ]
  [ "$(jget 'r.inventory.lifecycle.stale_days')" = "30" ]
  [ "$(jget 'r.inventory.lifecycle.stale.map(x=>x.id).sort().join(",")')" = "pa:a1,pa:c1,pa:s1" ]
  [ "$(jget 'r.inventory.lifecycle.archive_candidates.length')" = "0" ]
  [ "$(jget 'r.inventory.lifecycle.stale[0].idle_days')" = "44" ]
  # 미사용-전체(s2)는 라이프사이클에 섞이지 않는다 — unused_* 버킷 소관
  [[ "$(jget 'r.inventory.lifecycle.stale.map(x=>x.id).join(",")')" != *"pb:s2"* ]]
  [ "$(jget 'r.inventory.unused_skills.map(u=>u.id).join(",")')" = "pb:s2" ]
}

@test "report: lifecycle archive candidates past archive threshold" {
  make_fake_plugins; write_fixture_trace
  # now = 106일 후 → 전부 archive 후보, stale 은 비어야 한다 (구간 배타)
  run_report --now 2026-10-15T00:00:00Z
  [ "$status" -eq 0 ]
  [ "$(jget 'r.inventory.lifecycle.archive_candidates.map(x=>x.id).sort().join(",")')" = "pa:a1,pa:c1,pa:s1" ]
  [ "$(jget 'r.inventory.lifecycle.stale.length')" = "0" ]
}

@test "report: lifecycle disabled with stale-days zero" {
  make_fake_plugins; write_fixture_trace
  run_report --now 2026-10-15T00:00:00Z --stale-days 0
  [ "$status" -eq 0 ]
  [ "$(jget 'r.inventory.lifecycle.stale.length')" = "0" ]
  [ "$(jget 'r.inventory.lifecycle.archive_candidates.length')" = "0" ]
}

@test "report: coverage span reported from windowed records" {
  make_fake_plugins; write_fixture_trace
  run_report --now 2026-08-15T00:00:00Z
  [ "$status" -eq 0 ]
  # 픽스처 관측 구간 09:00~09:08 (8분) → 0.0일 반올림, 임계(30일)보다 짧다
  [ "$(jget 'r.meta.coverage.first_ts')" = "2026-07-01T09:00:00.000Z" ]
  [ "$(jget 'r.meta.coverage.last_ts')" = "2026-07-01T09:08:00.000Z" ]
  [ "$(jget 'r.meta.coverage.days')" = "0" ]
}

@test "report: followup pairs action with next plain prompt only" {
  make_fake_plugins; write_fixture_trace
  run_report
  [ "$status" -eq 0 ]
  # 픽스처 시퀀스: skill s1 → 커맨드 프롬프트(/c1, 쌍 없이 소거) → skill c1 → 평문 프롬프트(쌍 성립)
  # → 평문 프롬프트(액션 없음) → agent a1 → skill ghost(교체) → session_end(소거)
  [ "$(jget 'r.followups.length')" = "1" ]
  [ "$(jget 'r.followups[0].kind')" = "skill" ]
  [ "$(jget 'r.followups[0].target')" = "pa:c1" ]
  [ "$(jget 'r.followups[0].next_prompt')" = "what is the meaning of life" ]
  [ "$(jget 'r.followups[0].action_ts')" = "2026-07-01T09:02:10Z" ]
}

@test "report: followups cap zero returns none" {
  make_fake_plugins; write_fixture_trace
  run_report --followups 0
  [ "$status" -eq 0 ]
  [ "$(jget 'r.followups.length')" = "0" ]
}
