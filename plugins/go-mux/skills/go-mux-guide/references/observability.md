# Go 관측·프로파일링 스페셜리스트 항목 (GO-OBS)

"추측하지 말고 측정" 을 실제로 하려면 프로파일 종류별 의미·기본 비활성 설정·샘플링 특성을 알아야 한다.

---

### GO-OBS-01 · heap 프로파일의 inuse 와 alloc 을 혼동해 엉뚱한 곳을 최적화한다
- 적용: 메모리 사용량/GC 비용 조사
- 신호: "메모리 많이 먹는 함수" 를 찾으려다 `allocs` 프로파일을 보거나, GC 빈도 원인을 찾으려다 `heap` inuse 만 봄
- 메커니즘: 같은 힙 프로파일에 4개 샘플 인덱스가 있다 — `inuse_space/inuse_objects`(마지막 GC 시점 살아있는 것: 상주 메모리·누수 조사), `alloc_space/alloc_objects`(시작 이후 누적 할당: GC 압력·할당률 조사). `/debug/pprof/allocs` 와 `/heap` 은 같은 데이터에 기본 인덱스만 다르다. 샘플링은 평균 512KiB 마다 1회(`runtime.MemProfileRate`)라 작은 할당도 통계적으로 잡힌다.
- 처방: 누수/상주 → `go tool pprof -sample_index=inuse_space`, 시점 비교는 `-base`; GC CPU 감소 → `-sample_index=alloc_space`(또는 alloc_objects: GC 비용은 객체 수에도 비례).
- 반례: MemProfileRate 를 1 로 낮추는 것은 테스트 한정 — 운영에선 오버헤드 큼.
- 검증: 최적화 전후 `-benchmem` 과 프로파일 상위 비교
- 근거: https://go.dev/doc/diagnostics · https://pkg.go.dev/runtime#MemProfileRate

### GO-OBS-02 · CPU 프로파일에서 안 보이는 대기 시간(락·채널·I/O)을 CPU 프로파일로 찾으려 한다
- 적용: CPU 사용률은 낮은데 지연이 큰 서비스
- 신호: CPU 프로파일이 평평한데 p99 가 큼
- 메커니즘: CPU 프로파일(기본 100Hz)은 on-CPU 시간만 샘플한다. 블록된 시간은 block 프로파일, 락 경합은 mutex 프로파일, 스케줄링 지연·GC 일시정지·syscall 은 execution trace 에 나타난다.
- 처방: 대기 원인 → GO-OBS-03(block/mutex) 또는 GO-OBS-04(trace). `/sched/latencies:seconds`(runtime/metrics)로 runnable 대기 분포 확인.
- 반례: 없음.
- 검증: 프로파일 종류별 상위 항목과 지연 상관
- 근거: https://go.dev/doc/diagnostics

### GO-OBS-03 · mutex/block 프로파일이 기본 비활성이라 빈 결과를 "경합 없음" 으로 해석한다
- 적용: net/http/pprof 를 켜 둔 서비스
- 신호: `/debug/pprof/mutex`, `/debug/pprof/block` 결과가 비어 있음
- 메커니즘: `runtime.SetMutexProfileFraction`, `runtime.SetBlockProfileRate` 기본값 0 = 수집 안 함. block 프로파일 rate 는 임계값이 아니라 샘플링 비율이다 — 블록된 시간 rate ns 당 평균 1개 이벤트를 샘플하며, rate 보다 짧은 이벤트도 지속 시간에 비례한 확률로 잡힌다(짧은 블록이 안 보이는 게 아님). rate=1 은 모든 블록 이벤트 — 오버헤드 큼.
- 처방: 운영은 `runtime.SetMutexProfileFraction(100)`(1/100 샘플), `runtime.SetBlockProfileRate(int((10*time.Microsecond).Nanoseconds()))` 같은 보수적 값으로 시작; 진단 시간에만 올림. 총량 지표는 `/sync/mutex/wait/total:seconds`.
- 반례: 고빈도 채널 경로에서 낮은 block rate 는 측정 자체가 성능을 왜곡.
- 검증: 활성화 전후 처리량 차이가 오차 범위인지 확인
- 근거: https://pkg.go.dev/runtime#SetMutexProfileFraction · https://pkg.go.dev/runtime#SetBlockProfileRate

### GO-OBS-04 · 간헐적 지연 스파이크를 프로파일 평균으로 쫓는다 — 실행 트레이스/플라이트 레코더를 안 쓴다
- 적용: 수 초에 한 번 튀는 p99.9, GC/스케줄러/시스템콜 상호작용 의심
- 신호: 프로파일 상위는 정상인데 간헐 스파이크 지속
- 메커니즘: `runtime/trace` 는 고루틴 상태 전환·GC 단계·P 사용·syscall 을 시간축으로 기록한다(Go 1.21+ 에서 오버헤드 대폭 감소). Go 1.25 `trace.FlightRecorder` 는 메모리 링 버퍼에 계속 기록하다가 이상 징후 시 `WriteTo` 로 최근 몇 초만 덤프한다.
- 처방: 지연 SLO 위반 감지 시 FlightRecorder 스냅샷 저장 → `go tool trace` 로 분석. 구간 식별은 `trace.WithRegion`/`trace.NewTask`. (Go 1.27 `go tool trace -http=:port` 는 localhost 에만 바인딩)
- 반례: 상시 전체 트레이스 파일 기록은 용량 부담 — 플라이트 레코더로 대체.
- 검증: 스파이크 시점 트레이스에서 GC STW/assist, runnable 대기 확인
- 근거: https://pkg.go.dev/runtime/trace#FlightRecorder · https://go.dev/blog/flight-recorder · https://go.dev/doc/go1.27

