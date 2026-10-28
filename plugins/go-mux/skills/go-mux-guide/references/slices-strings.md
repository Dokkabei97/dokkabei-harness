# Go 슬라이스·문자열 스페셜리스트 항목 (GO-SLC)

백킹 배열 공유, 숨은 복사·할당, 메모리 유지(retention)에 관한 함정.

---

### GO-SLC-01 · append 앨리어싱 — 서브슬라이스에 append 해 원본의 다음 원소를 덮어쓴다
- 적용: 슬라이스를 인자로 받아 append 하는 함수, 공통 prefix 슬라이스에서 여러 갈래를 만드는 코드(경로·조합 생성, 백트래킹)
- 신호: `base := xs[:n]; a := append(base, x); b := append(base, y)` 후 a 의 마지막 값이 y 로 바뀜; 재귀 백트래킹 결과가 마지막 값으로 덮임
- 메커니즘: `len < cap` 이면 append 는 새 배열을 만들지 않고 같은 백킹 배열에 쓴다. 두 갈래가 같은 메모리를 공유한다.
- 처방: 갈래를 만들 때 full slice expression 으로 cap 을 잘라 강제 복사 — `append(xs[:n:n], x)`; 결과를 보관할 때 `slices.Clone`.
- 반례: 단일 소유 슬라이스의 누적 append 는 공유가 의도된 최적화 — 매번 Clone 하면 O(n²).
- 검증: `-race` 로는 안 잡힘(단일 고루틴). 갈래별 결과를 비교하는 테이블 테스트
- 근거: https://go.dev/ref/spec#Slice_expressions (Full slice expressions) · https://go.dev/blog/slices-intro

### GO-SLC-02 · 큰 버퍼의 작은 서브슬라이스/부분문자열을 보관해 전체 버퍼를 GC 가 회수하지 못한다
- 적용: 파일·HTTP 바디·메시지를 통째로 읽은 뒤 일부 필드(토큰, ID, 헤더 값)를 캐시/맵/장수 구조체에 저장
- 신호: 저장 항목 수 × 항목 크기보다 heap inuse 가 훨씬 큼; heap 프로파일 inuse 상위가 `io.ReadAll`/`bufio` 할당 지점
- 메커니즘: 서브슬라이스와 부분문자열은 원본 백킹 배열을 가리키는 포인터+길이라, 10바이트만 보관해도 수 MB 원본 전체가 살아 있다.
- 처방: 보관 직전 분리 — 문자열 `strings.Clone(s)`(Go 1.20), 바이트 `bytes.Clone(b)`/`slices.Clone`. 대량 중복 문자열은 `unique.Make`(GO-GC-10).
- 반례: 요청 범위에서 쓰고 버리는 값까지 Clone 하면 불필요한 할당.
- 검증: heap 프로파일 `-sample_index=inuse_space` 에서 원본 할당 지점의 inuse 감소
- 근거: https://pkg.go.dev/strings#Clone · https://go.dev/blog/slices-intro (A possible "gotcha")

### GO-SLC-03 · 포인터 슬라이스에서 원소를 잘라내도 잘린 꼬리가 객체를 붙잡는다
- 적용: `[]*T`, `[]any`, `[]string` 큐/스택/풀에서 pop·삭제
- 신호: `s = s[:len(s)-1]`, `s = s[1:]` 큐; 수동 삭제 `append(s[:i], s[i+1:]...)`
- 메커니즘: len 밖이지만 cap 안의 슬롯에 남은 포인터는 여전히 도달 가능하다. `s[1:]` 큐는 앞쪽 슬롯도 배열이 재할당될 때까지 유지된다. Go 1.22 부터 `slices.Delete/DeleteFunc/Compact/CompactFunc/Replace` 는 비워진 꼬리 원소를 0값으로 지운다.
- 처방: 수동 pop 시 `s[len(s)-1] = nil` 후 축소; 삭제는 `slices.Delete`(1.22+); 장수 FIFO 는 링 버퍼.
- 반례: 포인터 없는 원소 타입(`[]int`)은 해당 없음.
- 검증: heap 프로파일에서 해당 타입 inuse 추이
- 근거: https://go.dev/doc/go1.22 (slices 절) · https://pkg.go.dev/slices#Delete

