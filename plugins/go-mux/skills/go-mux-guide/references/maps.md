# Go map 스페셜리스트 항목 (GO-MAP)

맵 선택·용량·메모리·GC 비용에서 강한 시니어도 놓치는 함정. 각 항목은 ID 로 project-rules 가 선별할 수 있다.
"map 은 O(1)" 은 평균 해시 비용 기준이다 — 해시 계산(키 길이 비례), 캐시 미스, 성장 시 재배치, GC 스캔 비용이 상수에 숨어 있다.

---

### GO-MAP-01 · 크기를 아는 맵을 make(map[K]V) 로 만들어 성장 재배치를 반복한다
- 적용: 루프로 N개(대략이라도)를 채우는 맵 — 역직렬화 결과 인덱싱, 그룹핑, 조인용 룩업 테이블
- 신호: `m := map[K]V{}` 직후 `for _, x := range xs { m[k(x)] = ... }`; pprof alloc_space 에서 `runtime.growslice` 대신 `runtime.(*table).grow`/`hashGrow`/`mapassign` 하위 할당이 상위
- 메커니즘: 용량 힌트 없이 시작하면 적재율 한계마다 테이블을 2배로 키우며 엔트리를 재배치한다. Go 1.24+ Swiss Table 은 테이블당 최대 1024 엔트리로 쪼개 한 번에 1024개만 옮기지만(지연 스파이크 완화), 총 재해시·할당 횟수는 그대로다.
- 처방: `m := make(map[K]V, len(xs))`. 정확하지 않아도 상한/추정치를 주면 대부분의 성장을 제거한다.
- 반례: 대부분 비어 있는 채로 끝나는 맵에 큰 힌트 → 쓰지 않는 메모리를 미리 잡는다(힌트는 즉시 할당된다). 맵이 다시 줄지 않으므로(GO-MAP-02) 과대 힌트는 영구 비용.
- 검증: `go test -bench . -benchmem` 에서 allocs/op·B/op 비교, pprof `-sample_index=alloc_space`
- 근거: https://go.dev/blog/swisstable · https://go.dev/ref/spec#Making_slices_maps_and_channels