### GO-OBS-05 · GC assist 가 요청 지연을 만든다는 걸 gctrace 로 확인하지 않는다
- 적용: 할당률 높은 API 서버의 지연 분석
- 신호: CPU 프로파일에 `runtime.gcAssistAlloc` 상위; GC 주기와 지연 스파이크 상관
- 메커니즘: 동시 마킹 중 할당이 빠르면 런타임은 할당하는 고루틴에게 마킹 작업(assist)을 떠넘긴다 — 요청 고루틴이 직접 GC 일을 하므로 지연에 반영된다. `GODEBUG=gctrace=1` 은 GC 마다 힙 크기·목표·단계별 wall/CPU 시간(assist 포함)을 stderr 에 출력한다.
- 처방: 근본은 할당률 감소(GO-GC-04~06). 임시로 GOGC 상향/GOMEMLIMIT 여유 확대로 GC 빈도 축소.
- 반례: GOGC 상향은 메모리 피크를 키움 — 컨테이너 limit 과 함께 판단(GO-GC-01).
- 검증: `gctrace` 의 assist CPU, `/cpu/classes/gc/mark/assist:cpu-seconds`
- 근거: https://go.dev/doc/gc-guide · https://pkg.go.dev/runtime#hdr-Environment_Variables

### GO-OBS-06 · PGO 를 쓰지 않거나, 대표성 없는 프로파일로 PGO 빌드한다
- 적용: Go 1.21+ CPU 바운드 서비스(직렬화·검색 결과 가공·게이트웨이)
- 신호: `default.pgo` 없음; 벤치마크 한 개 프로파일로 빌드
- 메커니즘: main 패키지 디렉터리의 `default.pgo` 를 `-pgo=auto`(1.21+ 기본)가 자동 사용한다. 핫 함수 인라이닝과 인터페이스 호출 devirtualization 이 주 효과로, 릴리스노트 기준 대표 프로그램에서 2~14%(1.22) 향상. 소스가 조금 바뀌어도 프로파일은 대부분 유효하다.
- 처방: 운영 CPU 프로파일 여러 개를 `go tool pprof -proto a.pprof b.pprof > default.pgo` 로 병합해 커밋, 주기적 갱신.
- 반례: 운영 트래픽과 다른 프로파일은 엉뚱한 경로를 최적화하고 빌드 시간·바이너리 크기만 늘린다.
- 검증: PGO 유무 바이너리로 동일 부하 CPU 비교
- 근거: https://go.dev/doc/pgo

### GO-OBS-07 · 마이크로벤치마크가 측정 대상을 컴파일러가 제거한 상태를 잰다 / 1회 실행으로 결론낸다
- 적용: 성능 개선 PR 의 근거 벤치마크
- 신호: `for i := 0; i < b.N; i++ { f(x) }` 결과를 버림; `-count` 없이 한 번 실행한 수치 비교
- 메커니즘: 결과를 쓰지 않으면 인라인 후 계산이 제거돼 비현실적 ns/op 이 나온다. Go 1.24 `b.Loop()` 는 루프 본문의 인자·결과를 살려 두고, 셋업을 `-count` 당 1회만 실행한다. 단일 실행은 노이즈(CPU 주파수, 다른 프로세스)에 취약.
- 처방: `for b.Loop() { ... }` + `b.ReportAllocs()`; `go test -bench=X -count=10 > old.txt` 후 `benchstat old.txt new.txt` 로 유의성 확인.
- 반례: 마이크로벤치 개선이 실제 서비스 개선을 보장하지 않음 — 최종 판단은 운영 프로파일.
- 검증: benchstat 의 p-value/변동폭
- 근거: https://pkg.go.dev/testing#B.Loop · https://pkg.go.dev/golang.org/x/perf/cmd/benchstat

### GO-OBS-08 · goroutine 프로파일을 debug=2 덤프 한 번만 보고 누수를 판단한다
- 적용: 고루틴 수 증가 조사
- 신호: 수만 개 스택 텍스트를 눈으로 훑음
- 메커니즘: `/debug/pprof/goroutine` 은 pprof 형식으로 받으면 동일 스택이 합산돼 상위가 바로 보이고, 두 시점 `-base` diff 로 "증가한 스택" 만 남길 수 있다. Go 1.27 는 `goroutineleak` 프로파일로 영구 블록 고루틴을 직접 보고한다(GO-CON-01). Go 1.27 은 go 라인 1.27+ 모듈에서 traceback 헤더에 pprof goroutine 라벨도 출력한다(`tracebacklabels=0` 으로 끔).
- 처방: `go tool pprof -base t0.pb.gz t1.pb.gz` 로 증가분 확인; 요청 유형별 라벨은 `pprof.Do(ctx, pprof.Labels(...))`.
- 반례: 라벨에 민감정보(사용자 ID 등)를 넣으면 traceback/프로파일로 노출.
- 검증: diff 상위 스택이 트래픽과 비례하는지
- 근거: https://pkg.go.dev/runtime/pprof · https://go.dev/doc/go1.27
