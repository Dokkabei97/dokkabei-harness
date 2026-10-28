# Go GC·메모리 스페셜리스트 항목 (GO-GC)

GC 는 "힙을 얼마나 자주 마킹하느냐(GOGC/GOMEMLIMIT)" × "한 번 마킹이 얼마나 비싼가(살아있는 포인터 메모리)" × "얼마나 할당하느냐(할당률)" 로 비용이 정해진다.
튜닝 노브보다 할당률·포인터 밀도 감소가 먼저다. 기준 문서: https://go.dev/doc/gc-guide

---

### GO-GC-01 · 컨테이너에서 GOMEMLIMIT 없이 GOGC 만으로 운영해 OOMKill 되거나 메모리를 과소 활용한다
- 적용: Go 1.19+, 메모리 limit 이 있는 컨테이너(k8s `resources.limits.memory`)
- 신호: 라이브 힙은 limit 의 절반 근처인데 OOMKilled; 또는 limit 대비 힙이 작은데 GC CPU 비중이 높음
- 메커니즘: GOGC=100 이면 다음 GC 목표 ≈ 라이브 힙 × 2 — 라이브 힙이 limit/2 를 넘으면 목표가 limit 을 넘어 OOM 가능. GOMEMLIMIT 은 런타임이 관리하는 전체 메모리(힙+스택+런타임 메타데이터 등)에 대한 소프트 상한으로, 근접하면 GOGC 와 무관하게 GC 를 더 자주 돌린다.
- 처방: `GOMEMLIMIT` 을 컨테이너 limit 의 약 90%(런타임이 모르는 cgo/mmap/스레드 스택 등을 위해 5~10% 여유)로 설정(`GOMEMLIMIT=900MiB` 또는 `debug.SetMemoryLimit`). GOGC 는 기본 유지가 출발점.
- 반례: limit 이 없는 환경(VM 단독 등)에서는 의미가 약함. cgo 비중이 큰 프로세스는 Go 가 모르는 메모리가 커서 여유를 더 둬야 함.
- 검증: `/gc/gomemlimit:bytes`, `/memory/classes/total:bytes`(runtime/metrics), 컨테이너 working set 과 비교
- 근거: https://go.dev/doc/gc-guide#Memory_limit · https://pkg.go.dev/runtime/debug#SetMemoryLimit

### GO-GC-02 · GOGC=off + GOMEMLIMIT 를 "GC 최소화" 묘수로 쓰다가 라이브 힙이 limit 에 근접하면 GC 스래싱
- 적용: GOMEMLIMIT 를 쓰는 모든 서비스, 특히 GOGC=off 조합
- 신호: 라이브 힙이 limit 에 다가가며 처리량 급락, GC CPU 가 약 50% 에 고정
- 메커니즘: limit 근처에서 런타임은 GC 를 연속 실행한다. 무한 스래싱을 막기 위해 GC CPU 를 약 50%(2×GOMAXPROCS CPU-초 윈도우)로 제한하는 limiter 가 있어, 그 이후에는 limit 을 넘겨 메모리를 늘린다(결국 OOM 일 수 있음). 즉 GOMEMLIMIT 은 OOM 방지 장치가 아니다.
- 처방: GOGC=off 는 라이브 힙 최대치가 limit 보다 충분히 작다는 근거(부하 테스트)가 있을 때만. 기본은 GOGC 유지 + GOMEMLIMIT. 경보: `/gc/limiter/last-enabled:gc-cycle` 변화, GC CPU 비중.
- 반례: 배치 잡처럼 라이브 힙 상한이 명확하고 짧게 끝나는 프로세스는 GOGC=off+limit 이 유효.
- 검증: 부하 테스트에서 라이브 힙 상한 측정, `gctrace`
- 근거: https://go.dev/doc/gc-guide#Suggested_uses