### GO-SLC-04 · append 성장 공식을 "항상 2배"로 가정해 메모리 예산을 잘못 계산한다
- 적용: 대용량 슬라이스를 점진적으로 키우는 배치/수집 경로
- 신호: 최종 len 이 대략 알려져 있는데 `var xs []T` 로 시작; pprof 에서 `runtime.growslice` 상위
- 메커니즘: Go 1.18+ 에서 cap 256 미만은 2배, 이후 `newcap += (newcap + 3*256)/4` 로 1.25배 쪽으로 완만히 수렴하고, 결과 바이트 수를 메모리 size class 로 올림한다. 성장마다 이전 배열 복사 + 이전 배열은 GC 까지 잔존 → 순간 피크 ≈ 이전 + 새 배열.
- 처방: `make([]T, 0, n)` 사전 할당; 크기 미상이면 `slices.Grow(xs, k)` 로 배치 단위 확보.
- 반례: 상한이 매우 큰데 실제 평균이 작으면 사전 할당이 낭비.
- 검증: `-benchmem`, alloc_space 프로파일의 growslice
- 근거: Go 소스 `runtime/slice.go` `nextslicecap` · https://pkg.go.dev/slices#Grow

### GO-SLC-05 · []byte↔string 변환이 언제 할당되고 언제 안 되는지 모른다
- 적용: 파서, 직렬화, 로깅, 헤더 처리 핫 경로
- 신호: CPU/alloc 프로파일에 `runtime.slicebytetostring`/`stringtoslicebyte` 상위
- 메커니즘: 변환은 원칙적으로 복사+할당이다. 컴파일러 예외(할당 없음): `m[string(b)]` 조회, `string(b) == "x"` 비교, 일시적 결합 `"a"+string(b)`, `for i, r := range []byte(s)`/`range string(b)`, 그리고 결과가 탈출하지 않고 32바이트 이하인 변환(스택 임시 버퍼). 
- 처방: 바이트 단위 API 유지(`bytes.*`, `strconv.Append*`, `AppendFormat`); 정말 필요하고 불변성을 보장할 수 있을 때만 `unsafe.String(unsafe.SliceData(b), len(b))`(Go 1.20+) — 이후 b 를 절대 수정하지 않아야 한다.
- 반례: unsafe 변환 후 버퍼 재사용(sync.Pool 등) → 문자열 내용이 바뀌는 메모리 오염. 측정 없이 unsafe 도입 금지.
- 검증: `testing.AllocsPerRun`, `-gcflags=-m` 로 탈출 여부
- 근거: https://go.dev/wiki/CompilerOptimizations · https://pkg.go.dev/unsafe#String

### GO-SLC-06 · strings.Builder/bytes.Buffer 를 잘못 써서 숨은 복사·panic 이 생긴다
- 적용: 문자열 조립 루프, 응답 본문 생성
- 신호: 루프 내 `s += ...`; `bytes.Buffer` 로 만든 뒤 `.String()`; Builder 를 값으로 반환/복사
- 메커니즘: `+=` 는 매번 새 문자열(O(n²)). `strings.Builder.String()` 은 복사 없이 내부 버퍼를 문자열로 노출하지만, `bytes.Buffer.String()` 은 복사한다. 0이 아닌 Builder 를 값 복사 후 쓰면 `strings: illegal use of non-zero Builder copied by value` panic.
- 처방: 최종 크기 추정 후 `b.Grow(n)`; 결과가 string 이면 `strings.Builder`, `io.Writer` 대상이면 `bytes.Buffer`; Builder 는 포인터로 전달.
- 반례: 2~3개 결합은 `+` 가 컴파일러 최적화로 단일 할당이라 Builder 가 오히려 장황.
- 검증: `-benchmem`
- 근거: https://pkg.go.dev/strings#Builder · https://pkg.go.dev/bytes#Buffer.String

