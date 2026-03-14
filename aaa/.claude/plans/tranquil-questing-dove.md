# 사내 GitLab 전용 Claude Code 플러그인 완성 계획

## Context

`agents-utils` 프로젝트에 Claude Code 플러그인 구조(agents, commands, skills, hooks, MCP)가 구축되어 있지만, setup.sh와 메타데이터 간 불일치/누락으로 전사 배포에 미완성 상태. `./setup.sh` 한 번으로 플러그인 + 설정(hooks, output-styles, MCP) 전체가 자동 설치되도록 완성한다.

---

## Step 1: 이름 통일 및 메타데이터 정리

**파일**: `setup.sh`, `.claude-plugin/marketplace.json`

- `setup.sh:9` — `PLUGIN_NAME="cowave-devtools"` → `"agents-utils"`
- `marketplace.json` — `owner.email` 필드를 `owner.url`로 수정 (현재 email에 URL이 들어있음)

---

## Step 2: MCP 설정 정리 및 .mcp.json 복원

**파일**: `.mcp.json` (복원), `claude/.cluade.json` (삭제)

- root `.mcp.json` 복원 (올바른 `mcpServers` 래퍼 포함):
  ```json
  {
    "mcpServers": {
      "plane": { ... },
      "outline": { ... },
      "grafana": { ... }
    }
  }
  ```
- `claude/.cluade.json` 삭제 (오타 파일명, .mcp.json으로 통합)
- `mcp/` 디렉토리의 개별 JSON은 레퍼런스 문서로 유지
- 환경변수는 `${VAR_NAME}` 플레이스홀더 사용

---

## Step 3: setup.sh 개선 — settings 자동 머지 추가

**파일**: `setup.sh`

기존 `install_to_cache()` 이후 실행할 `install_claude_settings()` 함수 추가:

1. **백업**: `~/.claude/settings.json` → `~/.claude/settings.json.bak.{timestamp}`
2. **hooks 머지**: `claude/hooks/hooks.json`의 hooks → `~/.claude/settings.json`의 hooks 섹션에 추가
   - 이미 존재하는 hook(description 기준 비교)은 건너뜀 → 멱등성 보장
3. **output-styles 복사**: `claude/output-styles/` → `~/.claude/output-styles/`
4. **statusline 복사**: `claude/statusline-command.sh` → `~/.claude/statusline-command.sh`
5. **statusLine 설정 추가**: settings.json에 statusLine 커맨드 등록
6. **CLAUDE.md 병합**: `claude/CLAUDE.md` 내용을 `~/.claude/CLAUDE.md`에 마커 기반 블록으로 추가
   - `# --- agents-utils plugin start ---` / `# --- agents-utils plugin end ---` 마커 사용
   - 재실행 시 마커 블록 교체 → 멱등성

핵심 원칙: **기존 설정 보존**, **멱등성**, **백업 생성**

---

## Step 4: 경로 포터블화

**파일**: `claude/settings.json`

- `bash /Users/admin/.claude/statusline-command.sh` → `bash $HOME/.claude/statusline-command.sh`
- setup.sh에서 settings.json 복사 시 `$HOME`을 실제 홈 경로로 치환

---

## Step 5: hooks 중복 정리

**파일**: `claude/settings.json`, `claude/hooks/hooks.json`

- `claude/hooks/hooks.json` = hooks의 단일 소스(SSOT)
- `claude/settings.json`에서 hooks 섹션 제거 → `statusLine`과 `enabledPlugins`만 유지
- setup.sh에서 hooks.json 기반으로 사용자 settings에 머지

---

## Step 6: uninstall.sh 추가

**신규 파일**: `uninstall.sh`

- `~/.claude/plugins/cache/cowave-plugins/agents-utils/` 제거
- `~/.claude/plugins/marketplaces/cowave-plugins/` 제거
- `installed_plugins.json`에서 `agents-utils@cowave-plugins` 항목 제거
- `known_marketplaces.json`에서 `cowave-plugins` 항목 제거
- `settings.json`에서 플러그인 비활성화 (`plugins` 키에서 제거)
- CLAUDE.md에서 마커 블록 제거
- hooks에서 플러그인이 추가한 항목 제거
- output-styles에서 플러그인 파일 제거

---

## Step 7: README.md 전사 배포용 업데이트

**파일**: `README.md`

보강할 내용:
- **Quick Start**: 3단계 설치 가이드 (git clone → 환경변수 설정 → ./setup.sh)
- **사전 요구사항**: git, jq, node, claude CLI
- **환경변수 설정**: API 키 발급 URL 및 설정 방법
- **설치되는 내용 요약**: agents, commands, skills, hooks, MCP, output-styles
- **업데이트 방법**: setup.sh 재실행
- **제거 방법**: uninstall.sh
- **트러블슈팅**: FAQ

---

## 수정 대상 파일 요약

| 파일 | 작업 | 비고 |
|------|------|------|
| `setup.sh` | 이름 통일 + settings 머지 로직 추가 | 핵심 변경 |
| `.mcp.json` | 복원 (mcpServers 래퍼 포함) | git restore + 포맷 수정 |
| `claude/.cluade.json` | 삭제 | 오타 파일 정리 |
| `claude/settings.json` | hooks 제거, 경로 포터블화 | SSOT 정리 |
| `.claude-plugin/marketplace.json` | owner.email → owner.url | 메타데이터 수정 |
| `uninstall.sh` | 신규 생성 | 전사 배포 필수 |
| `README.md` | 전사 가이드 보강 | 문서 개선 |

---

## 검증 방법

1. `./setup.sh` 실행 → `~/.claude/plugins/cache/cowave-plugins/agents-utils/` 구조 확인
2. `~/.claude/settings.json`에 hooks가 머지되었는지 확인
3. `~/.claude/output-styles/learning-plus.md` 존재 확인
4. `~/.claude/CLAUDE.md`에 마커 블록 추가 확인
5. Claude Code 재시작 → 플러그인 로드 확인
6. `./setup.sh` 2회 실행 → 중복 없이 멱등 동작 확인
7. `./uninstall.sh` 실행 → 깔끔한 제거 확인
