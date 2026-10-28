# Go 동시성 스페셜리스트 항목 (GO-CON)

고루틴 수명, context 전파, 타이머, 동기화 원시의 내부 동작에서 생기는 함정.
많은 동작이 main 모듈 go.mod 의 `go` 라인으로 게이트된다(GO-VER-01).

---

### GO-CON-01 · 결과 채널을 버퍼 없이 만들어, 호출자가 타임아웃으로 떠난 뒤 송신 고루틴이 영원히 막힌다
- 적용: `select { case r := <-ch: case <-ctx.Done(): }` 로 기다리는 비동기 호출
- 신호: goroutine 수(`/sched/goroutines:goroutines`)가 트래픽에 비례해 단조 증가; goroutine 프로파일에 같은 `chan send` 스택 다수
- 메커니즘: 수신자가 사라지면 언버퍼드 채널 송신은 영원히 블록되고, 고루틴이 붙잡은 스택·클로저·요청 데이터 전부가 누수된다.
- 처방: 단일 결과 채널은 `make(chan T, 1)`; 송신도 `select { case ch <- r: case <-ctx.Done(): }` 로 감쌈. 테스트에 `go.uber.org/goleak`; 운영 진단은 Go 1.27 정식화된 `goroutineleak` 프로파일(`/debug/pprof/goroutineleak`, 1.26 은 `GOEXPERIMENT=goroutineleakprofile`).
- 반례: goroutineleak 프로파일은 도달 불가능한 원시에 막힌 고루틴만 잡는다 — 전역 변수나 실행 중 고루틴 지역 변수로 도달 가능한 채널에 막힌 누수는 놓친다. goroutine 수 추이와 병행.
- 검증: 부하 전후 `go tool pprof http://.../debug/pprof/goroutine` diff, goleak
- 근거: https://go.dev/doc/go1.27 (goroutine leak profile) · https://pkg.go.dev/runtime/pprof

### GO-CON-02 · for-select 루프의 time.After / Timer 재사용 규칙을 버전별로 잘못 적용한다
- 적용: 이벤트 루프, 폴링·하트비트, 유휴 타임아웃 구현
- 신호: `for { select { case <-ch: case <-time.After(d): } }`; `if !t.Stop() { <-t.C }` 드레인 관용구; `len(t.C)` 폴링
- 메커니즘: Go 1.23 이전에는 멈추지 않은 Timer 가 발화 전까지 GC 되지 않아(Ticker 는 영영) 루프마다 쌓였다. 1.23+(go.mod `go 1.23` 이상)부터 참조 없는 Timer/Ticker 는 즉시 GC 대상이고 타이머 채널이 언버퍼드(동기)라 `Reset/Stop` 후 낡은 값이 오지 않는다. Go 1.27 은 `asynctimerchan` GODEBUG 를 제거해 go 라인과 무관하게 항상 동기 채널이다. 이 변화로 `len(t.C)`/`cap(t.C)` 는 0 이 되고 구식 `if !t.Stop() { <-t.C }` 는 블록될 수 있다.
- 처방: 1.23+ 에서는 드레인 없이 `t.Reset(d)` 만 사용; `len(t.C)` 대신 비차단 수신(`select default`). 고빈도 루프는 여전히 `time.After` 가 반복마다 Timer 를 할당하므로 `time.NewTimer` 하나를 `Reset` 해 재사용.
- 반례: 저빈도 루프의 `time.After` 는 1.23+ 에서 누수 문제가 없어 가독성 우선 가능.
- 검증: `-benchmem` 할당, goroutine/heap 프로파일의 `time.newTimer`
- 근거: https://go.dev/doc/go1.23 (Timer changes) · https://go.dev/doc/go1.27 (asynctimerchan 제거) · https://pkg.go.dev/time#Timer.Reset

