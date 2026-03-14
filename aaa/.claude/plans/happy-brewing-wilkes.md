# Plane CLI 설계 및 구현 계획

## Context

Plane의 공식 MCP는 너무 무겁고 context를 낭비하고 있어, 가볍고 효율적인 CLI 도구를 만들고자 합니다. Google Workspace CLI(Rust/Clap)를 레퍼런스로 참고하되, Go/Cobra 기반으로 구현하여 빠른 개발과 간단한 배포를 추구합니다.

**확정 사항:**
- 언어: Go (Cobra/Viper)
- CLI 이름: `plane`
- 환경: Self-hosted 인스턴스 우선 (base URL 커스텀 필수)
- MVP: Core 5개 리소스 (project, issue, state, label, member) + config/auth

**Plane API 특징:**
- Base URL: 자체 호스팅 인스턴스 URL (예: `https://plane.example.com`)
- 인증: `X-API-Key` 헤더 또는 OAuth Bearer 토큰
- Rate limit: 60 req/min
- Pagination: cursor 기반 (`per_page` max 100)
- 20개 이상의 API 리소스, ~180개 엔드포인트

---

## 기술 스택

| 항목 | 선택 | 이유 |
|------|------|------|
| 언어 | Go 1.22+ | 정적 바이너리, 빠른 시작(~5ms), CLI 생태계 최적 |
| CLI 프레임워크 | Cobra | kubectl, gh, docker 등에서 검증됨 |
| 설정 관리 | Viper | Cobra와 완벽 통합, YAML+ENV+Flag 바인딩 |
| 테스트 | testify | assertion/mocking 지원 |
| 테이블 출력 | tablewriter | 가벼운 ASCII 테이블 렌더링 |
| Rate Limiting | golang.org/x/time | 공식 확장 라이브러리 |

**GWS CLI 대비 설계 차이점:**
- GWS는 Discovery Document 기반 동적 커맨드 → plane-cli는 정적 커맨드 (Plane에 discovery 서비스 없음, API 표면 유한)
- 정적 커맨드의 장점: 타입 안전 플래그, 정확한 help 텍스트, shell completion, 컴파일 타임 검증

---

## 커맨드 패턴

```
plane <resource> <action> [flags]
```

### 글로벌 플래그
```
--config string     설정 파일 경로 (기본: ~/.config/plane-cli/config.yaml)
--workspace string  워크스페이스 슬러그 오버라이드
--project string    프로젝트 ID 오버라이드
--format string     출력 형식: json (기본), table
--quiet             에러 외 출력 억제
--debug             HTTP 요청/응답 로깅
--base-url string   API base URL 오버라이드
```

### 핵심 커맨드 트리
```
plane
  config    init|set|get|list          설정 관리
  version                              버전 정보
  completion bash|zsh|fish             셸 자동완성

  user      me                         현재 사용자 조회
  project   list|get|create|update|delete
  issue     list|get|get-by-seq|search|create|update|delete
  state     list|get|create|update|delete
  label     list|get|create|update|delete
  cycle     list|get|create|update|delete|list-items|add-items|remove-item|transfer|archive|unarchive
  module    list|get|create|update|delete|list-items|add-items|remove-item|archive|unarchive
  member    list|list-project
  comment   list|get|create|update|delete
  link      list|get|create|update|delete
  activity  list|get
  page      create|get|create-workspace|get-workspace
  intake    list|get|create|update|delete
  worklog   list|get|create|update|delete|total
  initiative list|get|create|update|delete (+ labels, projects, epics 관리)
  epic      list|get
  customer  list|get|create|update|delete (+ properties, requests, linking)
  teamspace list|get|create|update|delete (+ members, projects)
  sticky    list|get|create|update|delete
```

---

## 디렉토리 구조

```
plane-cli/
  main.go                    # 진입점
  go.mod / go.sum
  Makefile                   # build, test, install, lint
  .goreleaser.yaml           # 크로스 플랫폼 릴리스
  .gitignore

  cmd/
    root.go                  # 루트 커맨드, 글로벌 플래그, config 로딩
    version.go               # plane version
    config.go                # plane config [init|set|get|list]
    completion.go            # 셸 자동완성 생성
    project/project.go       # project CRUD
    issue/issue.go           # issue CRUD + search + get-by-seq
    state/state.go           # state CRUD
    label/label.go           # label CRUD
    cycle/cycle.go           # cycle CRUD + 항목 관리 + archive
    module/module.go         # module CRUD + 항목 관리 + archive
    member/member.go         # member 조회
    comment/comment.go       # comment CRUD
    link/link.go             # link CRUD
    activity/activity.go     # activity 조회
    page/page.go             # page 관리
    intake/intake.go         # intake CRUD
    worklog/worklog.go       # worklog CRUD + total
    user/user.go             # user me
    initiative/initiative.go # initiative CRUD + 관계 관리
    epic/epic.go             # epic 조회
    customer/customer.go     # customer CRUD + properties + requests
    teamspace/teamspace.go   # teamspace CRUD + members + projects
    sticky/sticky.go         # sticky CRUD

  internal/
    api/
      client.go              # HTTP 클라이언트 (인증, rate limit, retry)
      pagination.go          # cursor 기반 페이지네이션
      errors.go              # API 에러 타입 및 파싱
      request.go             # 요청 빌더 (메서드, 경로 템플릿, 쿼리, 바디)
      response.go            # 응답 파싱

    config/
      config.go              # Viper 기반 설정 로딩/저장
      types.go               # Config 구조체
      path.go                # XDG 호환 경로 관리

    output/
      formatter.go           # Formatter 인터페이스
      json.go                # JSON 출력 (기본, 터미널 감지하여 pretty/compact)
      table.go               # 테이블 출력 (--format table)
      writer.go              # --quiet 지원

    models/
      project.go, issue.go, state.go, label.go, cycle.go, module.go,
      member.go, comment.go, link.go, activity.go, page.go, intake.go,
      worklog.go, user.go, initiative.go, epic.go, customer.go,
      teamspace.go, sticky.go, pagination.go, common.go

    cmdutil/
      factory.go             # DI 팩토리 (client, config, output 주입)
      flags.go               # 공통 플래그 헬퍼 (--project, --format 등)
      errors.go              # CLI 에러 포매팅

  test/
    fixtures/                # JSON 응답 fixture
    integration/             # 통합 테스트 (API 키 필요)
    mocks/                   # Mock API 클라이언트
```

