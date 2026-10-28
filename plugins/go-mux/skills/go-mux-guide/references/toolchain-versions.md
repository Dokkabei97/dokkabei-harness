# Go 툴체인·버전 게이트 스페셜리스트 항목 (GO-VER)

같은 코드라도 "어떤 툴체인으로 빌드했나" 와 "main 모듈 go.mod 의 go 라인이 무엇인가" 에 따라 런타임 동작이 다르다.
항목을 적용하기 전에 프로젝트의 `go.mod`(go/toolchain 라인)와 CI·Dockerfile 의 빌드 이미지 버전을 먼저 확인한다.

---

### GO-VER-01 · 툴체인만 올리면 새 동작이 켜진다고 가정한다 — 실제로는 go.mod go 라인이 GODEBUG 기본값을 결정한다
- 적용: 툴체인 업그레이드, 신규 동작 기대(1.22 loopvar·ServeMux, 1.23 timer, 1.25 container GOMAXPROCS 등)
- 신호: Dockerfile 은 `golang:1.27` 인데 go.mod 는 `go 1.21`; "1.25 로 올렸는데 GOMAXPROCS 가 그대로"
- 메커니즘: 하위 호환을 위해 동작 변경은 GODEBUG 설정으로 도입되고, 기본값은 main 모듈 go.mod 의 `go` 라인 버전에 맞춰진다(예: `containermaxprocs=0` 은 언어 버전 1.24 이하의 기본값). 루프 변수 시맨틱(1.22)은 GODEBUG 가 아니라 *각 파일이 속한 모듈*의 go 라인으로 결정된다. 개별 재정의는 main 패키지의 `//go:debug name=value` 또는 go.mod `godebug` 블록.
- 처방: 업그레이드 시 go 라인을 함께 올리고 해당 버전 릴리스노트의 GODEBUG 표를 검토. 현재 적용값은 `go version -m <binary>` 의 `build DefaultGODEBUG=...` 로 확인.
- 반례: Go 1.27 부터는 *제거된* GODEBUG 를 go.mod/`//go:debug` 에 최종 기본값이 아닌 값으로 두면 빌드가 실패한다(예: `asynctimerchan=1`) — 옛 우회 설정을 정리해야 한다.
- 검증: `go version -m ./bin/app | grep DefaultGODEBUG`, `/sched/gomaxprocs:threads` 등 런타임 메트릭
- 근거: https://go.dev/doc/godebug · https://go.dev/doc/go1.27 (GODEBUG 절)

### GO-VER-02 · toolchain 지시어/GOTOOLCHAIN 을 몰라 CI 와 로컬의 실제 빌드 툴체인이 다르다
- 적용: Go 1.21+ 모듈
- 신호: go.mod 에 `toolchain go1.x.y` 라인; CI 로그에서 툴체인 자동 다운로드; 로컬과 CI 결과 차이
- 메커니즘: go 라인이 로컬 툴체인보다 높거나 `toolchain` 지시어가 있으면 `GOTOOLCHAIN=auto`(기본)에서 go 명령이 해당 툴체인을 내려받아 재실행한다. `GOTOOLCHAIN=local` 이면 대신 실패한다. 이미지 버전만 보고 "1.25 로 빌드됐다" 단정할 수 없다.
- 처방: 빌드 산출물의 `go version -m` 으로 실제 컴파일 버전 확인; 재현성을 원하면 toolchain 라인을 명시하고 CI 캐시에 포함.
- 반례: 폐쇄망 CI 는 자동 다운로드 불가 — `GOTOOLCHAIN=local` + 이미지 고정.
- 검증: `go version -m`
- 근거: https://go.dev/doc/toolchain

### GO-VER-03 · 신규 vet/린터 신호를 CI 에 넣지 않아 버전이 제공하는 무료 검사를 놓친다
- 적용: CI 에서 `go vet` 만 기본 실행하는 프로젝트
- 신호: CI 에 race 테스트·staticcheck 없음
- 메커니즘: 최근 버전 vet 에는 `waitgroup`(Add 위치), `hostport`(IPv6 미지원 주소 조립, 1.25), `stdversion`(go 라인보다 새 API 사용 — 1.27 부터 go test 에서 기본 실행) 등이 추가됐다. `-race` 는 동시성 버그(GO-MAP-08, GO-CON-13)를 잡는 유일한 런타임 검사다.
- 처방: CI 에 `go vet ./...`, `go test -race ./...`(최소 핵심 패키지), `staticcheck`/`golangci-lint`(bodyclose, copyloopvar, gosec G112 포함) 추가.
- 반례: `-race` 는 실행 시간·메모리를 크게 늘림 — 전체가 무거우면 핵심 패키지만.
- 검증: CI 로그
- 근거: https://go.dev/doc/go1.25 (Vet 절) · https://go.dev/doc/go1.27 · https://go.dev/doc/articles/race_detector
