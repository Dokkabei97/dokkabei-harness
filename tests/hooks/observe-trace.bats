#!/usr/bin/env bats
# =============================================================================
# observe-trace.bats — observe 트레이스 훅 회귀 테스트
# 대상: plugins/observe/bin/hooks/trace-prompt.js  (UserPromptSubmit)
#       plugins/observe/bin/hooks/trace-skill.js   (PreToolUse: Skill)
#       plugins/observe/bin/hooks/trace-agent.js   (PreToolUse: Agent|Task)
#       plugins/observe/bin/hooks/trace-result.js  (PostToolUse: Skill|Agent|Task)
#       plugins/observe/bin/hooks/trace-session.js (SessionStart/SessionEnd)
# 규약: OBSERVE_TRACE=1 opt-in — 미설정 시 완전 무동작(파일 미생성).
#       어떤 입력에도 항상 exit 0 + stdout/stderr 무출력(컨텍스트 오염 0).
#       기록은 $CLAUDE_PROJECT_DIR/.claude/skill-trace.jsonl append-only JSONL.
# 주의: @test 이름은 ASCII. OBSERVE_TRACE 는 셸 누출 방지를 위해 setup 에서 unset.
# =============================================================================

bats_require_minimum_version 1.5.0

load 'helpers'

setup()    { make_project; unset OBSERVE_TRACE; TRACE="$TEST_PROJ/.claude/skill-trace.jsonl"; }
teardown() { cleanup_project; }

PROMPT_HOOK="$REPO_ROOT/plugins/observe/bin/hooks/trace-prompt.js"
SKILL_HOOK="$REPO_ROOT/plugins/observe/bin/hooks/trace-skill.js"
AGENT_HOOK="$REPO_ROOT/plugins/observe/bin/hooks/trace-agent.js"
RESULT_HOOK="$REPO_ROOT/plugins/observe/bin/hooks/trace-result.js"
SESSION_HOOK="$REPO_ROOT/plugins/observe/bin/hooks/trace-session.js"

# 훅 실행 — OBSERVE_TRACE 는 호출부가 export 로 제어
invoke_node_hook() {
  local hook="$1" stdin_json="${2:-"{}"}"
  printf '%s' "$stdin_json" | CLAUDE_PROJECT_DIR="$TEST_PROJ" node "$hook"
}

# 트레이스 마지막 레코드의 필드 값 출력 (null/미존재는 빈 문자열)
last_field() {
  TRACE_PATH="$TRACE" node -e '
    const fs = require("fs");
    const lines = fs.readFileSync(process.env.TRACE_PATH, "utf8").trim().split("\n");
    const rec = JSON.parse(lines[lines.length - 1]);
    const v = rec[process.argv[1]];
    process.stdout.write(v === null || v === undefined ? "" : String(v));
  ' "$1"
}

trace_lines() { [ -f "$TRACE" ] && wc -l < "$TRACE" | tr -d ' ' || echo 0; }

skill_event() { # $1 skill, $2 args, $3 transcript path("" 허용)
  printf '{"tool_name":"Skill","tool_input":{"skill":"%s","args":"%s"},"session_id":"sess-1","transcript_path":"%s","cwd":"%s"}' \
    "$1" "$2" "${3:-}" "$TEST_PROJ"
}

# ── opt-in 게이트 ────────────────────────────────────────────────────────────

@test "trace-prompt: gate off -> no file, exit 0, silent" {
  run invoke_node_hook "$PROMPT_HOOK" '{"session_id":"s","prompt":"hello"}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -e "$TRACE" ]
}

@test "trace-skill: gate off -> no file, exit 0, silent" {
  run invoke_node_hook "$SKILL_HOOK" "$(skill_event 'analyze:analyze' 'x' '')"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -e "$TRACE" ]
}

# ── prompt 레코드 ────────────────────────────────────────────────────────────

@test "trace-prompt: gate on -> prompt record appended, silent" {
  export OBSERVE_TRACE=1
  run invoke_node_hook "$PROMPT_HOOK" '{"session_id":"sess-1","prompt":"fix the bug"}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$(trace_lines)" = "1" ]
  [ "$(last_field type)" = "prompt" ]
  [ "$(last_field text)" = "fix the bug" ]
  [ "$(last_field session_id)" = "sess-1" ]
}