### GO-MAP-02 · delete 해도 맵은 줄지 않는다 — 큰 일회성 피크 후 메모리가 그대로 남는다
- 적용: 세션/연결/요청 ID 를 키로 넣고 빼는 장수 맵, 버스트 후 대부분 삭제되는 캐시. Go 1.24 Swiss Table 포함 모든 버전
- 신호: 엔트리 수(len)는 작은데 heap inuse 가 피크 수준에 머무름; heap 프로파일 inuse_space 에서 맵 할당 지점이 상위; len 이 작은 맵의 range 인데 CPU 프로파일에 `mapiternext`/`Iter.Next` 가 상위
- 메커니즘: 런타임 맵은 축소(shrink)를 구현하지 않는다(golang/go#20135 Open; 1.27 소스 `internal/runtime/maps/map.go` 에도 `TODO: shrink directory?` 만 있음). 삭제는 슬롯을 비우거나 tombstone 으로 표시할 뿐 버킷/그룹 배열을 반환하지 않는다. `clear(m)`(Go 1.21)도 용량을 유지한다. 그래서 range·clear 비용도 len 이 아니라 피크 용량에 비례한다 — 실측(Go 1.27.3, arm64): 4M 엔트리를 채운 뒤 10개만 남기면 range 1회 ≈ 8ms, 새 10엔트리 맵은 수백 ns(수만 배). 이런 맵을 핫 루프에서 순회하면 메모리보다 CPU 로 먼저 드러난다. 처방(새 맵 복사)이 두 증상을 함께 해소한다.
- 처방: 피크 이후 주기적으로 새 맵에 복사해 교체 — `n := make(map[K]V, len(m)); maps.Copy(n, m); m = n`(교체 시점은 락으로 보호). 키 수명이 짧으면 세대(generation) 맵 2개를 회전시키는 방식도 유효.
- 반례: 크기가 안정적으로 유지되는 맵은 복사 비용만 추가된다. 재사용 목적이면 오히려 `clear(m)` 으로 용량을 유지하는 편이 할당이 적다.
- 검증: 부하 버스트 → 삭제 → `runtime.GC()` 후 `/memory/classes/heap/objects:bytes`(runtime/metrics) 비교
- 근거: https://github.com/golang/go/issues/20135 · https://pkg.go.dev/builtin#clear

### GO-MAP-03 · Go 1.24 Swiss Table 전환을 모른 채 맵 벤치마크/튜닝 결론을 이전 버전에서 가져온다
- 적용: Go 1.24+ 로 빌드하는 서비스(go.mod go 라인과 무관하게 툴체인 기준)
- 신호: "map 대신 slice 선형 탐색이 빠르다", "맵 미리 크게 잡아라" 같은 사내 규칙의 근거 벤치마크가 1.23 이하 결과
- 메커니즘: 1.24 맵은 8슬롯 그룹 + 그룹당 64비트 제어 워드(슬롯당 1바이트, 해시 하위 7비트)로 한 번에 8슬롯을 비교한다. 맵은 독립 테이블(최대 1024 엔트리) 여러 개로 나뉘는 extendible hashing 이다. 공식 수치: 마이크로벤치 최대 60% 빨라짐(일부 회귀), 전체 앱 기하평균 CPU 약 1.5% 개선. 반복 중 수정 의미론(삭제된 미방문 엔트리는 안 나옴, 추가 엔트리는 나올 수도)은 동일.
- 처방: 맵 관련 성능 판단은 현재 툴체인에서 재측정. 회귀 의심 시 1.24/1.25 에서는 `GOEXPERIMENT=noswissmap` 빌드로 A/B 가능(1.27 툴체인 소스 `internal/goexperiment` 에는 해당 플래그가 없음 — 구 구현 제거).
- 반례: 옵트아웃을 운영 기본값으로 두지 말 것 — 비교용 일시 조치.
- 검증: `benchstat` 로 두 빌드의 `-count=10` 결과 비교
- 근거: https://go.dev/blog/swisstable · https://go.dev/doc/go1.24#runtime

### GO-MAP-04 · 집합에 map[K]bool 대 map[K]struct{} 를 메모리 최적화로 착각하고, 진짜 큰 절감(비트셋)을 놓친다
- 적용: 멤버십 집합. 특히 키가 작은 정수 범위(ID 0..N, enum, 포트 등)일 때
- 신호: `map[int]bool` / `map[uint32]struct{}` 에 수십만~수백만 개의 조밀한 정수 키
- 메커니즘: 1.24+ Swiss Table 의 슬롯은 `struct{key; elem}` 이고 끝의 0크기 필드는 패딩되므로, 4/8바이트 키에서는 `struct{}` 와 `bool` 값의 엔트리당 크기가 같다 — 실측(Go 1.27.3, 1M 엔트리): `map[int64]bool` 36.1 B ≈ `map[int64]struct{}` 36.1 B, `map[int32]` 쪽도 둘 다 18.6 B. 키·제어 바이트·빈 슬롯 오버헤드가 지배한다. 조밀한 정수 키라면 비트셋은 원소당 1비트, `[]bool` 은 1바이트로 맵 대비 수십 배 작고 해시도 없다.
- 처방: 의미 명확성 때문에 `map[K]struct{}` 를 쓰되 메모리 근거로 내세우지 말 것. 조밀 정수 키 → `[]uint64` 비트셋(`bits` 패키지) 또는 `[]bool`; 희소 대규모 정수 키 → 정렬 슬라이스 + `slices.BinarySearch`(읽기 위주일 때).
- 반례: 키가 희소하고 범위가 크면(예: 64비트 해시) 비트셋은 폭발한다. 쓰기 빈번한 정렬 슬라이스는 O(n) 삽입.
- 검증: `testing.AllocsPerRun`/`-benchmem` 의 B/op, heap 프로파일
- 근거: https://go.dev/ref/spec#Size_and_alignment_guarantees · https://pkg.go.dev/math/bits

### GO-MAP-05 · 큰 값을 맵에 직접 저장해 읽기마다 복사하고, 128바이트 초과 시 숨은 간접 할당까지 발생한다
- 적용: `map[K]BigStruct` (수백 바이트 구조체), 핫 경로 조회
- 신호: `v := m[k]; v.Field = x; m[k] = v` 패턴, CPU 프로파일에 `runtime.memmove`, `m[k].f = x` 가 컴파일 에러라 우회 코드가 많음
- 메커니즘: 맵 값은 주소를 취할 수 없어 조회·갱신마다 값 전체가 복사된다. 키나 값이 128바이트를 넘으면 런타임은 슬롯에 포인터만 두고 본체를 별도 할당한다(엔트리당 추가 할당 + GC 추적 대상).
- 처방: 갱신이 잦으면 `map[K]*V`; 엔트리가 아주 많고 GC 비용이 문제면 `map[K]int32` 인덱스 + `[]V` 슬라이스(값이 포인터 없는 구조체면 GO-MAP-06 과 결합해 GC 스캔 제거).
- 반례: 작은 값(수십 바이트 이하)은 직접 저장이 캐시 지역성·할당 면에서 더 낫다. `*V` 로 바꾸면 엔트리마다 객체 1개 → GC 대상 객체 수 증가.
- 검증: CPU 프로파일 memmove 비중, `-benchmem`
- 근거: https://go.dev/ref/spec#Address_operators · Go 소스 `internal/abi/map.go` 의 `MapMaxKeyBytes`/`MapMaxElemBytes` = 128 (1.27 기준; 1.24 는 `SwissMap*` 이름)

### GO-MAP-06 · 수백만 엔트리 맵에 포인터(string 포함)가 있어 GC 가 매 사이클 전부 스캔한다
- 적용: 인메모리 캐시/인덱스가 수백만 엔트리 이상, GC CPU 비중이 높은 서비스
- 신호: `map[string]*Item`, `map[string]string` 대형 맵; CPU 프로파일에서 `runtime.gcDrain`/`scanobject` 비중 큼; `GODEBUG=gctrace=1` 의 mark 단계 CPU 시간이 힙 크기에 비례해 큼
- 메커니즘: GC 마킹 비용은 "포인터를 담을 수 있는 메모리" 양에 비례한다. 키·값 타입에 포인터가 하나도 없으면 맵 저장소는 noscan 으로 할당돼 스캔을 건너뛴다. `string`, `[]byte`, `time.Time`(내부에 `*Location`), 인터페이스는 모두 포인터를 포함한다.
- 처방: 키를 `uint64` 해시(`hash/maphash`)로, 값을 `[]byte` 아레나 오프셋/`uint32` 인덱스로 바꿔 맵을 포인터 없는 형태로 만든다(bigcache/freecache 와 같은 원리). 해시 충돌은 원본 키 비교로 확인.
- 반례: 엔트리가 수만 개 수준이면 복잡도만 증가. 해시 키 전환 시 충돌 처리 누락은 정합성 버그.
- 검증: 전/후 `gctrace` 의 mark CPU, `/cpu/classes/gc/total:cpu-seconds`, CPU 프로파일 `scanobject` 비중
- 근거: https://go.dev/doc/gc-guide (Optimization guide 절) · https://pkg.go.dev/hash/maphash

### GO-MAP-07 · 맵 반복 순서에 의존하거나, 반대로 "무작위"를 샘플링에 이용한다
- 적용: 직렬화 출력, 캐시 키 생성, 서명/해시 입력, 테스트 골든 파일, 무작위 선택
- 신호: `for k := range m` 결과를 그대로 문자열 결합/해시; 플래키 테스트; "첫 번째 원소 = 랜덤 선택" 코드
- 메커니즘: 명세상 순서는 정의되지 않고 런타임은 시작 위치를 무작위화한다. 그러나 균등 분포가 보장되지 않아 무작위 샘플링 용도로는 편향된다.
- 처방: 결정적 순서가 필요하면 `slices.Sorted(maps.Keys(m))`(Go 1.23). 무작위 선택은 키를 슬라이스로 유지하고 `math/rand/v2` 사용.
- 반례: 순서 무관한 집계에 정렬을 넣으면 O(n log n) 낭비.
- 검증: 동일 입력 다회 실행 결과 diff, `-count=20` 테스트
- 근거: https://go.dev/ref/spec#For_range · https://pkg.go.dev/maps#Keys

### GO-MAP-08 · 동시 쓰기 맵을 recover 로 막을 수 있다고 믿거나, sync.Map 을 범용 동시 맵으로 쓴다
- 적용: 여러 고루틴이 같은 맵에 접근
- 신호: `fatal error: concurrent map writes`/`concurrent map read and map write` 크래시; 쓰기 비율 높은 경로의 `sync.Map`
- 메커니즘: 동시 맵 접근 감지는 panic 이 아니라 fatal error 라 `recover` 로 잡히지 않고 프로세스가 죽는다. `sync.Map` 은 문서상 (1) 한 번 쓰고 많이 읽는 키, (2) 고루틴별로 서로 다른 키 집합 두 경우에 최적화돼 있고 타입 안전성이 없다(박싱 할당). Go 1.24 에서 concurrent hash-trie 로 재구현돼 쓰기 경합이 크게 줄었지만 값 박싱은 여전하다.
- 처방: 기본은 `sync.RWMutex`/`sync.Mutex` + map. 쓰기 경합이 프로파일로 확인되면 키 해시로 샤딩한 N개 맵. `sync.Map` 은 문서의 두 사용 패턴일 때만. CI 에서 `go test -race`.
- 반례: 읽기 위주·짧은 임계구역·코어 수 많음 → RWMutex 의 reader 카운터 원자 연산 자체가 경합점이 될 수 있다(GO-CON-08).
- 검증: `-race`, mutex 프로파일(GO-OBS-03)
- 근거: https://pkg.go.dev/sync#Map · https://go.dev/doc/go1.24 (sync 절) · https://go.dev/doc/articles/race_detector

### GO-MAP-09 · 복합 키를 문자열 결합으로 만들어 조회마다 할당한다 / []byte 키 조회에 불필요한 변환을 한다
- 적용: 핫 경로 조회, 파서·프로토콜 처리
- 신호: `m[a+":"+b]`, `m[fmt.Sprintf("%d-%d", x, y)]`, `k := string(buf); v := m[k]`
- 메커니즘: `fmt.Sprintf` 는 조회마다 항상 할당한다. `a+":"+b` 결합은 결과가 탈출하지 않으면(인덱스 식 안) 32바이트 스택 버퍼(`tmpStringBufSize`)를 쓰므로 결과가 32바이트 이하면 0 할당, 초과하면 매 조회 할당한다(실측 Go 1.27.3: 5바이트 키 0회, 43바이트 키 1회). 즉 문제는 긴 키와 Sprintf 이고, 구조체 키의 주된 이점은 명확성과 길이 무관 0 할당이다. 반면 컴파일러는 `m[string(b)]` 처럼 변환이 인덱스 식 안에 직접 있으면 복사 없이 조회한다(변수에 담으면 최적화가 사라짐).
- 처방: 비교 가능한 구조체 키 `type key struct{ a, b string }` 또는 `[2]uint64`; `[]byte` 는 `m[string(b)]` 를 그 자리에서 사용.
- 반례: 키를 맵에 *저장*할 때(`m[string(b)] = v`)는 복사가 필요하다 — 최적화는 조회 전용.
- 검증: `testing.AllocsPerRun` 으로 0 할당 확인
- 근거: https://go.dev/wiki/CompilerOptimizations (string(byteSlice) map 인덱스 최적화) · https://go.dev/ref/spec#Comparison_operators

### GO-MAP-10 · NaN·time.Time·인터페이스 키의 등가성 함정
- 적용: `map[float64]V`, `map[time.Time]V`, `map[any]V`
- 신호: len 은 늘어나는데 조회가 실패; 같은 시각인데 다른 키; 런타임 `panic: runtime error: hash of unhashable type`
- 메커니즘: NaN != NaN 이라 `m[NaN]=v` 는 매번 새 엔트리를 만들고 조회·delete 가 불가능하다(`clear` 로만 제거). `time.Time` 의 `==` 는 wall/monotonic/Location 까지 비교하므로 같은 순간이라도 다른 키가 된다(time 문서가 맵 키 사용을 경고). `map[any]V` 에 슬라이스/맵을 동적 타입으로 넣으면 컴파일은 되고 런타임 panic.
- 처방: 시각 키는 `t.UnixNano()` 또는 `t.Round(0).UTC()` 로 정규화; float 키는 정수 스케일링 또는 NaN 사전 차단; `any` 키는 피하고 구체 타입/제네릭 `comparable` 사용.
- 반례: 없음 — 정규화 비용은 무시할 수준.
- 검증: 테이블 테스트로 같은 순간·다른 Location 키 조회
- 근거: https://pkg.go.dev/time#Time ("Time values should not be used as map or database keys" 문단) · https://go.dev/ref/spec#Comparison_operators
