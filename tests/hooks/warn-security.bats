#!/usr/bin/env bats
# =============================================================================
# warn-security.bats — base 플러그인 실시간 보안 경고 훅 회귀 테스트
# 대상: plugins/base/bin/hooks/warn-security.js
#       (PostToolUse: Edit|Write 된 코드 파일의 고신호 취약점 클래스 경고)
# 규약: 경고 전용(비차단) — 항상 exit 0, stdout 으로 원본 이벤트 passthrough,
#       경고는 stderr 로만 출력. 시크릿 값은 앞 4자만 노출(마스킹).
# 주의: @test 이름은 ASCII — macOS 기본 bash 3.2 의 bats 한글 테스트명 인코딩
#       문제 회피. 한국어 설명은 주석 참조.
# =============================================================================

# run --separate-stderr (stdout/stderr 분리 검증) 사용을 위한 최소 버전 선언
bats_require_minimum_version 1.5.0

load 'helpers'

setup()    { make_project; }
teardown() { cleanup_project; }

SECURITY_HOOK="$REPO_ROOT/plugins/base/bin/hooks/warn-security.js"

# node 훅 실행 — helpers 의 invoke_hook 은 bash 훅 전용이라 node 판을 로컬 정의.
# $1 훅 절대 경로, $2 stdin JSON(기본 '{}')
invoke_node_hook() {
  local hook="$1" stdin_json="${2:-"{}"}"
  printf '%s' "$stdin_json" | CLAUDE_PROJECT_DIR="$TEST_PROJ" node "$hook"
}

# Edit 이벤트 stdin JSON 생성 — $1 대상 파일 절대 경로
edit_event() {
  printf '{"tool":"Edit","tool_input":{"file_path":"%s"}}' "$1"
}

# Write 이벤트 stdin JSON 생성 — $1 대상 파일 절대 경로
write_event() {
  printf '{"tool":"Write","tool_input":{"file_path":"%s"}}' "$1"
}

# ── 시크릿 탐지 ──────────────────────────────────────────────────────────────

# AWS 키 — stderr 경고(클래스 라벨 + 마스킹) + stdout 원본 passthrough 유지
@test "warn-security: AWS access key -> stderr warning + stdout passthrough" {
  printf 'const key = "AKIAABCDEFGHIJKLMNOP";\n' > "$TEST_PROJ/config.js"
  local ev; ev="$(edit_event "$TEST_PROJ/config.js")"
  run --separate-stderr invoke_node_hook "$SECURITY_HOOK" "$ev"
  [ "$status" -eq 0 ]
  [ "$output" = "$ev" ]
  [[ "$stderr" == *"[Hook] WARNING"* ]]
  [[ "$stderr" == *"AWS Access Key"* ]]
  [[ "$stderr" == *"security-ok"* ]]
  # 마스킹 — 키 전체가 노출되지 않고 앞 4자 + **** 만
  [[ "$stderr" != *"AKIAABCDEFGHIJKLMNOP"* ]]
  [[ "$stderr" == *"AKIA****"* ]]
}

# placeholder 시크릿(changeme 등) — 경고 없음
@test "warn-security: placeholder secret -> no warning" {
  printf 'const password = "changeme-please";\n' > "$TEST_PROJ/config.js"
  run invoke_node_hook "$SECURITY_HOOK" "$(edit_event "$TEST_PROJ/config.js")"
  [ "$status" -eq 0 ]
  [[ "$output" != *"WARNING"* ]]
}

# 실제 하드코딩 시크릿 — 클래스 라벨 경고 + 값 마스킹
@test "warn-security: hardcoded secret -> warning with masked value" {
  printf 'const password = "supersecretvalue123";\n' > "$TEST_PROJ/config.js"
  local ev; ev="$(edit_event "$TEST_PROJ/config.js")"
  run --separate-stderr invoke_node_hook "$SECURITY_HOOK" "$ev"
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"하드코딩된 시크릿"* ]]
  [[ "$stderr" != *"supersecretvalue123"* ]]
  [[ "$stderr" == *"supe****"* ]]
}

# ── 억제 규약 ────────────────────────────────────────────────────────────────

# security-ok 주석 라인 — 스킵 (경고 없음)
@test "warn-security: security-ok comment line -> skipped" {
  printf 'const key = "AKIAABCDEFGHIJKLMNOP"; // security-ok 테스트 픽스처\n' > "$TEST_PROJ/config.js"
  run invoke_node_hook "$SECURITY_HOOK" "$(edit_event "$TEST_PROJ/config.js")"
  [ "$status" -eq 0 ]
  [[ "$output" != *"WARNING"* ]]
}