@test "trace-prompt: user_prompt field fallback" {
  export OBSERVE_TRACE=1
  run invoke_node_hook "$PROMPT_HOOK" '{"session_id":"s","user_prompt":"alt field"}'
  [ "$status" -eq 0 ]
  [ "$(last_field text)" = "alt field" ]
}

@test "trace-prompt: broken stdin json -> exit 0, no crash" {
  export OBSERVE_TRACE=1
  run invoke_node_hook "$PROMPT_HOOK" 'not-json{{{'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ── skill 레코드: 기본 필드 ──────────────────────────────────────────────────

@test "trace-skill: basic event -> skill record, trigger model without transcript" {
  export OBSERVE_TRACE=1
  run invoke_node_hook "$SKILL_HOOK" "$(skill_event 'analyze:analyze' 'src/' '')"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$(last_field type)" = "skill" ]
  [ "$(last_field skill)" = "analyze:analyze" ]
  [ "$(last_field args)" = "src/" ]
  [ "$(last_field trigger)" = "model" ]
  [ "$(last_field why)" = "" ]
}

@test "trace-skill: non-Skill tool_name -> no record (double guard)" {
  export OBSERVE_TRACE=1
  run invoke_node_hook "$SKILL_HOOK" '{"tool_name":"Bash","tool_input":{"command":"ls"},"session_id":"s"}'
  [ "$status" -eq 0 ]
  [ ! -e "$TRACE" ]
}

@test "trace-skill: args over 1000 chars -> truncated" {
  export OBSERVE_TRACE=1
  local long; long="$(printf 'a%.0s' $(seq 1 1200))"
  run invoke_node_hook "$SKILL_HOOK" "$(skill_event 'x:y' "$long" '')"
  [ "$status" -eq 0 ]
  local args; args="$(last_field args)"
  [[ "$args" == *"[truncated]" ]]
}

# ── skill 레코드: trigger 분류 + why (transcript 결합) ───────────────────────

@test "trace-skill: user slash invocation in transcript -> trigger user" {
  export OBSERVE_TRACE=1
  local tr="$TEST_PROJ/transcript.jsonl"
  printf '%s\n' '{"message":{"role":"user","content":"/analyze:analyze src/"}}' > "$tr"
  run invoke_node_hook "$SKILL_HOOK" "$(skill_event 'analyze:analyze' 'src/' "$tr")"
  [ "$status" -eq 0 ]
  [ "$(last_field trigger)" = "user" ]
}

@test "trace-skill: command wrapper in transcript -> trigger user" {
  export OBSERVE_TRACE=1
  local tr="$TEST_PROJ/transcript.jsonl"
  printf '%s\n' '{"message":{"role":"user","content":"<command-name>/verify-flow</command-name><command-args>plugins/observe</command-args>"}}' > "$tr"
  run invoke_node_hook "$SKILL_HOOK" "$(skill_event 'harness:verify-flow' '' "$tr")"
  [ "$status" -eq 0 ]
  [ "$(last_field trigger)" = "user" ]
}

@test "trace-skill: unrelated user text -> trigger model, why from turn preamble" {
  export OBSERVE_TRACE=1
  local tr="$TEST_PROJ/transcript.jsonl"
  {
    printf '%s\n' '{"message":{"role":"user","content":"please review the search pipeline"}}'
    printf '%s\n' '{"message":{"role":"assistant","content":[{"type":"text","text":"ES query review skill fits here"}]}}'
  } > "$tr"
  run invoke_node_hook "$SKILL_HOOK" "$(skill_event 'search:es-query-review' '' "$tr")"
  [ "$status" -eq 0 ]
  [ "$(last_field trigger)" = "model" ]
  [ "$(last_field why)" = "ES query review skill fits here" ]
  [ "$(last_field why_source)" = "preamble" ]
}

@test "trace-skill: preamble from previous turn not attributed (turn boundary)" {
  export OBSERVE_TRACE=1
  local tr="$TEST_PROJ/transcript.jsonl"
  {
    printf '%s\n' '{"message":{"role":"user","content":"old request"}}'
    printf '%s\n' '{"message":{"role":"assistant","content":[{"type":"text","text":"stale preamble from last turn"}]}}'
    printf '%s\n' '{"message":{"role":"user","content":"new request without preamble"}}'
  } > "$tr"
  run invoke_node_hook "$SKILL_HOOK" "$(skill_event 'x:y' '' "$tr")"
  [ "$status" -eq 0 ]
  [ "$(last_field why)" = "" ]
}

# ── 저장 계층 (trace.js) ─────────────────────────────────────────────────────

@test "trace: first write with .git -> gitignore safety net added once" {
  export OBSERVE_TRACE=1
  mkdir -p "$TEST_PROJ/.git"
  run invoke_node_hook "$PROMPT_HOOK" '{"session_id":"s","prompt":"a"}'
  run invoke_node_hook "$PROMPT_HOOK" '{"session_id":"s","prompt":"b"}'
  [ "$status" -eq 0 ]
  local n; n="$(grep -c '^\.claude/skill-trace\.jsonl\*$' "$TEST_PROJ/.gitignore")"
  [ "$n" = "1" ]
}

@test "trace: over 10MB -> rotated to .1, fresh file appended" {
  export OBSERVE_TRACE=1
  mkdir -p "$TEST_PROJ/.claude"
  head -c $((10 * 1024 * 1024 + 1)) /dev/zero > "$TRACE"
  run invoke_node_hook "$PROMPT_HOOK" '{"session_id":"s","prompt":"after rotate"}'
  [ "$status" -eq 0 ]
  [ -f "$TRACE.1" ]
  [ "$(trace_lines)" = "1" ]
  [ "$(last_field text)" = "after rotate" ]
}

# ── additive 확장 필드 (2026-07) ─────────────────────────────────────────────

@test "trace-prompt: prompt_id and is_command recorded" {
  export OBSERVE_TRACE=1
  run invoke_node_hook "$PROMPT_HOOK" '{"session_id":"s","prompt_id":"p-9","prompt":"/retro --dry-run"}'
  [ "$status" -eq 0 ]
  [ "$(last_field prompt_id)" = "p-9" ]
  [ "$(last_field is_command)" = "true" ]
  run invoke_node_hook "$PROMPT_HOOK" '{"session_id":"s","prompt":"plain request"}'
  [ "$(last_field is_command)" = "false" ]
  [ "$(last_field prompt_id)" = "" ]
}

@test "trace-skill: tool_use_id, prompt_id, parent agent fields recorded" {
  export OBSERVE_TRACE=1
  local ev='{"tool_name":"Skill","tool_input":{"skill":"a:b"},"session_id":"s","prompt_id":"p-1","tool_use_id":"tu-1","agent_id":"ag-7","agent_type":"Explore"}'
  run invoke_node_hook "$SKILL_HOOK" "$ev"
  [ "$status" -eq 0 ]
  [ "$(last_field tool_use_id)" = "tu-1" ]
  [ "$(last_field prompt_id)" = "p-1" ]
  [ "$(last_field agent_id)" = "ag-7" ]
  [ "$(last_field agent_type)" = "Explore" ]
}

@test "trace-skill: turn_command preserves chain provenance, trigger stays model" {
  export OBSERVE_TRACE=1
  local tr="$TEST_PROJ/transcript.jsonl"
  printf '%s\n' '{"message":{"role":"user","content":"<command-name>/mvp-new</command-name><command-args>idea</command-args>"}}' > "$tr"
  run invoke_node_hook "$SKILL_HOOK" "$(skill_event 'mvp:mvp-orchestrator' '' "$tr")"
  [ "$status" -eq 0 ]
  [ "$(last_field trigger)" = "model" ]
  [ "$(last_field turn_command)" = "mvp-new" ]
}

# ── agent 레코드 (trace-agent.js) ────────────────────────────────────────────

@test "trace-agent: gate off -> no file" {
  run invoke_node_hook "$AGENT_HOOK" '{"tool_name":"Agent","tool_input":{"subagent_type":"Explore"},"session_id":"s"}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -e "$TRACE" ]
}

@test "trace-agent: Agent call -> agent record with type, description, prompt_head" {
  export OBSERVE_TRACE=1
  local ev='{"tool_name":"Agent","tool_input":{"subagent_type":"search:es-query-optimizer","description":"slow query triage","prompt":"analyze the slow ES query","model":"haiku"},"session_id":"s","tool_use_id":"tu-2","prompt_id":"p-2"}'
  run invoke_node_hook "$AGENT_HOOK" "$ev"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$(last_field type)" = "agent" ]
  [ "$(last_field agent)" = "search:es-query-optimizer" ]
  [ "$(last_field description)" = "slow query triage" ]
  [ "$(last_field prompt_head)" = "analyze the slow ES query" ]
  [ "$(last_field model)" = "haiku" ]
  [ "$(last_field tool_use_id)" = "tu-2" ]
}

@test "trace-agent: legacy Task tool name accepted" {
  export OBSERVE_TRACE=1
  run invoke_node_hook "$AGENT_HOOK" '{"tool_name":"Task","tool_input":{"subagent_type":"general-purpose"},"session_id":"s"}'
  [ "$status" -eq 0 ]
  [ "$(last_field type)" = "agent" ]
  [ "$(last_field agent)" = "general-purpose" ]
}

@test "trace-agent: non-agent tool -> no record (double guard)" {
  export OBSERVE_TRACE=1
  run invoke_node_hook "$AGENT_HOOK" '{"tool_name":"Bash","tool_input":{"command":"ls"},"session_id":"s"}'
  [ "$status" -eq 0 ]
  [ ! -e "$TRACE" ]
}

@test "trace-agent: long prompt truncated to 300 chars + marker" {
  export OBSERVE_TRACE=1
  local long; long="$(printf 'p%.0s' $(seq 1 500))"
  run invoke_node_hook "$AGENT_HOOK" "{\"tool_name\":\"Agent\",\"tool_input\":{\"subagent_type\":\"x\",\"prompt\":\"$long\"},\"session_id\":\"s\"}"
  [ "$status" -eq 0 ]
  local head; head="$(last_field prompt_head)"
  [[ "$head" == *"[truncated]" ]]
}

@test "trace-agent: why extracted from turn preamble" {
  export OBSERVE_TRACE=1
  local tr="$TEST_PROJ/transcript.jsonl"
  {
    printf '%s\n' '{"message":{"role":"user","content":"tune relevance"}}'
    printf '%s\n' '{"message":{"role":"assistant","content":[{"type":"text","text":"delegating to relevance engineer"}]}}'
  } > "$tr"
  run invoke_node_hook "$AGENT_HOOK" "{\"tool_name\":\"Agent\",\"tool_input\":{\"subagent_type\":\"x\"},\"session_id\":\"s\",\"transcript_path\":\"$tr\"}"
  [ "$status" -eq 0 ]
  [ "$(last_field why)" = "delegating to relevance engineer" ]
}

# ── result 레코드 (trace-result.js) ──────────────────────────────────────────

@test "trace-result: gate off -> no file" {
  run invoke_node_hook "$RESULT_HOOK" '{"tool_name":"Skill","tool_input":{"skill":"a:b"},"session_id":"s"}'
  [ "$status" -eq 0 ]
  [ ! -e "$TRACE" ]
}

@test "trace-result: Skill completion -> result record with target and bytes" {
  export OBSERVE_TRACE=1
  local ev='{"tool_name":"Skill","tool_input":{"skill":"analyze:analyze"},"session_id":"s","tool_use_id":"tu-3","tool_response":"0123456789"}'
  run invoke_node_hook "$RESULT_HOOK" "$ev"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$(last_field type)" = "result" ]
  [ "$(last_field tool)" = "Skill" ]
  [ "$(last_field target)" = "analyze:analyze" ]
  [ "$(last_field tool_use_id)" = "tu-3" ]
  [ "$(last_field response_bytes)" = "10" ]
}

@test "trace-result: Agent completion -> target is subagent_type, object response measured" {
  export OBSERVE_TRACE=1
  local ev='{"tool_name":"Agent","tool_input":{"subagent_type":"Explore"},"session_id":"s","tool_response":{"ok":true}}'
  run invoke_node_hook "$RESULT_HOOK" "$ev"
  [ "$status" -eq 0 ]
  [ "$(last_field target)" = "Explore" ]
  [ "$(last_field response_bytes)" = "11" ]
}

@test "trace-result: missing tool_response -> record with null bytes, no crash" {
  export OBSERVE_TRACE=1
  run invoke_node_hook "$RESULT_HOOK" '{"tool_name":"Skill","tool_input":{"skill":"a:b"},"session_id":"s"}'
  [ "$status" -eq 0 ]
  [ "$(last_field type)" = "result" ]
  [ "$(last_field response_bytes)" = "" ]
}

@test "trace-result: non-target tool -> no record (double guard)" {
  export OBSERVE_TRACE=1
  run invoke_node_hook "$RESULT_HOOK" '{"tool_name":"Bash","tool_input":{"command":"ls"},"session_id":"s"}'
  [ "$status" -eq 0 ]
  [ ! -e "$TRACE" ]
}

# ── session 레코드 (trace-session.js) ────────────────────────────────────────

@test "trace-session: gate off -> no file" {
  run invoke_node_hook "$SESSION_HOOK" '{"hook_event_name":"SessionStart","session_id":"s","source":"startup"}'
  [ "$status" -eq 0 ]
  [ ! -e "$TRACE" ]
}

@test "trace-session: SessionStart -> session_start record with source and plugin_root" {
  export OBSERVE_TRACE=1
  local ev='{"hook_event_name":"SessionStart","session_id":"s","source":"startup"}'
  run bash -c "printf '%s' '$ev' | CLAUDE_PROJECT_DIR='$TEST_PROJ' CLAUDE_PLUGIN_ROOT='/fake/plugins/observe' node '$SESSION_HOOK'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$(last_field type)" = "session_start" ]
  [ "$(last_field source)" = "startup" ]
  [ "$(last_field plugin_root)" = "/fake/plugins/observe" ]
}

