# Go 테스트 함정

적용 전 확인: `go.mod` 의 `go` 디렉티브(언어 버전 의미론을 결정 — 툴체인 버전이 아님), CI 의 `go test` 플래그.
벤치마크·`-race` 운용·`b.Loop` 는 `go-mux-guide` 레퍼런스(observability, toolchain-versions) 참조.

### TST-GO-01 · `go test ./...` 의 "ok (cached)" 는 DB·네트워크 변화를 모른다
- 적용: 패키지 목록 모드(`go test ./...`, `go test ./pkg`)로 실행하는 모든 테스트
- 신호: 출력에 `(cached)`, 스키마·외부 서비스를 바꿨는데 결과가 그대로
- 메커니즘: 성공한 패키지 결과는 테스트 바이너리·플래그·테스트가 읽은 파일/환경변수가 같으면 캐시에서 재생된다. 네트워크·DB·컨테이너 상태는 캐시 키가 아니다.
- 처방: RED 확인과 통합 테스트는 `-count=1`. CI 의 통합 잡도 `-count=1`. `go clean -testcache` 는 전체 무효화.
- 반례: 순수 단위 테스트는 캐시가 이득 — 단위/통합 잡을 빌드 태그나 디렉터리로 분리.
- 검증: 출력의 `(cached)` 유무.
- 근거: https://pkg.go.dev/cmd/go#hdr-Test_packages

### TST-GO-02 · table test 의 루프 변수 캡처는 `go.mod` 의 `go` 라인이 1.22 미만이면 여전히 버그
- 적용: `for _, tc := range tests { t.Run(..., func(t *testing.T) { t.Parallel(); ... tc ... }) }`
- 신호: 모든 서브테스트가 마지막 케이스 값으로 실행됨, 실패해야 할 케이스가 그린
- 메커니즘: 반복마다 새 변수를 만드는 의미론은 Go 1.22 부터이고, **모듈의 `go` 디렉티브**가 1.22 이상일 때만 적용된다. 최신 툴체인으로 빌드해도 `go 1.21` 모듈은 옛 의미론.
- 처방: `go` 디렉티브를 1.22+ 로 올리거나, 그 전까지 `tc := tc` 유지. 1.22+ 모듈에선 `tc := tc` 는 불필요(linter `copyloopvar` 가 지적).
- 반례: 1.22+ 모듈에서 `tc := tc` 를 "안전하게" 남기는 것은 무해하지만 노이즈.
- 검증: `go.mod` 확인, 케이스마다 고유 실패를 넣어 RED 확인.
- 근거: https://go.dev/blog/loopvar-preview · https://go.dev/doc/go1.22#language

### TST-GO-03 · `t.Setenv`/`t.Chdir` 는 병렬 테스트에서 panic — 전역 상태 신호다
- 적용: `t.Parallel()` 과 같은 테스트(또는 조상)에서 `t.Setenv`, Go 1.24+ `t.Chdir`
- 신호: 병렬 테스트(또는 병렬 조상을 가진 테스트)에서 `t.Setenv`/`t.Chdir` 호출 시 panic
- 메커니즘: 환경변수·작업 디렉터리는 프로세스 전역이라 병렬과 양립 불가 — 런타임이 막는다.
- 처방: 설정을 env 에서 직접 읽지 말고 구조체로 주입해 테스트에서 값을 넘긴다. env 파싱 자체는 비병렬 테스트 하나로.
- 반례: 진짜로 env 해석을 검증하는 테스트는 비병렬이 맞다.
- 검증: `go test -run X -v`.
- 근거: https://pkg.go.dev/testing#T.Setenv · https://pkg.go.dev/testing#T.Chdir