### GO-CON-03 · Go 1.22 루프 변수 시맨틱이 go.mod 버전에 따라 다르다는 걸 모른다
- 적용: 클로저/고루틴/주소(`&v`)로 루프 변수를 캡처하는 코드, 여러 모듈 버전이 섞인 모노레포
- 신호: `for _, v := range xs { go func(){ use(v) }() }`; 1.21 이하 go 라인 모듈에서 마지막 값만 처리됨; 반대로 습관적 `v := v` 섀도잉
- 메커니즘: 반복별 새 변수는 해당 *파일이 속한 모듈*의 go.mod 가 `go 1.22` 이상일 때만 적용된다. 캡처되는 변수는 반복마다 힙 할당될 수 있다(캡처 안 되면 비용 없음).
- 처방: go 라인을 1.22+ 로 올리고 `v := v` 제거(`copyloopvar` 린터). 핫 루프에서 캡처가 반복별 할당을 만든다면 `-gcflags=-m` 로 확인.
- 반례: 라이브러리 모듈이 낮은 go 라인을 유지하면 그 모듈 코드엔 구 시맨틱 — 일괄 가정 금지.
- 검증: `go vet`(loopclosure 는 1.22+ 모듈에서 무의미), 테스트 `-race`
- 근거: https://go.dev/blog/loopvar-preview · https://go.dev/doc/go1.22

### GO-CON-04 · 요청 context 를 백그라운드 작업에 그대로 넘겨 응답 직후 작업이 취소된다 / 반대로 Background 로 끊어 추적·값을 잃는다
- 적용: 핸들러에서 감사 로그·이벤트 발행·캐시 갱신 같은 후속 작업을 비동기로 시작
- 신호: 간헐적 `context canceled` (클라이언트 끊김·핸들러 반환 직후); `context.Background()` 로 바꿔서 트레이스 ID 유실
- 메커니즘: `r.Context()` 는 클라이언트 연결 종료, HTTP/2 스트림 취소, 핸들러 반환 시 취소된다. Background 는 취소는 피하지만 trace span/값을 모두 버린다.
- 처방: `context.WithoutCancel(r.Context())`(Go 1.21) — 값은 유지, 취소·데드라인만 분리; 별도 타임아웃을 다시 건다. 취소 시 정리 동작은 `context.AfterFunc`(1.21).
- 반례: 요청과 생명주기를 같이해야 하는 작업(DB 쿼리 등)은 원래 ctx 를 써야 클라이언트 이탈 시 자원을 아낀다.
- 검증: 클라이언트 조기 종료 통합 테스트(httptest + 취소된 ctx)
- 근거: https://pkg.go.dev/context#WithoutCancel · https://pkg.go.dev/net/http#Request.Context

### GO-CON-05 · 어떤 타임아웃이 발동했는지 구분할 수 없어 장애 분석이 막힌다
- 적용: 여러 계층에서 데드라인을 거는 서비스(게이트웨이 → 서비스 → DB/ES)
- 신호: 로그가 전부 `context deadline exceeded` 로 동일
- 메커니즘: `ctx.Err()` 는 `Canceled`/`DeadlineExceeded` 두 값뿐이라 원인 정보가 없다. Go 1.20 `WithCancelCause`, 1.21 `WithTimeoutCause`/`WithDeadlineCause` 로 원인을 실어 `context.Cause(ctx)` 로 꺼낼 수 있다.
- 처방: 계층별 `context.WithTimeoutCause(ctx, d, errUpstreamES)`; 로깅 시 `context.Cause(ctx)` 기록.
- 반례: 단일 타임아웃만 있는 단순 경로는 불필요.
- 검증: 타임아웃 주입 테스트에서 Cause 확인
- 근거: https://pkg.go.dev/context#WithTimeoutCause

### GO-CON-06 · context.Value 를 의존성 주입·핫 경로 설정 조회에 쓴다
- 적용: 미들웨어 체인이 깊은 서비스
- 신호: 핸들러에서 `ctx.Value(key)` 로 DB/로거/설정을 꺼냄; 문자열 키 사용
- 메커니즘: context 는 부모 체인 연결 리스트라 Value 조회가 깊이에 비례(O(depth))하고 타입 안전성이 없다. 문자열 키는 패키지 간 충돌한다.
- 처방: 요청 범위 메타데이터(trace ID, 인증 주체)만 비공개 키 타입(`type ctxKey struct{}`)으로; 의존성은 생성자 주입.
- 반례: 없음.
- 검증: 코드 리뷰(staticcheck SA1029: 내장 타입 키 경고)
- 근거: https://pkg.go.dev/context#WithValue