### GO-GC-03 · 컨테이너 CPU limit 과 GOMAXPROCS 불일치로 CFS 스로틀링 꼬리 지연이 생긴다
- 적용: Linux cgroup CPU limit(k8s `limits.cpu`)이 노드 코어 수보다 작은 배포
- 신호: CPU 사용률은 낮은데 p99 지연이 100ms 단위로 튐; cgroup `cpu.stat` 의 `nr_throttled` 증가
- 메커니즘: Go 1.24 이하는 GOMAXPROCS = 노드 논리 CPU 수라, limit 2 코어 컨테이너에서 64개 P 가 동시에 돌다 CFS 주기(기본 100ms) 할당량을 일찍 소진하고 스로틀된다(GC 워커도 P 수에 비례). Go 1.25 부터 Linux 에서 cgroup CPU 대역폭 limit 을 기본값에 반영(소수는 올림, 논리 CPU 가 2 이상이면 최소 2)하고 limit 변경 시 주기적으로 갱신한다. 단 main 모듈 go.mod `go` 라인이 1.25 이상이어야 기본 활성(1.24 이하는 `containermaxprocs=0`/`updatemaxprocs=0` 기본). CPU *request* 는 반영하지 않는다.
- 처방: go.mod `go 1.25`+ 로 올리고 `GOMAXPROCS` 환경변수를 지울 것(수동 설정 시 자동 기능 비활성). 그 이전 버전은 `go.uber.org/automaxprocs`. limit 없이 request 만 쓰는 배포는 필요 시 GOMAXPROCS 명시.
- 반례: CPU limit 을 두지 않는 정책(요청만 설정)에서는 자동 조정이 일어나지 않는다 — 기대하지 말 것.
- 검증: `/sched/gomaxprocs:threads`, 시작 로그에 `runtime.GOMAXPROCS(0)` 출력, `nr_throttled`
- 근거: https://go.dev/doc/go1.25 (Runtime 절) · https://pkg.go.dev/runtime (GOMAXPROCS 기본값 문단)

### GO-GC-04 · 할당을 줄이려면 어디서 힙 탈출하는지부터 봐야 하는데 감으로 최적화한다
- 적용: alloc_space 상위 함수가 핫 경로에 있을 때
- 신호: `-gcflags=-m` 미사용; "포인터 반환이 빠르다" 같은 통념 적용
- 메커니즘: 대표 탈출 원인 — (1) 포인터 반환/저장, (2) 인터페이스로 변환해 넘김(fmt/slog `...any` 인자 포함), (3) 인터페이스 메서드 호출 시 수신자/인자(정적 분석 불가), (4) 클로저 캡처 후 고루틴/저장, (5) 크기를 컴파일 타임에 모르는 `make`(Go 1.25+ 는 가변 크기 make 의 백킹 배열을 스택에 두는 경우가 늘었음), (6) 큰 객체. 참고로 Go 1.27 은 80바이트 미만 소형 할당 비용을 크기 특화 할당 루틴으로 최대 30% 줄였다 — 할당 "횟수" 감소가 여전히 1순위.
- 처방: `go build -gcflags='-m=2' ./pkg 2>&1 | grep escape` 로 원인 확인 → 값 반환/호출자 버퍼 전달(`AppendX(dst []byte, ...)` 패턴)/구체 타입 사용. PGO(GO-OBS-06) 는 핫 인터페이스 호출을 devirtualize 해 탈출을 줄일 수 있다.
- 반례: 탈출 제거가 큰 값 복사를 늘려 오히려 느려질 수 있음 — 벤치마크 필수.
- 검증: `-gcflags=-m`, `-benchmem` allocs/op
- 근거: https://go.dev/doc/gc-guide#Eliminating_heap_allocations · https://go.dev/doc/go1.25 (Compiler 절)