### TST-GO-04 · 패키지끼리도 병렬이다 — `t.Parallel()` 없이도 공유 DB 에서 충돌
- 적용: 여러 패키지의 통합 테스트가 같은 DB/인덱스/버킷을 쓰는 경우
- 신호: 패키지 단독 실행은 그린, `./...` 실행에서 간헐 실패
- 메커니즘: `go test` 는 패키지 바이너리를 `-p`(기본 GOMAXPROCS) 개까지 동시에 실행한다. `t.Parallel()` 은 패키지 내부 병렬일 뿐.
- 처방: 패키지별 고유 스키마/DB 이름/인덱스 접두어(`TestMain` 에서 생성·정리), 또는 통합 잡만 `-p 1`. 순서 의존 탐지는 `-shuffle=on`(시드가 출력되므로 `-shuffle=<seed>` 로 재현).
- 반례: `-p 1` 은 전체를 직렬화해 느려진다 — 격리가 우선.
- 검증: `go test -count=1 -p 8 ./...` 반복 실행.
- 근거: https://pkg.go.dev/cmd/go#hdr-Testing_flags

### TST-GO-05 · 타이머·타임아웃 로직은 `testing/synctest` 로 가짜 시계에서
- 적용: Go 1.25+ (`synctest.Test`), 타임아웃·재시도·캐시 만료·ticker 로직
- 신호: 테스트에 `time.Sleep`, 느리거나 CI 에서만 flaky 한 타이밍 테스트
- 메커니즘: `synctest.Test` 는 격리된 bubble 안에서 함수를 실행하고, bubble 의 시계는 모든 고루틴이 durably blocked 일 때만 전진한다. `synctest.Wait` 는 다른 고루틴이 모두 block 될 때까지 대기. 뮤텍스 대기와 실제 네트워크 I/O 는 durably blocked 가 아니다.
- 처방: 시간 의존 코드를 bubble 안에서 실행, 실제 소켓 대신 `net.Pipe` 같은 인메모리 연결. bubble 안에서 `t.Run`/`t.Parallel` 금지.
- 반례: 1.25 미만 모듈이거나 실제 I/O 가 본질인 테스트 — `Clock` 인터페이스 주입이 대안.
- 검증: 테스트 wall time 이 시뮬레이션 시간과 무관하게 짧아졌는지.
- 근거: https://pkg.go.dev/testing/synctest · https://go.dev/blog/synctest

### TST-GO-06 · 기본 커버리지는 "테스트 중인 패키지"만 센다
- 적용: `go test -cover`, 레이어(handler→service→repo)가 패키지로 나뉜 구조, 바이너리 수준 E2E
- 신호: handler 테스트로 service 코드를 실행했는데 service 커버리지는 0%
- 메커니즘: 기본은 테스트 대상 패키지만 계측. 다른 패키지 코드는 `-coverpkg` 로 지정해야 집계된다. 실행 바이너리(통합/E2E)는 Go 1.20+ `go build -cover` 로 빌드하고 `GOCOVERDIR` 에 데이터를 남긴다.
- 처방: `go test -coverpkg=./... -coverprofile=c.out ./...`; E2E 는 `go build -cover -o app` → `GOCOVERDIR=dir ./app` → `go tool covdata percent -i=dir`.
- 반례: `-coverpkg=./...` 수치는 "어딘가에서 실행됨"이라 단위 테스트 품질 지표로는 과대평가.
- 검증: 두 방식의 수치 비교.
- 근거: https://go.dev/doc/build-cover · https://pkg.go.dev/cmd/go#hdr-Testing_flags

### TST-GO-07 · 테스트 컨텍스트는 `t.Context()` — Cleanup 직전에 취소된다
- 적용: Go 1.24+, 테스트에서 고루틴·서버·컨슈머를 띄우는 경우
- 신호: `context.Background()` 로 띄운 고루틴이 테스트 종료 후에도 살아 다음 테스트에 로그·부작용
- 메커니즘: `T.Context` 는 `t.Cleanup` 함수들이 호출되기 직전에 취소되는 컨텍스트를 준다 → cleanup 에서 종료 대기를 걸 수 있다.
- 처방: 테스트 안 장수명 작업은 `t.Context()` 기반으로 시작하고 `t.Cleanup` 에서 종료(WaitGroup) 확인.
- 반례: 1.24 미만은 `ctx, cancel := context.WithCancel(...)` + `t.Cleanup(cancel)`.
- 검증: goleak 같은 누수 검사기 또는 `runtime.NumGoroutine` 비교.
- 근거: https://pkg.go.dev/testing#T.Context
