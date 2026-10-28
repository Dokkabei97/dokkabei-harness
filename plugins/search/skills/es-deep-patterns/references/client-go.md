# Go 클라이언트 (ES-CLI-10~)

> 적용 전 확인: `go.mod` 의 `github.com/elastic/go-elasticsearch/v8|v9` 버전과 서버 버전(ES-CLI-01 과 같은 forward-compatible 원칙), 저수준 `esapi`(`es.Search(...)`) 인지 Typed API(`es.Search().Do(ctx)`) 인지, `Config.Transport` 지정 여부, Go 버전(1.25+ 는 GOMAXPROCS 가 cgroup CPU limit 을 반영). 프로젝트 컨벤션이 있으면 그것이 우선.

### ES-CLI-10 · `Config.Transport` 미지정 = `http.DefaultTransport` 복제 — 호스트당 유휴 커넥션 2개
- 적용: go-elasticsearch v8/v9(`elastic-transport-go`), 고동시성 검색·색인 서비스
- 신호: 부하 시 `TIME_WAIT` 소켓 급증, ephemeral port 고갈(`connect: cannot assign requested address`), ES `took` 은 짧은데 앱 지연·CPU(TLS 핸드셰이크) 상승
- 메커니즘: Transport 가 nil 이면 `http.DefaultTransport.Clone()` 을 쓰고 `MaxIdleConnsPerHost` 를 따로 설정하지 않는다 → net/http 기본 `DefaultMaxIdleConnsPerHost = 2`. 동시 요청이 2를 넘으면 반환된 커넥션 대부분이 유휴 풀에 못 들어가 닫히고 매 요청 새 연결(TLS 포함)을 맺는다
- 처방: `&http.Transport{MaxIdleConns: n, MaxIdleConnsPerHost: n, IdleConnTimeout: 90*time.Second, ...}` 를 만들어 `elasticsearch.Config{Transport: tr}` 로 주입. n 은 서비스의 ES 동시 요청 수 기준(노드가 여러 개면 노드당). `MaxConnsPerHost` 로 상한을 걸면 초과 요청은 대기 큐가 된다는 점도 함께 고려
- 반례: 풀만 키우면 ES 스레드풀 거부(ES-JVM-05)로 병목이 이동 — 동시성 상한은 서버 용량 기준으로
- 검증: `ss -tan state time-wait | wc -l`, `httptrace.ClientTrace` 의 `GotConn.Reused` 비율, 부하 테스트 전후 비교
- 근거: https://github.com/elastic/elastic-transport-go/blob/main/elastictransport/elastictransport.go (nil 이면 DefaultTransport.Clone), https://pkg.go.dev/net/http#pkg-constants (DefaultMaxIdleConnsPerHost = 2)

### ES-CLI-11 · esapi 응답은 4xx/5xx 에도 `err == nil` — `res.IsError()` 확인과 Body 소진·Close 는 호출자 몫
- 적용: 저수준 `esapi` 호출(`es.Search`, `es.Index`, `es.Bulk` 등). Typed API 는 에러 상태를 `*types.ElasticsearchError` 로 err 에 담으므로 해당 부분만 다름
- 신호: `if err != nil { ... }` 만 있고 `res.IsError()` 없음 → 404/400/429 를 정상 응답으로 디코딩. `defer res.Body.Close()` 누락, 또는 에러 분기에서 바디를 읽지 않고 반환
- 메커니즘: `err` 는 전송 계층 실패(연결·타임아웃)만 뜻한다. HTTP 상태 실패는 `res.IsError()`(StatusCode > 299)로만 드러난다. 바디를 끝까지 읽고 닫지 않으면 커넥션이 keep-alive 풀로 돌아가지 못해 ES-CLI-10 의 커넥션 churn 이 재현된다
- 처방: 공통 헬퍼로 `defer res.Body.Close()` + `if res.IsError() { 바디를 읽어 error.type·status 로 에러 생성 }` 을 강제하고, 성공 경로도 디코딩 후 남은 바디는 `io.Copy(io.Discard, res.Body)`. 검색 응답은 `_shards.failed`·`timed_out` 도 함께 검사(ES-QRY-13)
- 반례: 없음
- 검증: 존재하지 않는 인덱스 검색 테스트가 에러를 반환하는지, `GotConn.Reused` 로 커넥션 재사용 확인
- 근거: https://github.com/elastic/go-elasticsearch (README — "close the response body and consume it"), https://pkg.go.dev/github.com/elastic/go-elasticsearch/v8/esapi#Response.IsError