@test "trace-session: SessionEnd -> session_end record with reason" {
  export OBSERVE_TRACE=1
  run invoke_node_hook "$SESSION_HOOK" '{"hook_event_name":"SessionEnd","session_id":"s","reason":"clear"}'
  [ "$status" -eq 0 ]
  [ "$(last_field type)" = "session_end" ]
  [ "$(last_field reason)" = "clear" ]
}

@test "trace-session: other event name -> no record (double guard)" {
  export OBSERVE_TRACE=1
  run invoke_node_hook "$SESSION_HOOK" '{"hook_event_name":"Stop","session_id":"s"}'
  [ "$status" -eq 0 ]
  [ ! -e "$TRACE" ]
}

# ── 리뷰 확정 결함 회귀 (2026-07 반증 리뷰) ──────────────────────────────────

@test "trace-skill: local-command-stdout record is not a turn boundary" {
  export OBSERVE_TRACE=1
  local tr="$TEST_PROJ/transcript.jsonl"
  {
    printf '%s\n' '{"message":{"role":"user","content":"<command-name>/tdd</command-name><command-args>foo</command-args>"}}'
    printf '%s\n' '{"message":{"role":"assistant","content":[{"type":"text","text":"TDD skill preamble"}]}}'
    printf '%s\n' '{"message":{"role":"user","content":"<local-command-stdout>Set model to Fable 5</local-command-stdout>"}}'
  } > "$tr"
  run invoke_node_hook "$SKILL_HOOK" "$(skill_event 'test:tdd' '' "$tr")"
  [ "$status" -eq 0 ]
  [ "$(last_field trigger)" = "user" ]
  [ "$(last_field turn_command)" = "tdd" ]
  [ "$(last_field why)" = "TDD skill preamble" ]
}