### GO-GC-05 · sync.Pool 을 잘못 써서 할당이 그대로이거나 메모리가 부푼다
- 적용: 버퍼/인코더 재사용
- 신호: `pool.Put(buf)` 에 `[]byte`/구조체 값 전달(staticcheck SA6002); 가끔 거대한 버퍼가 풀에 들어감; Get 후 리셋 누락
- 메커니즘: (1) 비포인터 값을 Put 하면 `any` 변환에서 매번 할당 — 풀의 의미가 사라짐. (2) 풀은 GC 마다 비워지되 Go 1.13+ victim 캐시로 한 사이클 더 유지 — 장기 캐시가 아님. (3) 큰 버퍼가 섞이면 풀에 남은 모든 객체가 최대 크기로 수렴해 메모리가 부푼다(encoding/json 등도 상한 초과 버퍼를 버림, golang/go#23199).
- 처방: `*bytes.Buffer`/`*[]byte` 같은 포인터 저장; Put 전 `cap` 상한 검사(예: 64KiB 초과 버림); Get 직후 Reset.
- 반례: 할당이 프로파일 상위가 아닌 곳의 Pool 은 복잡도만 늘림. 객체 상태 누수(이전 요청 데이터) 위험.
- 검증: alloc_space 프로파일, 상주 메모리 추이
- 근거: https://pkg.go.dev/sync#Pool · https://github.com/golang/go/issues/23199

### GO-GC-06 · 인터페이스 박싱 할당 — 로깅·메트릭 인자로 값을 넘길 때마다 힙 할당
- 적용: 핫 경로의 `slog.Info("...", "k", v)`, `fmt.Sprintf`, `[]any` 수집, 제네릭 대신 `any` API
- 신호: alloc 프로파일에 `runtime.convT64`/`convTstring`/`convT` 상위
- 메커니즘: 포인터 모양이 아닌 값을 인터페이스로 바꾸면 값 사본을 힙에 할당한다. 예외: 0값, 폭과 무관하게 256 미만인 정수 값과 단일 바이트 값(`convT16/32/64` 가 정적 배열 `staticuint64s` 를 재사용), 상수, 영 크기 값 등 런타임/컴파일러가 정적 저장소를 쓰는 경우.
- 처방: slog 는 타입 지정 `slog.Int/String/Duration` Attr 또는 `LogAttrs`; 레벨 비활성 시 계산 회피(`logger.Enabled`); 핫 경로 컨테이너는 제네릭 `[T any]` 로 구체화.
- 반례: 콜드 경로에서의 박싱은 무시해도 된다.
- 검증: `-benchmem`, alloc 프로파일의 convT*
- 근거: https://pkg.go.dev/log/slog#hdr-Performance_considerations

### GO-GC-07 · 포인터가 많은 장수 데이터 구조가 GC 마킹 비용을 지배한다
- 적용: 수십만~수백만 객체의 인메모리 그래프/트리/캐시, `[]*T`
- 신호: GC CPU 비중 큼, 할당률은 낮은데도 mark 시간이 길다
- 메커니즘: 마킹은 살아있는 객체 중 포인터를 포함하는 메모리를 모두 따라간다. 포인터 없는 객체(noscan span)는 스캔하지 않는다. `string`, slice, map, interface, `time.Time`(`*Location` 필드), `error` 는 모두 포인터를 포함한다.
- 처방: `[]*T` → `[]T`(연속 배열, 객체 수 1); 노드 링크를 포인터 대신 `int32` 인덱스로; 시각은 `int64` UnixNano 로 저장; 문자열 다수는 하나의 큰 `[]byte` + 오프셋.
- 반례: 인덱스 기반 설계는 가독성·안전성 비용이 크다 — GC 가 상위 병목임이 확인된 구조에만.
- 검증: CPU 프로파일 `scanobject`/`gcDrain` 비중, `gctrace` mark CPU
- 근거: https://go.dev/doc/gc-guide#Implementation-specific_optimizations

### GO-GC-08 · RSS 가 줄지 않는다고 메모리 누수로 오판하거나, ReadMemStats 를 고빈도 호출한다
- 적용: 메모리 대시보드/경보, 주기적 메트릭 수집
- 신호: RSS 기반 경보 오탐; 1초 주기 `runtime.ReadMemStats` 호출
- 메커니즘: 해제된 힙 페이지는 백그라운드 scavenger 가 점진적으로 OS 에 반환하므로 RSS 는 지연된다(GOMEMLIMIT 근접 시 적극 반환). `ReadMemStats` 는 stop-the-world 를 수반한다. `runtime/metrics`(Go 1.16+) 는 STW 없이 읽는다.
- 처방: 메트릭은 `runtime/metrics` — `/memory/classes/heap/objects:bytes`(라이브+미회수), `/memory/classes/heap/released:bytes`, `/gc/heap/goal:bytes`. 누수 판단은 heap 프로파일 inuse 의 시간 diff(`pprof -base`).
- 반례: 진짜 누수(고루틴 누수가 붙잡은 메모리 등)는 inuse 도 단조 증가한다 — 그건 GO-CON-01.
- 검증: 두 시점 heap 프로파일 `go tool pprof -base old.pb.gz new.pb.gz`
- 근거: https://pkg.go.dev/runtime/metrics · https://go.dev/doc/diagnostics

### GO-GC-09 · Go 1.26 Green Tea GC 기본 전환을 모르고 GC 튜닝 결과를 비교한다
- 적용: Go 1.25(실험, `GOEXPERIMENT=greenteagc`) / Go 1.26+(기본)
- 신호: 툴체인 업그레이드 후 GC CPU·지연 프로파일이 크게 변함
- 메커니즘: 작은 객체 마킹을 페이지(span) 단위로 묶어 지역성·확장성을 높인 수집기. 공식 기대치는 GC 집약 프로그램에서 GC 오버헤드 10~40% 감소, 최신 amd64(Ice Lake/Zen 4+)는 벡터 명령으로 약 10% 추가.
- 처방: GC 관련 튜닝(GOGC 상향 등)은 1.26 업그레이드 후 재측정해 불필요해진 설정을 제거. 회귀 시 `GOEXPERIMENT=nogreenteagc` 로 A/B(1.26 릴리스노트는 1.27 제거 예정이라 했으나 1.27.3 소스엔 `GreenTeaGC` 플래그가 남아 있음 — 사용 툴체인에서 확인).
- 반례: 큰 객체·포인터 희소 힙은 이득이 작을 수 있음.
- 검증: 업그레이드 전후 `/cpu/classes/gc/total:cpu-seconds` 비율
- 근거: https://go.dev/doc/go1.26 · https://go.dev/doc/go1.25

### GO-GC-10 · 중복 문자열/값이 대량으로 상주한다 — unique 패키지로 인터닝하지 않는다
- 적용: Go 1.23+, 로그/이벤트 파싱 결과의 반복 값(호스트명, 태그, 상태 문자열)을 장시간 보관
- 신호: heap 에서 같은 내용의 작은 문자열 다수; 수동 `map[string]string` 인터닝 테이블(영구 누수)
- 메커니즘: `unique.Make[T]` 는 정규화된 `Handle[T]` 를 반환하고 핸들 비교는 포인터 비교다. 내부는 약한 참조라 아무도 안 쓰는 값은 회수된다 — 수동 인터닝 맵의 무한 성장 문제가 없다.
- 처방: `h := unique.Make(s)`; 구조체 필드를 `unique.Handle[string]` 로 저장, 출력 시 `h.Value()`.
- 반례: 카디널리티가 높은(대부분 유일한) 값은 인터닝 비용만 추가.
- 검증: heap inuse 전후 비교
- 근거: https://pkg.go.dev/unique · https://go.dev/blog/unique

### GO-GC-11 · SetFinalizer 로 리소스 정리를 보장하려 한다
- 적용: 네이티브 핸들/파일/외부 리소스 래퍼
- 신호: `runtime.SetFinalizer(obj, ...)`; 순환 참조 객체에 파이널라이저
- 메커니즘: 파이널라이저는 실행 보장이 없고, 객체 해제를 최소 한 GC 사이클 지연시키며, 순환 참조에 걸리면 영원히 해제되지 않는다. Go 1.24 `runtime.AddCleanup` 은 객체 해제를 지연시키지 않고 순환 누수가 일반적으로 없으며 여러 개 부착 가능.
- 처방: 정리는 명시적 `Close()` + `defer`; 안전망이 필요하면 `runtime.AddCleanup`(1.24+). 캐시의 약한 참조는 `weak.Pointer`(1.24+).
- 반례: cleanup 역시 실행 시점·보장 없음 — 정확성 의존 금지.
- 검증: 테스트에서 `runtime.GC()` 후 cleanup 호출 여부(보조 확인만)
- 근거: https://go.dev/doc/go1.24 (runtime 절) · https://pkg.go.dev/runtime#AddCleanup · https://pkg.go.dev/weak

### GO-GC-12 · 힙 ballast(거대 []byte) 같은 Go 1.19 이전 트릭이 남아 있다
- 적용: 오래된 서비스의 main 초기화 코드
- 신호: `ballast := make([]byte, 10<<30)` + `runtime.KeepAlive`
- 메커니즘: ballast 는 GOGC 기반 목표 힙을 부풀려 GC 빈도를 줄이던 우회책. GOMEMLIMIT(1.19+) 이 같은 목적을 명시적으로 달성하며, ballast 는 메모리 회계(컨테이너 working set, 일부 도구)에 혼선을 준다.
- 처방: ballast 제거 → GOMEMLIMIT(+필요 시 GOGC 상향)로 대체.
- 반례: 없음(1.19+ 기준).
- 검증: 교체 전후 GC 빈도(`/gc/cycles/total:gc-cycles`)·지연
- 근거: https://go.dev/doc/gc-guide#Memory_limit

### GO-GC-13 · 구조체 필드 순서가 GC 스캔 길이와 패딩을 결정한다는 점을 놓친다
- 적용: 수백만 개 상주하는 구조체(캐시 엔트리, 그래프 노드), 슬라이스 원소 타입
- 신호: 포인터 필드(string, slice, *T)가 구조체 끝쪽에 있고 앞에 큰 스칼라 배열/숫자 필드; `fieldalignment` 경고
- 메커니즘: GC 는 값 안에서 마지막 포인터 위치까지만 스캔한다 — 포인터 필드를 앞에 모으면 스캔 범위가 줄어든다. 별개로 필드 정렬 순서는 패딩 바이트를 결정해(예: `bool,int64,bool` = 24B vs `int64,bool,bool` = 16B) 원소 수만큼 메모리가 곱해진다.
- 처방: 포인터 필드 먼저, 이후 큰 스칼라 → 작은 스칼라 순. `go run golang.org/x/tools/go/analysis/passes/fieldalignment/cmd/fieldalignment ./...` 로 후보 확인.
- 반례: 직렬화 순서/가독성이 중요한 DTO·소수 인스턴스 구조체에는 무의미 — 대량 상주 타입에만.
- 검증: `unsafe.Sizeof`, heap inuse 및 GC mark CPU 전후 비교
- 근거: https://go.dev/doc/gc-guide#Implementation-specific_optimizations · https://pkg.go.dev/golang.org/x/tools/go/analysis/passes/fieldalignment