### GO-CON-07 · errgroup 의 ctx 와 동시성 제한 의미를 잘못 이해한다
- 적용: `golang.org/x/sync/errgroup` 팬아웃
- 신호: `g, ctx := errgroup.WithContext(ctx)` 후 Wait 이후에도 그 ctx 를 사용; 수천 개 작업에 `g.Go` 무제한 호출
- 메커니즘: WithContext 의 파생 ctx 는 첫 에러뿐 아니라 *Wait 반환 시에도* 취소된다 — Wait 후 후속 호출에 쓰면 즉시 실패. `SetLimit(n)` 이 설정되면 `g.Go` 는 슬롯이 날 때까지 호출자를 블록한다(비차단은 `TryGo`). 제한 없는 팬아웃은 다운스트림(DB 풀, ES) 포화를 만든다.
- 처방: 파생 ctx 는 그룹 내부에서만; `g.SetLimit(n)` 으로 다운스트림 풀 크기에 맞춤. 에러가 필요 없는 단순 대기는 `sync.WaitGroup.Go`(Go 1.25).
- 반례: CPU 바운드 작업은 GOMAXPROCS 이상 병렬화해도 이득 없음.
- 검증: 다운스트림 풀 대기 메트릭(GO-DB-02), 부하 테스트
- 근거: https://pkg.go.dev/golang.org/x/sync/errgroup · https://pkg.go.dev/sync#WaitGroup.Go

### GO-CON-08 · RWMutex 가 항상 Mutex 보다 낫다고 가정한다 / 재귀 RLock 으로 교착된다
- 적용: 읽기 위주 공유 상태, 코어 수 많은 노드
- 신호: 짧은 임계구역에 RWMutex; mutex 프로파일에 `RUnlock`/`RLock` 경합; 같은 고루틴이 RLock 중 다시 RLock 하는 호출 경로
- 메커니즘: RLock/RUnlock 도 공유 카운터에 원자 연산을 하므로 코어가 많고 임계구역이 짧으면 캐시 라인 경합으로 Mutex 보다 느릴 수 있다. 또 대기 중인 Lock 이 있으면 새 RLock 이 막히므로, 재귀 RLock 은 writer 가 끼는 순간 교착된다(문서상 금지).
- 처방: 짧은 임계구역은 Mutex 로 먼저 측정; 읽기 압도적이면 `atomic.Pointer[T]` 로 불변 스냅샷 교체(copy-on-write); 재귀 락 경로 제거.
- 반례: 임계구역이 길고(I/O 없이 수 μs 이상) 읽기가 압도적이면 RWMutex 가 유리.
- 검증: mutex 프로파일, `-cpu=1,8,32` 벤치마크
- 근거: https://pkg.go.dev/sync#RWMutex

### GO-CON-09 · Mutex 기아 모드 전환(1ms)을 모르고 꼬리 지연을 해석한다
- 적용: 경합이 심한 Mutex
- 신호: 처리량이 갑자기 떨어지며 p99 가 평탄화; mutex 프로파일 상위
- 메커니즘: 대기자가 1ms 넘게 락을 못 얻으면 Mutex 는 기아 모드로 바뀌어 소유권을 대기열 앞 고루틴에 직접 넘긴다(새로 도착한 고루틴의 스핀·선점 금지). 공정성은 생기지만 처리량은 떨어진다.
- 처방: 근본 해결은 경합 감소 — 임계구역 축소, 키 샤딩, per-P/per-goroutine 누적 후 병합, 채널 대신 배치.
- 반례: 경합이 없으면 무관.
- 검증: mutex 프로파일, `/sync/mutex/wait/total:seconds`
- 근거: Go 소스 `sync/mutex.go` (starvationThresholdNs = 1e6) · https://pkg.go.dev/sync#Mutex

### GO-CON-10 · 원자 카운터·슬롯 배열의 false sharing
- 적용: 고루틴/워커별 카운터 배열, 샤딩된 락 배열, 링 버퍼 head/tail
- 신호: `counters [N]atomic.Int64` 를 워커 i 가 각자 갱신하는데 코어 증가에도 처리량 정체
- 메커니즘: 서로 다른 변수라도 같은 캐시 라인(x86-64 64B, 일부 ARM 128B)에 있으면 쓰기마다 라인이 코어 간 핑퐁한다. Intel 은 인접 라인 프리페처 때문에 128B 간격이 더 나은 경우도 있다.
- 처방: 슬롯마다 패딩 — `struct { v atomic.Int64; _ [56]byte }` 또는 `golang.org/x/sys/cpu.CacheLinePad`(아키텍처별 크기). 집계는 읽을 때 합산.
- 반례: 메모리 ×8 이상 증가 — 경합이 측정된 핫 카운터에만.
- 검증: `-cpu=1,4,16` 벤치마크 확장성 곡선, `perf c2c`(Linux)
- 근거: https://pkg.go.dev/golang.org/x/sys/cpu#CacheLinePad