@test "trace-prompt: absolute path prompt is not a command" {
  export OBSERVE_TRACE=1
  run invoke_node_hook "$PROMPT_HOOK" '{"session_id":"s","prompt":"/Users/admin/project/foo.kt review this file"}'
  [ "$status" -eq 0 ]
  [ "$(last_field is_command)" = "false" ]
}

@test "trace: CLAUDE_PROJECT_DIR unset -> payload cwd fallback" {
  local ev; ev="$(printf '{"session_id":"s","prompt":"cwd fallback","cwd":"%s"}' "$TEST_PROJ")"
  run bash -c "printf '%s' '$ev' | env -u CLAUDE_PROJECT_DIR OBSERVE_TRACE=1 node '$PROMPT_HOOK'"
  [ "$status" -eq 0 ]
  [ -f "$TRACE" ]
  [ "$(last_field text)" = "cwd fallback" ]
}

# ── v2.1.201 실전 transcript 포맷 회귀 (2026-07 실측) ────────────────────────
# 픽스처는 실세션(3d98ba5e) transcript 라인 787·793~795 를 축약한 것 — 엔벨로프
# (type/uuid/parentUuid/isSidechain/version), message.content 블록 배열, thinking 블록
# 개입, 블록별 분리 기록 구조를 보존하고 usage/서명 등 비구조 필드만 제거했다.
# 실측 핵심: v2.1.201 은 현재 라운드 assistant 레코드(thinking/text/tool_use)를
# PreToolUse 훅 종료 후(툴 시작 시점)에야 flush 한다 → 훅 시점 EOF 스캔은 preamble 을
# 못 본다. 훅은 anchor(tool_use_id) 미발견 시 detached 자식에 기록을 위임한다.

