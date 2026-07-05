#!/usr/bin/env bats
# =============================================================================
# block-md-creation.bats — base 플러그인 문서 파일 생성 차단 훅 회귀 테스트
# 대상: plugins/base/bin/hooks/block-md-creation.js
#       (PreToolUse: Write 로 허용목록 밖 .md/.txt 생성을 exit 2 로 차단)
# 규약: 차단은 exit 2(PreToolUse), 허용은 exit 0 + 원본 passthrough.
# 허용: README/CLAUDE/AGENTS/CONTRIBUTING/HANDOFF.md, .planning/**, tasks/**
# 주의: @test 이름은 ASCII.
# =============================================================================

bats_require_minimum_version 1.5.0

load 'helpers'

setup()    { make_project; }
teardown() { cleanup_project; }

BLOCK_HOOK="$REPO_ROOT/plugins/base/bin/hooks/block-md-creation.js"

invoke_node_hook() {
  local hook="$1" stdin_json="${2:-"{}"}"
  printf '%s' "$stdin_json" | CLAUDE_PROJECT_DIR="$TEST_PROJ" node "$hook"
}
write_event() { printf '{"tool":"Write","tool_input":{"file_path":"%s"}}' "$1"; }

# ── 차단 대상 ────────────────────────────────────────────────────────────────

@test "block-md: arbitrary .md -> blocked (exit 2)" {
  run invoke_node_hook "$BLOCK_HOOK" "$(write_event "docs/random-notes.md")"
  [ "$status" -eq 2 ]
  [[ "$output" == *"BLOCKED"* ]]
}

@test "block-md: arbitrary .txt -> blocked (exit 2)" {
  run invoke_node_hook "$BLOCK_HOOK" "$(write_event "scratch.txt")"
  [ "$status" -eq 2 ]
}

# ── 허용 대상 (기존) ─────────────────────────────────────────────────────────

@test "block-md: README.md -> allowed (exit 0)" {
  local ev; ev="$(write_event "README.md")"
  run invoke_node_hook "$BLOCK_HOOK" "$ev"
  [ "$status" -eq 0 ]
  [ "$output" = "$ev" ]
}

@test "block-md: .planning/ output -> allowed (exit 0)" {
  run invoke_node_hook "$BLOCK_HOOK" "$(write_event ".planning/prd.md")"
  [ "$status" -eq 0 ]
}

# ── 허용 대상 (신규: workflow 하네스 산출물) ──────────────────────────────────

# /handoff 의 HANDOFF.md — 허용목록 추가분
@test "block-md: HANDOFF.md -> allowed (exit 0)" {
  local ev; ev="$(write_event "HANDOFF.md")"
  run invoke_node_hook "$BLOCK_HOOK" "$ev"
  [ "$status" -eq 0 ]
  [ "$output" = "$ev" ]
}

# /release-notes 의 CHANGELOG.md — 허용목록 추가분
@test "block-md: CHANGELOG.md -> allowed (exit 0)" {
  local ev; ev="$(write_event "CHANGELOG.md")"
  run invoke_node_hook "$BLOCK_HOOK" "$ev"
  [ "$status" -eq 0 ]
  [ "$output" = "$ev" ]
}

# /retro 의 tasks/lessons.md — tasks/ 경로 예외
@test "block-md: tasks/lessons.md -> allowed (exit 0)" {
  run invoke_node_hook "$BLOCK_HOOK" "$(write_event "tasks/lessons.md")"
  [ "$status" -eq 0 ]
}

@test "block-md: tasks/todo.md -> allowed (exit 0)" {
  run invoke_node_hook "$BLOCK_HOOK" "$(write_event "tasks/todo.md")"
  [ "$status" -eq 0 ]
}

# 경로 중간의 tasks/ 도 예외 (모노레포 하위 프로젝트)
@test "block-md: sub/tasks/notes.md -> allowed (exit 0)" {
  run invoke_node_hook "$BLOCK_HOOK" "$(write_event "packages/app/tasks/notes.md")"
  [ "$status" -eq 0 ]
}

# ── 허용 대상 (신규: 하네스 관리 영역 — 프로젝트 외부) ─────────────────────────

# Claude Code 자동 메모리 — 시스템 프롬프트가 Write 를 지시하는 per-fact .md 저장소
@test "block-md: auto-memory dir .md -> allowed (exit 0)" {
  local ev; ev="$(write_event "/Users/u/.claude/projects/-Users-u-proj/memory/some-fact.md")"
  run invoke_node_hook "$BLOCK_HOOK" "$ev"
  [ "$status" -eq 0 ]
  [ "$output" = "$ev" ]
}

@test "block-md: auto-memory MEMORY.md index -> allowed (exit 0)" {
  run invoke_node_hook "$BLOCK_HOOK" "$(write_event "/Users/u/.claude/projects/-Users-u-proj/memory/MEMORY.md")"
  [ "$status" -eq 0 ]
}

# 세션 스크래치패드 — Artifact 렌더링용 .md 산출 경로 (macOS /private/tmp, Linux /tmp)
@test "block-md: scratchpad .md (private tmp) -> allowed (exit 0)" {
  run invoke_node_hook "$BLOCK_HOOK" "$(write_event "/private/tmp/claude-501/-proj/sess-id/scratchpad/report.md")"
  [ "$status" -eq 0 ]
}

@test "block-md: scratchpad .md (plain tmp) -> allowed (exit 0)" {
  run invoke_node_hook "$BLOCK_HOOK" "$(write_event "/tmp/claude-501/-proj/sess-id/scratchpad/report.md")"
  [ "$status" -eq 0 ]
}

# memory/ 밖의 .claude/projects/ 하위는 여전히 차단 — 예외가 과확장되지 않았는지 가드
@test "block-md: .claude/projects non-memory .md -> blocked (exit 2)" {
  run invoke_node_hook "$BLOCK_HOOK" "$(write_event "/Users/u/.claude/projects/-Users-u-proj/notes.md")"
  [ "$status" -eq 2 ]
}

# ── 비대상 ──────────────────────────────────────────────────────────────────

# .md/.txt 가 아닌 파일 — 관여하지 않고 passthrough
@test "block-md: non-doc file (.kt) -> passthrough (exit 0)" {
  local ev; ev="$(write_event "src/Main.kt")"
  run invoke_node_hook "$BLOCK_HOOK" "$ev"
  [ "$status" -eq 0 ]
  [ "$output" = "$ev" ]
}