### ES-CLI-12 · `esutil.BulkIndexer` 기본값: 워커 `runtime.NumCPU()`·5MB·30s — 아이템 실패는 콜백과 `Stats()` 에서만 보인다
- 적용: `esutil.NewBulkIndexer`, 특히 컨테이너 배포
- 신호: `OnFailure` 를 아이템에 달지 않음, `Close()` 후 `Stats().NumFailed` 미확인, 컨테이너 CPU limit 2 인데 워커가 수십 개(호스트 코어 수)
- 메커니즘: 기본 `NumWorkers = runtime.NumCPU()` — NumCPU 는 cgroup CPU limit 을 반영하지 않는다(Go 1.25 에서 바뀐 것은 GOMAXPROCS 기본값뿐). 워커마다 별도 버퍼를 가지므로 워커 수 × `FlushBytes`(기본 5e6) 만큼 메모리와 동시 bulk 요청이 생긴다. `FlushInterval` 기본 30s → 저트래픽 시 문서가 최대 30초 버퍼에 머문다. 응답의 아이템 실패(`status > 201` 또는 error)는 그 아이템의 `OnFailure` 호출 + `NumFailed` 증가로만 보고되고, 요청 전체 실패는 버퍼의 모든 아이템 `OnFailure` + 인덱서 `OnError` 로 간다
- 처방: `NumWorkers`(ES 쪽 동시 bulk 용량 기준, 최소한 `runtime.GOMAXPROCS(0)`), `FlushBytes`, `FlushInterval` 을 명시. 모든 아이템에 `OnFailure` 로 ES-CLI-04 분류(429 재시도·4xx DLQ·409 무시), 인덱서 `OnError` 로그, 종료 시 `Close(ctx)` 후 `Stats()` 를 메트릭으로. Kafka 오프셋과 묶어야 하면 비동기 인덱서보다 "poll 단위 동기 bulk → 결과 확인 → 커밋"(ES-ING-03)
- 반례: 일회성 백필은 기본값으로 시작해도 되지만 `NumFailed` 확인은 생략 불가
- 검증: 잘못된 타입 문서를 섞은 통합 테스트에서 `Stats().NumFailed` 와 DLQ 건수 일치, 워커 수별 처리량·ES `thread_pool/write` rejected 측정
- 근거: https://github.com/elastic/go-elasticsearch/blob/main/esutil/bulk_indexer.go (기본값·실패 보고 경로), https://go.dev/doc/go1.25 (container-aware GOMAXPROCS)

### ES-CLI-13 · Go 는 `context` 데드라인이 실제로 HTTP 를 끊는다 — 대신 기본 재시도(502/503/504 ×3)와 429 미재시도를 알고 계층화
- 적용: `esapi` 요청의 `WithContext(ctx)` / Typed API `Do(ctx)`, 기본 `elastictransport` 재시도 설정
- 신호: 검색 데드라인 없이 `context.Background()` 사용, 또는 앱 레벨 재시도를 transport 재시도 위에 중첩, 429 가 재시도될 것이라 가정
- 메커니즘: Kotlin 동기 클라이언트(ES-CLI-06)와 달리 Go 는 ctx 취소가 진행 중인 HTTP 요청을 중단한다. transport 는 기본으로 502/503/504 에 대해 최대 3회 재시도하며(`RetryOnStatus`·`MaxRetries` 로 변경), 429 는 기본 목록에 없어 재시도되지 않는다. 클라이언트가 끊어도 서버 쪽 작업 취소 여부는 API 마다 다르다(ES-CLI-03)
- 처방: 요청마다 `context.WithTimeout` — 서버 `timeout` < ctx 데드라인 < 상위 호출 데드라인(ES-CLI-03). 429 재시도가 필요하면 `RetryOnStatus` 에 429 를 넣고 `RetryBackoff` 를 지수 백오프로 지정하거나 앱 레벨에서 한 곳만 재시도. 무거운 검색은 재시도 상한을 낮춘다
- 반례: 자동완성처럼 응답 시간이 우선인 경로는 짧은 데드라인 + 재시도 없음
- 검증: toxiproxy 로 ES 지연·503 주입 후 실제 반환 시간과 요청 횟수 측정, `GET _tasks?actions=*search*&detailed` 로 서버 잔여 작업 확인
- 근거: https://github.com/elastic/elastic-transport-go/blob/main/elastictransport/elastictransport.go (defaultRetryOnStatus 502/503/504, defaultMaxRetries 3), https://pkg.go.dev/net/http#NewRequestWithContext