V2_TUID="toolu_015U9PdE6beTGmTez16ZYFfg"
V2_WHY_HEAD="확인해야 할 게 두 갈래네요"

write_v2_user_boundary() { # $1 transcript — PreToolUse 훅 시점의 실측 상태(assistant 미flush)
  printf '%s\n' '{"parentUuid":"07ecbbfc-9fa9-40bc-ab68-6bd28ec68176","isSidechain":false,"promptId":"7f66a472-65aa-4138-a943-45fef1ac2dde","type":"user","message":{"role":"user","content":"grafana 대쉬보드 보니 어떤 스킬/하네스가 호출이 누적되었는지 볼수 있는 대쉬보드는 업슨거 같은데 크롬으로 직접 확인 해볼래?"},"uuid":"306ad205-df4c-4b43-8fed-09a2ae3fcea9","timestamp":"2026-07-05T03:14:24.818Z","userType":"external","entrypoint":"cli","sessionId":"3d98ba5e","version":"2.1.201","gitBranch":"main"}' > "$1"
}

append_v2_assistant_flush() { # $1 transcript — 툴 시작 시점 flush 재현 (블록별 분리 기록)
  {
    printf '%s\n' '{"parentUuid":"d0a17fec","isSidechain":false,"message":{"model":"claude-fable-5","id":"msg_01BfM3Abpp8s8vye7ciXaM7L","type":"message","role":"assistant","content":[{"type":"thinking","thinking":"","signature":"sig"}],"stop_reason":"tool_use"},"type":"assistant","uuid":"b527c9f1","timestamp":"2026-07-05T03:16:20.627Z","sessionId":"3d98ba5e","version":"2.1.201"}'
    printf '%s\n' '{"parentUuid":"b527c9f1","isSidechain":false,"message":{"model":"claude-fable-5","id":"msg_01BfM3Abpp8s8vye7ciXaM7L","type":"message","role":"assistant","content":[{"type":"text","text":"확인해야 할 게 두 갈래네요: ① Grafana 대시보드를 크롬으로 직접 열어 확인하고 보강, ② observe README 재검토. 먼저 브라우저부터 엽니다."}],"stop_reason":"tool_use"},"type":"assistant","uuid":"1022aa23","timestamp":"2026-07-05T03:16:22.562Z","sessionId":"3d98ba5e","version":"2.1.201"}'
    printf '%s\n' '{"parentUuid":"1022aa23","isSidechain":false,"message":{"model":"claude-fable-5","id":"msg_01BfM3Abpp8s8vye7ciXaM7L","type":"message","role":"assistant","content":[{"type":"tool_use","id":"toolu_015U9PdE6beTGmTez16ZYFfg","name":"Skill","input":{"skill":"claude-in-chrome"},"caller":{"type":"direct"}}],"stop_reason":"tool_use"},"type":"assistant","uuid":"a1df6314","timestamp":"2026-07-05T03:16:22.719Z","sessionId":"3d98ba5e","version":"2.1.201"}'
  } >> "$1"
}