### GO-CON-11 · 64비트 원자 연산을 일반 int64 필드에 써서 32비트 플랫폼/혼합 접근에서 깨진다
- 적용: `atomic.AddInt64(&s.n, 1)` 스타일 코드, 일부 경로는 비원자 읽기
- 신호: 구조체 중간의 int64 필드에 함수형 atomic 사용; `s.n` 을 락 없이 직접 읽는 코드
- 메커니즘: 32비트 플랫폼에서 64비트 원자 연산은 8바이트 정렬이 필요하나 구조체 필드는 보장되지 않는다. Go 1.19 `atomic.Int64` 등 타입은 정렬을 보장하고, 비원자 접근을 타입 수준에서 막는다.
- 처방: `atomic.Int64/Uint64/Bool/Pointer[T]` 타입 사용(값 복사는 `go vet` copylocks 가 경고).
- 반례: 없음.
- 검증: `-race`, `go vet`
- 근거: https://pkg.go.dev/sync/atomic#Int64 · https://pkg.go.dev/sync/atomic#pkg-note-BUG

### GO-CON-12 · 핸들러가 띄운 고루틴의 panic 은 recovery 미들웨어가 잡지 못해 프로세스 전체가 죽는다
- 적용: 핸들러/컨슈머 내부 `go func(){...}()`
- 신호: Recovery 미들웨어가 있는데도 `panic:` 로 파드 재시작
- 메커니즘: recover 는 같은 고루틴의 defer 에서만 동작한다. net/http 서버가 핸들러 고루틴 panic 은 로깅·연결 종료로 흡수하지만, 그 안에서 시작한 고루틴은 보호 밖이다.
- 처방: 백그라운드 고루틴 진입점에 공통 `safeGo(func())` 래퍼로 recover + 로깅 + 메트릭.
- 반례: recover 로 불변식이 깨진 상태를 계속 쓰면 더 나쁨 — 상태 오염 가능 영역은 크래시가 낫다.
- 검증: panic 주입 테스트
- 근거: https://go.dev/ref/spec#Handling_panics · https://pkg.go.dev/net/http#Handler

### GO-CON-13 · WaitGroup.Add 를 고루틴 안에서 호출해 Wait 이 먼저 통과한다
- 적용: 수동 WaitGroup 사용 코드
- 신호: `go func(){ wg.Add(1); defer wg.Done() ... }()`
- 메커니즘: Add 가 Wait 보다 늦게 실행되면 Wait 은 카운터 0 을 보고 즉시 반환한다(경쟁 조건). Go 1.25 는 `WaitGroup.Go` 를 추가했고 vet 에 잘못된 Add 위치를 보고하는 `waitgroup` 분석기를 넣었다.
- 처방: `wg.Go(func(){ ... })`(1.25+), 그 이전은 고루틴 시작 *전* Add.
- 반례: 없음.
- 검증: `go vet`, `-race`
- 근거: https://go.dev/doc/go1.25 · https://pkg.go.dev/sync#WaitGroup.Go

### GO-CON-14 · 타이밍 의존 동시성 테스트를 time.Sleep 으로 작성해 느리고 플래키하다
- 적용: 타임아웃·재시도·캐시 만료·rate limiter 테스트
- 신호: 테스트에 `time.Sleep(100*time.Millisecond)`; CI 에서 간헐 실패
- 메커니즘: `testing/synctest`(Go 1.25 정식)는 격리된 bubble 안에서 시간을 가상화해, 모든 고루틴이 블록되면 가짜 시계를 즉시 전진시킨다. Go 1.27 은 `synctest.Sleep`(Sleep+Wait)과 인메모리 네트워크용 `httptest.NewTestServer` 를 추가했다.
- 처방: `synctest.Test(t, func(t *testing.T){ ... synctest.Wait() ... })`.
- 반례: 실제 I/O(외부 DB, 실소켓)를 기다리는 테스트는 bubble 안에서 "블록됨"으로 간주되지 않아 시계가 전진하지 않는다.
- 검증: `-count=100 -race` 안정성
- 근거: https://pkg.go.dev/testing/synctest · https://go.dev/blog/synctest · https://go.dev/doc/go1.27