# ── 인젝션 탐지 ──────────────────────────────────────────────────────────────

# SQL 문자열 결합 — 해당 클래스 라벨로 경고
@test "warn-security: SQL string concat -> warning with SQL injection label" {
  printf 'const q = "SELECT * FROM users WHERE id = " + userId;\n' > "$TEST_PROJ/query.js"
  run invoke_node_hook "$SECURITY_HOOK" "$(edit_event "$TEST_PROJ/query.js")"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SQL 인젝션 의심"* ]]
}

# ── 무해 케이스 ──────────────────────────────────────────────────────────────

# 클린 파일 — 경고 없이 passthrough 만
@test "warn-security: clean file -> no warning, passthrough only" {
  printf 'function add(a, b) { return a + b; }\n' > "$TEST_PROJ/util.js"
  local ev; ev="$(edit_event "$TEST_PROJ/util.js")"
  run --separate-stderr invoke_node_hook "$SECURITY_HOOK" "$ev"
  [ "$status" -eq 0 ]
  [ "$output" = "$ev" ]
  [ -z "$stderr" ]
}

# 존재하지 않는 file_path — 조용히 passthrough
@test "warn-security: nonexistent file_path -> quiet passthrough" {
  local ev='{"tool":"Edit","tool_input":{"file_path":"/nonexistent/nope.js"}}'
  run --separate-stderr invoke_node_hook "$SECURITY_HOOK" "$ev"
  [ "$status" -eq 0 ]
  [ "$output" = "$ev" ]
  [ -z "$stderr" ]
}

# .md 파일 — 시크릿이 있어도 스킵 (문서 예시 오탐 방지)
@test "warn-security: .md file with secret -> skipped" {
  printf 'AWS 키 예시: AKIAABCDEFGHIJKLMNOP\n' > "$TEST_PROJ/notes.md"
  run invoke_node_hook "$SECURITY_HOOK" "$(edit_event "$TEST_PROJ/notes.md")"
  [ "$status" -eq 0 ]
  [[ "$output" != *"WARNING"* ]]
}

# ── Write 이벤트 ─────────────────────────────────────────────────────────────

# Write 이벤트도 Edit 과 동일하게 처리 — 경고 + 원본 passthrough
@test "warn-security: Write event with secret -> warning + passthrough" {
  printf 'const key = "AKIAABCDEFGHIJKLMNOP";\n' > "$TEST_PROJ/new.js"
  local ev; ev="$(write_event "$TEST_PROJ/new.js")"
  run --separate-stderr invoke_node_hook "$SECURITY_HOOK" "$ev"
  [ "$status" -eq 0 ]
  [ "$output" = "$ev" ]
  [[ "$stderr" == *"AWS Access Key"* ]]
}

# ── 확장자 화이트리스트 (tool 명 matcher 전환 후 스크립트 내부 필터) ──────────

# 코드 파일이 아닌 확장자(.txt) — 시크릿이 있어도 스킵 (matcher 가 Edit|Write tool 명이라
# 확장자 필터는 스크립트 내부 CODE_EXT 가 담당; 표현식 matcher 미발화 회귀 대응)
@test "warn-security: non-code extension (.txt) with secret -> skipped" {
  printf 'AKIAABCDEFGHIJKLMNOP\n' > "$TEST_PROJ/secret.txt"
  run --separate-stderr invoke_node_hook "$SECURITY_HOOK" "$(edit_event "$TEST_PROJ/secret.txt")"
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
}

# .env 파일 — 확장자 없이도 CODE_EXT 의 env 브랜치로 검사 대상
@test "warn-security: .env file with secret -> warning" {
  printf 'API_KEY="sk_live_abcdef123456"\n' > "$TEST_PROJ/.env"
  run --separate-stderr invoke_node_hook "$SECURITY_HOOK" "$(edit_event "$TEST_PROJ/.env")"
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"하드코딩된 시크릿"* ]]
}

# .env.production — env 접미사 브랜치도 검사 대상
@test "warn-security: .env.production with secret -> warning" {
  printf 'DB_PASSWORD="supersecretvalue123"\n' > "$TEST_PROJ/.env.production"
  run --separate-stderr invoke_node_hook "$SECURITY_HOOK" "$(edit_event "$TEST_PROJ/.env.production")"
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"하드코딩된 시크릿"* ]]
}