v2_skill_event() { # $1 transcript
  printf '{"tool_name":"Skill","tool_input":{"skill":"claude-in-chrome"},"session_id":"3d98ba5e","transcript_path":"%s","cwd":"%s","prompt_id":"7f66a472","tool_use_id":"%s"}' \
    "$1" "$TEST_PROJ" "$V2_TUID"
}

@test "trace-skill: v2 real format anchor flushed -> why from same-turn preamble" {
  export OBSERVE_TRACE=1
  local tr="$TEST_PROJ/transcript.jsonl"
  write_v2_user_boundary "$tr"
  append_v2_assistant_flush "$tr"
  run invoke_node_hook "$SKILL_HOOK" "$(v2_skill_event "$tr")"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$(trace_lines)" = "1" ]
  [ "$(last_field trigger)" = "model" ]
  [ "$(last_field why_source)" = "preamble" ]
  [[ "$(last_field why)" == "$V2_WHY_HEAD"* ]]
  [ "$(last_field tool_use_id)" = "$V2_TUID" ]
}

@test "trace-skill: v2 anchor bounds scan - later turn text not attributed" {
  # 사후 재추출(파이프 재현) 상태: anchor 뒤에 다음 턴이 이미 flush 되어 있어도
  # EOF 가 아니라 anchor 기준으로 스캔해 현재 턴 preamble 에 귀속해야 한다.
  export OBSERVE_TRACE=1
  local tr="$TEST_PROJ/transcript.jsonl"
  write_v2_user_boundary "$tr"
  append_v2_assistant_flush "$tr"
  {
    printf '%s\n' '{"parentUuid":"a1df6314","isSidechain":false,"type":"user","message":{"role":"user","content":"later unrelated request"},"uuid":"u-later","version":"2.1.201"}'
    printf '%s\n' '{"parentUuid":"u-later","isSidechain":false,"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"stale later-turn text"}]},"uuid":"a-later","version":"2.1.201"}'
  } >> "$tr"
  run invoke_node_hook "$SKILL_HOOK" "$(v2_skill_event "$tr")"
  [ "$status" -eq 0 ]
  [[ "$(last_field why)" == "$V2_WHY_HEAD"* ]]
  [ "$(last_field trigger)" = "model" ]
}