---

## 핵심 설계

### 설정 우선순위 (높은 순)
1. CLI 플래그: `--workspace`, `--project` 등
2. 환경 변수: `PLANE_API_KEY`, `PLANE_WORKSPACE`, `PLANE_BASE_URL`
3. 설정 파일: `~/.config/plane-cli/config.yaml`
4. 기본값: base_url 없음 (self-hosted이므로 `plane config init`에서 필수 입력), format=`json`

### HTTP 클라이언트
- Path 템플릿: `workspaces/{workspace_slug}/projects/{project_id}/work-items/`
- 클라이언트 사이드 rate limiting: 55 req/min (안전 마진)
- `X-RateLimit-Remaining` 헤더 기반 서버 사이드 대응
- 30초 타임아웃, 자동 retry (429 응답시)

### API URL 계층
- **Workspace 레벨**: `GET /api/v1/workspaces/{slug}/...` → members, initiatives, stickies 등
- **Project 레벨**: `GET /api/v1/workspaces/{slug}/projects/{project_id}/...` → issues, states, labels 등
- **User 레벨**: `GET /api/v1/users/me/`

### 출력 포매팅
- **JSON (기본)**: 터미널→pretty-print, 파이프→compact, 스트리밍→NDJSON
- **Table**: `--format table` 각 리소스별 컬럼 정의
- **Quiet**: `--quiet` 생성/수정 시 ID만 출력 (스크립트 연계)

### 에러 UX (자기 치유형 메시지)
```
Error: Authentication failed (401)
  Your API key may be invalid or expired.
  Run `plane config init` to set up a new API key.
  Generate keys at: https://app.plane.so/profile/api-tokens/
```

---

## 구현 단계

### Phase 1: Foundation + MVP Core 5 (우선 구현)
1. Go 모듈 초기화, .gitignore, Makefile
2. `internal/config/` - Viper 기반 설정 (base URL 커스텀 필수, self-hosted 우선)
3. `internal/api/client.go` - HTTP 클라이언트 (인증, rate limit, 에러 처리)
4. `internal/api/request.go` - path 템플릿 요청 빌더
5. `internal/api/pagination.go` - cursor 기반 페이지네이션
6. `internal/api/errors.go` - API 에러 파싱
7. `internal/output/` - JSON(기본) + table 포매터
8. `internal/cmdutil/factory.go` - DI 팩토리
9. `cmd/root.go` - 루트 커맨드, 글로벌 플래그
10. `cmd/config.go` - `plane config init|set|get|list`
11. `cmd/version.go` - `plane version`
12. `cmd/user/user.go` - `plane user me`
13. `cmd/project/project.go` - project CRUD (list|get|create|update|delete)
14. `cmd/issue/issue.go` - issue CRUD + search + get-by-seq
15. `cmd/state/state.go` - state CRUD
16. `cmd/label/label.go` - label CRUD
17. `cmd/member/member.go` - member list|list-project
18. 단위 테스트 (httptest 기반 mock)

### Phase 2: Planning Resources
cycle, module 전체 구현 (CRUD + 항목 관리 + archive)
comment, link, activity 구현
auto-pagination (`--all`), shell completion

### Phase 3: Advanced Resources
page, intake, worklog, initiative, epic 구현
customer, teamspace, sticky 구현
`--dry-run`, `--fields`, `--expand` 플래그

### Phase 4: Polish & Distribution
GoReleaser 설정, Homebrew formula
README, CLAUDE.md 작성, 통합 테스트

---

## 검증 방법

1. `go build -o plane .` 빌드 확인
2. `plane config init` → API 키 입력 → `plane user me` 인증 확인
3. `plane project list` → 실제 프로젝트 목록 확인
4. `plane issue create --project <id> --name "Test"` → 이슈 생성 확인
5. `plane issue list --project <id> --format table` → 테이블 출력 확인
6. `plane issue list --project <id> | jq '.[]'` → 파이프 호환 확인
7. `go test ./...` 전체 테스트 통과