# ── 오탐·미탐 (placeholder 억제 정밀화) ──────────────────────────────────────

# env 치환 커넥션 스트링 — 자격증명 URL 룰에도 placeholder 억제 적용 (오탐 방지)
@test "warn-security: env-substituted connection string -> no warning" {
  printf 'const url = "postgres://app:${process.env.DB_PASSWORD}@db";\n' > "$TEST_PROJ/db.js"
  run --separate-stderr invoke_node_hook "$SECURITY_HOOK" "$(edit_event "$TEST_PROJ/db.js")"
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
}

# Ansible/Jinja 변수 라인 — '{{' placeholder 억제 (오탐 방지)
@test "warn-security: Jinja template password -> no warning" {
  printf 'password: "{{ vault_db_password }}"\n' > "$TEST_PROJ/vars.yaml"
  run --separate-stderr invoke_node_hook "$SECURITY_HOOK" "$(edit_event "$TEST_PROJ/vars.yaml")"
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
}

# <API_KEY> 류 대문자 placeholder — 억제 유지
@test "warn-security: angle-bracket placeholder -> no warning" {
  printf 'const apiKey = "<API_KEY_GOES_HERE>";\n' > "$TEST_PROJ/config.js"
  run --separate-stderr invoke_node_hook "$SECURITY_HOOK" "$(edit_event "$TEST_PROJ/config.js")"
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
}

# JSX 라인의 실제 시크릿 — 단독 '<' 억제 제거로 경고 발생 (미탐 회귀 가드)
@test "warn-security: JSX line with real secret -> warning" {
  printf 'const el = <Config apiKey="sk_live_abcdef123456" />;\n' > "$TEST_PROJ/app.jsx"
  run --separate-stderr invoke_node_hook "$SECURITY_HOOK" "$(edit_event "$TEST_PROJ/app.jsx")"
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"하드코딩된 시크릿"* ]]
}

# ── 강건성/성능 ──────────────────────────────────────────────────────────────

# 깨진 JSON stdin — 파싱 실패 시 원문 그대로 조용히 passthrough
@test "warn-security: broken JSON stdin -> exit 0 quiet passthrough" {
  run --separate-stderr invoke_node_hook "$SECURITY_HOOK" 'not-a-json'
  [ "$status" -eq 0 ]
  [ "$output" = "not-a-json" ]
  [ -z "$stderr" ]
}

# 1MB 초과 파일 — 시크릿이 있어도 스킵 (무경고)
@test "warn-security: file over 1MB -> skipped" {
  { printf 'const key = "AKIAABCDEFGHIJKLMNOP";\n'
    head -c 1100000 /dev/zero | tr '\0' 'a'; } > "$TEST_PROJ/big.js"
  run --separate-stderr invoke_node_hook "$SECURITY_HOOK" "$(edit_event "$TEST_PROJ/big.js")"
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
}

# 읽기 불가 파일(chmod 000) — unhandled exception 없이 조용히 passthrough
@test "warn-security: unreadable file -> quiet passthrough" {
  if [ "$(id -u)" -eq 0 ]; then skip "root 는 파일 권한을 우회한다"; fi
  printf 'const key = "AKIAABCDEFGHIJKLMNOP";\n' > "$TEST_PROJ/locked.js"
  chmod 000 "$TEST_PROJ/locked.js"
  local ev; ev="$(edit_event "$TEST_PROJ/locked.js")"
  run --separate-stderr invoke_node_hook "$SECURITY_HOOK" "$ev"
  chmod 644 "$TEST_PROJ/locked.js" # teardown rm -rf 대비 복구
  [ "$status" -eq 0 ]
  [ "$output" = "$ev" ]
  [ -z "$stderr" ]
}

# 초장문 단일 라인(수백 KB, 'SELECT ' 다수 + ' FROM ' 부재) — 라인 길이 상한 스킵으로
# 백트래킹 폭주 없이 완료되는지 타이밍 가드 (ReDoS 회귀 방지)
@test "warn-security: huge single-line file -> completes under 5s" {
  local line='SELECT a '
  while [ "${#line}" -lt 400000 ]; do line="$line$line"; done
  printf '%s\n' "$line" > "$TEST_PROJ/minified.sql"
  SECONDS=0
  run --separate-stderr invoke_node_hook "$SECURITY_HOOK" "$(edit_event "$TEST_PROJ/minified.sql")"
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  [ "$SECONDS" -lt 5 ]
}