@test "trace-skill: v2 preflush state -> deferred child resolves why after flush" {
  # 실전 타이밍 재현: 훅 시점엔 user 경계만 flush → 훅은 즉시 종료(비차단)하고
  # 기록을 detached 자식에 위임 → flush 도착 후 why 가 non-null 로 기록된다.
  export OBSERVE_TRACE=1
  local tr="$TEST_PROJ/transcript.jsonl"
  write_v2_user_boundary "$tr"
  run invoke_node_hook "$SKILL_HOOK" "$(v2_skill_event "$tr")"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -e "$TRACE" ]                # 훅 종료 직후엔 미기록 — 자식이 anchor flush 대기 중
  append_v2_assistant_flush "$tr"  # 툴 시작 시점의 flush 재현
  local i=0
  until [ -e "$TRACE" ] || [ "$i" -ge 50 ]; do sleep 0.1; i=$((i + 1)); done
  [ "$(trace_lines)" = "1" ]
  [ "$(last_field skill)" = "claude-in-chrome" ]
  [ "$(last_field trigger)" = "model" ]
  [ "$(last_field why_source)" = "preamble" ]
  [[ "$(last_field why)" == "$V2_WHY_HEAD"* ]]
}

@test "trace-agent: v2 real format anchored -> why from same-turn preamble" {
  export OBSERVE_TRACE=1
  local tr="$TEST_PROJ/transcript.jsonl"
  write_v2_user_boundary "$tr"
  append_v2_assistant_flush "$tr"
  printf '%s\n' '{"parentUuid":"a1df6314","isSidechain":false,"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_agent01","name":"Task","input":{"subagent_type":"Explore","prompt":"scan repo"}}]},"uuid":"ag-1","version":"2.1.201"}' >> "$tr"
  local ev
  ev="$(printf '{"tool_name":"Task","tool_input":{"subagent_type":"Explore","prompt":"scan repo"},"session_id":"s","transcript_path":"%s","cwd":"%s","tool_use_id":"toolu_agent01"}' "$tr" "$TEST_PROJ")"
  run invoke_node_hook "$AGENT_HOOK" "$ev"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$(last_field type)" = "agent" ]
  [ "$(last_field why_source)" = "preamble" ]
  [[ "$(last_field why)" == "$V2_WHY_HEAD"* ]]
}
