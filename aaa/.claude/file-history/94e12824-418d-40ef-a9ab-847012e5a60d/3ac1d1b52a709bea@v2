# Plane CLI

Go/Cobra 기반 Plane 프로젝트 관리 CLI. Self-hosted 인스턴스 우선.

## Build & Test
```bash
make build          # 빌드 (ldflags 포함)
go vet ./...        # 정적 분석
go test ./... -v    # 테스트
./plane --help      # 도움말
```

## Architecture
- `main.go` → `cmd/root.go` (Cobra root + 글로벌 플래그)
- `cmd/<resource>/<resource>.go` - 각 리소스 커맨드 (21개)
- `internal/api/` - HTTP 클라이언트, rate limit (55 req/min), path builder
- `internal/config/` - Viper 기반 설정 (XDG 경로)
- `internal/output/` - JSON(기본)/table 출력 (text/tabwriter 사용)
- `internal/cmdutil/` - Factory DI, 공통 플래그, 에러 포매팅
- `internal/models/` - API 모델 구조체

## Conventions
- 리소스 커맨드 패턴: `func NewCmd(f *cmdutil.Factory) *cobra.Command`
- API 경로: `api.NewPath("workspaces/{workspace_slug}/...")` 체이닝
- 출력: `output.FormatRaw(f.Format, resp, columns)`
- 업데이트: `cmd.Flags().Changed("field")` 패턴으로 partial update
- Workspace-level 리소스: initiative, customer, teamspace, sticky
- Project-level 리소스: issue, state, label, cycle, module, epic 등

## Config
- 파일: `~/.config/plane-cli/config.yaml`
- 환경변수: `PLANE_API_KEY`, `PLANE_BASE_URL`, `PLANE_WORKSPACE`
- 우선순위: CLI 플래그 > 환경변수 > config.yaml > 기본값