### GO-SLC-07 · Split/Fields 로 전체 슬라이스를 만든 뒤 첫 몇 개만 쓴다
- 적용: 로그/헤더/CSV 한 줄 파싱 핫 경로
- 신호: `strings.Split(s, ",")[0]`, `strings.Fields(line)` 후 조기 break
- 메커니즘: Split 은 결과 `[]string` 을 할당한다(부분문자열 자체는 원본 공유). 첫 토큰만 필요하면 낭비.
- 처방: 단일 분리 `strings.Cut`(1.18), 마지막 구분자 기준 `strings.CutLast`(1.27); 순회는 `strings.SplitSeq`/`FieldsSeq`/`Lines`(Go 1.24, 슬라이스 할당 없는 이터레이터); 개수 제한 `SplitN`.
- 반례: 결과 전체를 인덱스로 여러 번 접근하면 Split 이 단순.
- 검증: `-benchmem`
- 근거: https://go.dev/doc/go1.24 (strings 절) · https://go.dev/doc/go1.27 (strings.CutLast) · https://pkg.go.dev/strings#Cut

### GO-SLC-08 · range 로 큰 구조체 슬라이스를 순회하며 원소마다 복사한다 / 수정이 반영되지 않는다
- 적용: `[]BigStruct`(수백 바이트) 핫 루프
- 신호: `for _, v := range items { v.Count++ }` (반영 안 됨), CPU 프로파일 memmove
- 메커니즘: range 값 변수는 원소의 복사본이다. 큰 원소면 반복마다 복사 비용, 수정은 원본에 반영되지 않는다.
- 처방: `for i := range items { it := &items[i]; ... }`
- 반례: 작은 원소는 값 순회가 더 명확하고 비용 차이 없음.
- 검증: 벤치마크
- 근거: https://go.dev/ref/spec#For_range

### GO-SLC-09 · nil 슬라이스와 빈 슬라이스의 JSON 차이를 API 계약에서 놓친다
- 적용: encoding/json(v1) 으로 응답을 직렬화하는 API
- 신호: 결과 없음일 때 클라이언트가 `items: null` 로 깨짐; `var items []T` 를 그대로 응답
- 메커니즘: v1 API(`encoding/json`)는 nil 슬라이스/맵을 `null`, 빈 슬라이스를 `[]` 로 인코딩한다 — Go 1.27 에서 v1 이 v2 구현 위로 옮겨졌어도 v1 의 마샬링 동작은 보존된다. 반면 `encoding/json/v2`(1.25 실험 → 1.27 정식)는 기본적으로 nil 슬라이스를 `[]`, nil 맵을 `{}` 로 내보낸다(`FormatNilSliceAsNull`/`FormatNilMapAsNull` 로 null). 또한 v2 는 잘못된 UTF-8·중복 키를 거부한다.
- 처방: 응답 DTO 생성 시 `items := make([]T, 0, n)` 으로 초기화하거나 계약을 `null` 허용으로 명시. v1→v2 import 전환 시 빈 결과·중복 키 입력에 대한 계약 테스트 추가.
- 반례: `null` 과 `[]` 의 의미를 구분해 쓰는 API.
- 검증: 빈 결과 핸들러의 골든 응답 테스트
- 근거: https://pkg.go.dev/encoding/json#Marshal · https://pkg.go.dev/encoding/json/v2 · https://go.dev/doc/go1.27 (encoding/json 절)

### GO-SLC-10 · omitempty 가 time.Time·구조체 0값을 생략하지 못한다
- 적용: 선택적 시각/구조체 필드를 가진 JSON 응답
- 신호: `"deleted_at":"0001-01-01T00:00:00Z"` 가 응답에 노출
- 메커니즘: v1 `omitempty` 는 false/0/nil/빈 문자열·컬렉션만 생략하고 구조체는 생략하지 않는다. Go 1.24 `omitzero` 는 0값(또는 `IsZero()` true)이면 생략한다.
- 처방: Go 1.24+ 에서 `json:"deleted_at,omitzero"`; 이전 버전은 `*time.Time`.
- 반례: 0값이 의미 있는 값인 필드.
- 검증: 직렬화 테스트
- 근거: https://go.dev/doc/go1.24 (encoding/json omitzero)
