#!/usr/bin/env bats
# =============================================================================
# hooks-registration.bats — 플러그인 hooks.json 등록면 정합성 lint
# 대상: plugins/*/hooks/hooks.json (전체)
# 배경: PreToolUse/PostToolUse 의 matcher 는 tool 명 regex 만 유효하며,
#       'tool == "..."' / '... matches ...' / 'tool_input.' 같은 표현식 matcher 는
#       실측상 미발화(2026-07)다. 과거 warn-security 훅이 표현식 matcher 로 등록돼
#       완전히 죽어 있었으나, 스크립트를 직접 invoke 하는 기존 bats 가 이를 놓쳤다.
#       이 lint 는 등록면(matcher/dispatch)을 직접 검사해 그 회귀 클래스를 잡는다.
# 규약: matcher 는 jq 로 필드만 추출해 검사(description 텍스트 오탐 방지).
# 주의: @test 이름은 ASCII — macOS 기본 bash 3.2 bats 인코딩 문제 회피.
# =============================================================================

bats_require_minimum_version 1.5.0

load 'helpers'

# 표현식 matcher 로 오인될 금지 토큰 — tool 명 regex 에는 등장하지 않는다.
FORBIDDEN='tool[[:space:]]*==|[[:space:]]matches[[:space:]]|tool_input\.'

# 모든 plugin hooks.json 경로 목록
plugin_hooks_files() {
  find "$REPO_ROOT/plugins" -path '*/hooks/hooks.json'
}

# 유효 JSON — 모든 hooks.json 이 jq 로 파싱된다
@test "hooks-registration: every plugin hooks.json is valid JSON" {
  local f
  for f in $(plugin_hooks_files); do
    run jq empty "$f"
    [ "$status" -eq 0 ] || { echo "invalid JSON: $f"; false; }
  done
}

# PreToolUse/PostToolUse matcher 는 표현식이 아닌 tool 명 regex 여야 한다
@test "hooks-registration: PreToolUse/PostToolUse matchers use tool-name regex, not expressions" {
  local f violations=""
  for f in $(plugin_hooks_files); do
    # matcher 필드만 추출(description 등 다른 텍스트 제외)
    local matchers
    matchers="$(jq -r '((.hooks.PreToolUse // []) + (.hooks.PostToolUse // []))[].matcher // empty' "$f")"
    while IFS= read -r m; do
      [ -z "$m" ] && continue
      if printf '%s' "$m" | grep -Eq "$FORBIDDEN"; then
        violations="$violations
$f -> matcher: $m"
      fi
    done <<< "$matchers"
  done
  [ -z "$violations" ] || { printf 'expression matcher(s) found (미발화):%s\n' "$violations"; false; }
}

# 훅 command 가 참조하는 스크립트 파일이 실재한다(dispatch 정합)
@test "hooks-registration: every hook command script exists" {
  local f violations=""
  for f in $(plugin_hooks_files); do
    local plugin_root; plugin_root="$(dirname "$(dirname "$f")")"
    local scripts
    # 모든 이벤트의 모든 훅에서 args 배열 원소 중 CLAUDE_PLUGIN_ROOT 참조 경로 추출
    scripts="$(jq -r '.hooks | to_entries[].value[].hooks[]?.args[]? // empty | select(startswith("${CLAUDE_PLUGIN_ROOT}"))' "$f")"
    while IFS= read -r s; do
      [ -z "$s" ] && continue
      local resolved="${s/\$\{CLAUDE_PLUGIN_ROOT\}/$plugin_root}"
      [ -f "$resolved" ] || violations="$violations
$f -> missing: $resolved"
    done <<< "$scripts"
  done
  [ -z "$violations" ] || { printf 'referenced hook script(s) not found:%s\n' "$violations"; false; }
}
