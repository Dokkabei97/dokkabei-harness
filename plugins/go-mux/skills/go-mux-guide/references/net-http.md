# Go net/http 스페셜리스트 항목 (GO-HTTP)

클라이언트 커넥션 풀, 서버 타임아웃 기본값, Go 1.22+ ServeMux 의 실제 동작.

---

### GO-HTTP-01 · http.Client/Transport 를 요청마다 만들거나 DefaultClient(타임아웃 0)를 쓴다
- 적용: 외부 API·내부 마이크로서비스·ES REST 호출을 하는 모든 클라이언트 코드
- 신호: 함수 안 `&http.Client{}`/`&http.Transport{}` 생성; `http.Get(url)`/`http.DefaultClient` 사용; `netstat` TIME_WAIT 폭증, 파일 디스크립터 고갈
- 메커니즘: 커넥션 풀은 Transport 에 있다. 요청마다 새 Transport 는 매번 TCP+TLS 핸드셰이크를 하고 유휴 커넥션을 닫지 않아 누수된다. `DefaultClient` 의 `Timeout` 은 0(무제한)이라 응답 없는 서버에 고루틴이 영원히 매달린다.
- 처방: 프로세스 수명의 Client 하나를 주입해 재사용, `Timeout`(바디 읽기까지 포함하는 전체 상한) 또는 요청별 `context.WithTimeout`. 커스텀 Transport 는 `http.DefaultTransport.(*http.Transport).Clone()` 에서 시작해 기본값(프록시, HTTP/2, 다이얼 타임아웃)을 유지.
- 반례: `Client.Timeout` 은 스트리밍 다운로드도 끊는다 — 장시간 스트림은 ctx/데드라인으로 별도 관리.
- 검증: `httptrace.ClientTrace` 의 `GotConn.Reused`, 연결 수 메트릭
- 근거: https://pkg.go.dev/net/http#Client · https://pkg.go.dev/net/http#Transport.Clone

### GO-HTTP-02 · MaxIdleConnsPerHost 기본값 2 때문에 단일 호스트 고QPS 호출에서 커넥션이 계속 새로 맺어진다
- 적용: 하나의 다운스트림(게이트웨이, ES 코디네이터, 사내 API)에 동시 요청이 수십 이상
- 신호: 동시성은 높은데 재사용률 낮음(`GotConn.Reused=false` 다수), TIME_WAIT 증가, TLS 핸드셰이크 CPU 상위
- 메커니즘: `DefaultMaxIdleConnsPerHost = 2` — 동시 50개 요청 후 48개 커넥션은 반납 시 닫힌다. DefaultTransport 의 `MaxIdleConns` 는 100(전체), `MaxConnsPerHost` 는 0(무제한)이라 버스트 시 커넥션이 무한히 열릴 수도 있다.
- 처방: `MaxIdleConnsPerHost` ≈ 호스트당 정상 동시성, `MaxIdleConns` ≥ 호스트 수 × 그 값, 다운스트림 보호가 필요하면 `MaxConnsPerHost` 상한.
- 반례: 호스트가 수천 개(크롤러 등)면 호스트당 유휴를 키우면 FD 낭비.
- 검증: `httptrace` 재사용률, 다운스트림 신규 연결 수
- 근거: https://pkg.go.dev/net/http#DefaultMaxIdleConnsPerHost · https://pkg.go.dev/net/http#Transport

### GO-HTTP-03 · 응답 Body 를 닫지 않거나 끝까지 읽지 않아 커넥션이 재사용되지 않는다
- 적용: 상태 코드만 보고 바디를 버리는 호출, 에러 응답 분기
- 신호: `if resp.StatusCode != 200 { return err }` 에서 Close 누락; `defer resp.Body.Close()` 는 있지만 바디 미소비
- 메커니즘: 문서상 바디를 EOF 까지 읽고 닫지 않으면 Transport 가 HTTP/1 커넥션을 재사용하지 못할 수 있다. Go 1.27 부터 HTTP/1 `Body.Close` 가 보수적 상한까지 남은 내용을 자동 drain 한다 — 1.26 이하에선 직접 해야 하고, 상한을 넘는 큰 바디는 여전히 커넥션이 버려진다.
- 처방: `defer func(){ io.Copy(io.Discard, io.LimitReader(resp.Body, 64<<10)); resp.Body.Close() }()` (상한 있는 drain). err 가 nil 이면 항상 Close(`bodyclose` 린터).
- 반례: 거대한 바디를 끝까지 읽는 것은 커넥션 재연결보다 비쌀 수 있음 — 상한 필수.
- 검증: `httptrace` 재사용률
- 근거: https://pkg.go.dev/net/http#Response · https://go.dev/doc/go1.27 (net/http 절)

### GO-HTTP-04 · 클라이언트 IdleConnTimeout 이 서버/LB 유휴 타임아웃보다 길어 재사용 커넥션에서 간헐적 EOF/reset
- 적용: AWS ALB(기본 유휴 60초)·nginx·사내 L7 뒤의 서비스 호출
- 신호: 트래픽이 뜸한 시간대 첫 요청에서 `EOF`, `connection reset by peer`, `server closed idle connection`
- 메커니즘: DefaultTransport `IdleConnTimeout` 은 90초. 서버가 먼저 닫은 커넥션을 클라이언트가 꺼내 쓰면 실패한다. Transport 는 재사용 커넥션 실패를 *재전송 가능한* 요청(GET/HEAD/OPTIONS/TRACE 또는 `Idempotency-Key`/`X-Idempotency-Key` 헤더가 있고 바디가 없거나 `GetBody` 가 있는 경우)만 자동 재시도한다 — POST 는 에러로 올라온다.
- 처방: 클라이언트 `IdleConnTimeout` 을 서버/LB 유휴 타임아웃보다 짧게(예: 50초 vs 60초). 재시도 가능한 POST 는 `Idempotency-Key` 헤더 부여.
- 반례: 서버 쪽 keep-alive 를 끈 환경에선 무관.
- 검증: 유휴 후 첫 요청 실패율, 다운스트림 LB 설정 대조
- 근거: https://pkg.go.dev/net/http#Transport · https://docs.aws.amazon.com/elasticloadbalancing/latest/application/application-load-balancers.html#connection-idle-timeout

### GO-HTTP-05 · http.Server 타임아웃 기본값이 전부 0(무제한)이다 — ListenAndServe 는 slowloris 에 열려 있다
- 적용: 인터넷/사내망에 노출되는 모든 Go HTTP 서버
- 신호: `http.ListenAndServe(addr, mux)` 직접 호출; `&http.Server{Addr, Handler}` 만 설정
- 메커니즘: `ReadTimeout`, `ReadHeaderTimeout`, `WriteTimeout`, `IdleTimeout` 기본 0 = 제한 없음. `IdleTimeout` 이 0 이면 `ReadTimeout` 을, `ReadHeaderTimeout` 이 0 이면 `ReadTimeout` 을 쓰고 둘 다 0 이면 무제한. 헤더를 천천히 보내는 클라이언트가 고루틴·FD 를 무한히 점유한다.
- 처방: 최소 `ReadHeaderTimeout`(예: 5~10s)와 `IdleTimeout` 설정. `WriteTimeout` 은 스트리밍/긴 응답을 끊으므로 전역값 대신 핸들러별 `http.NewResponseController(w).SetWriteDeadline(...)`(Go 1.20). `gosec` G112 가 ReadHeaderTimeout 누락을 잡는다.
- 반례: `http.TimeoutHandler` 는 응답 전체를 버퍼링하고 Flusher/Hijacker 를 지원하지 않아 스트리밍·SSE 에 부적합.
- 검증: 헤더를 바이트 단위로 천천히 보내는 클라이언트로 연결 유지 시간 측정
- 근거: https://pkg.go.dev/net/http#Server · https://pkg.go.dev/net/http#ResponseController

### GO-HTTP-06 · 요청 바디/헤더 크기 제한이 없어 메모리 DoS 에 노출된다
- 적용: JSON 바디를 받는 모든 핸들러
- 신호: `json.NewDecoder(r.Body).Decode(&v)` 또는 `io.ReadAll(r.Body)` 를 제한 없이 사용
- 메커니즘: 서버는 바디 크기를 제한하지 않는다. 헤더는 `MaxHeaderBytes` 기본 1MB(`DefaultMaxHeaderBytes`). Go 1.27 은 헤더 값 개수 상한 `Server.MaxHeaderValueCount`(기본 `DefaultMaxHeaderValueCount`)를 추가했다. 또한 `Decoder.Decode` 는 첫 JSON 값만 읽어 뒤에 붙은 데이터를 조용히 무시한다.
- 처방: `r.Body = http.MaxBytesReader(w, r.Body, 1<<20)` 후 디코딩, 초과는 `*http.MaxBytesError` 로 413 매핑. 후행 데이터 거부는 Decode 후 `if err := dec.Decode(&struct{}{}); !errors.Is(err, io.EOF) { /* 400 */ }` — `dec.More()` 는 다음 바이트가 `]`/`}` 이면 false 라 `{"a":1}}` 를 통과시키므로 쓰지 말 것.
- 반례: 파일 업로드 경로는 별도 큰 상한 + 스트리밍 처리.
- 검증: 대용량 바디 요청 테스트에서 413
- 근거: https://pkg.go.dev/net/http#MaxBytesReader · https://go.dev/doc/go1.27 (net/http 절)

### GO-HTTP-07 · Go 1.22 ServeMux 패턴 규칙(우선순위·충돌 panic·{$}·HEAD)을 모르고 라우팅을 설계한다
- 적용: stdlib mux 로 라우팅하는 서비스(go.mod `go 1.22`+)
- 신호: `/api/` 가 모든 하위 경로를 잡음; 등록 시점 panic `pattern ... conflicts with pattern ...`; 405 대신 404 기대
- 메커니즘: 패턴은 `[METHOD ][HOST]/path`, 와일드카드 `{name}`(한 세그먼트), `{name...}`(나머지 전부), `{$}`(정확히 끝). 겹치는 두 패턴 중 *더 구체적인* 쪽이 이기며, 어느 쪽도 더 구체적이지 않으면 등록 시 panic 한다. `GET` 패턴은 HEAD 도 매치한다. 경로는 맞는데 메서드가 안 맞으면 `Allow` 헤더와 함께 405. 슬래시로 끝나는 패턴은 하위 트리 전체를 매치하고 슬래시 없는 요청을 리다이렉트한다(Go 1.26 부터 301 → 307). 새 동작은 go.mod `go` 라인 1.22+ 일 때만이며 `GODEBUG=httpmuxgo121=1` 로 구 동작 복귀.
- 처방: 정확 매치는 `/api/{$}`, 경로 파라미터는 `r.PathValue("id")`; 라우트 등록을 테스트에서 실행해 충돌 panic 을 CI 에서 잡음.
- 반례: 정규식 제약(`{id:[0-9]+}`)·미들웨어 그룹은 stdlib 범위 밖 — 핸들러에서 검증하거나 기존 라우터 유지.
- 검증: 라우팅 테이블 테스트(메서드·경로·기대 상태 코드), 405 의 Allow 헤더 확인
- 근거: https://pkg.go.dev/net/http#hdr-Patterns-ServeMux · https://go.dev/blog/routing-enhancements · https://go.dev/doc/go1.26 (net/http 절)

### GO-HTTP-08 · 메트릭/트레이스 라벨에 r.URL.Path 를 넣어 카디널리티가 폭발한다
- 적용: HTTP 메트릭(Prometheus/OTel) 미들웨어
- 신호: `path` 라벨 값이 `/orders/123`, `/orders/124`… 무한 증가; 메트릭 백엔드 메모리 경보
- 메커니즘: 경로 파라미터가 라벨에 그대로 들어가 시계열이 요청 수만큼 생긴다. Go 1.23+ `Request.Pattern` 은 매치된 ServeMux 패턴(`GET /orders/{id}`)을 담는다(`httpmuxgo121=1` 이면 비어 있음). ServeMux 는 받은 `*Request` 의 `Pattern` 필드를 제자리에서 채우므로(1.27 소스 `server.go` `h, r.Pattern, r.pat, r.matches = mux.findHandler(r)`), mux 바깥 미들웨어는 `next.ServeHTTP` *이후*에 읽어야 하고, 중간 미들웨어가 `r.WithContext`(복제)로 넘기면 바깥의 r 에는 채워지지 않는다.
- 처방: 미들웨어에서 `next.ServeHTTP(w, r)` 이후 `r.Pattern` 을 라벨로 사용(빈 값은 "unmatched").
- 반례: mux 를 거치지 않는 핸들러는 Pattern 이 비어 있다. 복제 문제를 피하려면 라벨 기록을 mux 안쪽(라우트 등록 시 감싸는 래퍼)에서 하거나, 바깥 미들웨어가 ctx 에 넣은 가변 홀더에 안쪽에서 Pattern 을 기록.
- 검증: 메트릭 시계열 수(cardinality) 확인
- 근거: https://pkg.go.dev/net/http#Request · https://go.dev/doc/go1.23

### GO-HTTP-09 · net/http/pprof blank import 가 DefaultServeMux 에 디버그 엔드포인트를 등록해 외부에 노출된다
- 적용: `import _ "net/http/pprof"` 가 있는 서비스
- 신호: 서비스가 `http.ListenAndServe(addr, nil)`(=DefaultServeMux) 또는 DefaultServeMux 를 공개 포트에 서빙
- 메커니즘: 패키지 init 이 `/debug/pprof/` 핸들러를 DefaultServeMux 에 등록한다. 공개되면 힙 덤프·프로파일 수집으로 정보 노출·CPU 소모 공격이 가능하다.
- 처방: 공개 트래픽은 별도 `http.NewServeMux()`; pprof 는 localhost/내부 전용 포트의 별도 서버에서만.
- 반례: 없음.
- 검증: 공개 포트로 `/debug/pprof/` 요청이 404 인지 확인
- 근거: https://pkg.go.dev/net/http/pprof

### GO-HTTP-10 · Shutdown 이 진행 중 요청을 취소한다고 착각하거나, 롤링 배포에서 요청을 잃는다
- 적용: k8s 롤링 업데이트, SIGTERM 처리
- 신호: 배포 중 502/connection refused; 웹소켓/SSE 가 Shutdown 을 무시
- 메커니즘: `Server.Shutdown(ctx)` 는 리스너를 닫고 유휴 커넥션을 닫은 뒤 활성 요청이 *스스로* 끝나길 ctx 만료까지 기다린다 — 요청 ctx 를 취소하지 않는다. 하이재킹된 커넥션(웹소켓)은 닫지도 기다리지도 않는다. 또 k8s 는 SIGTERM 과 엔드포인트 제거를 병렬로 하므로 즉시 리스너를 닫으면 늦게 라우팅된 요청이 실패한다.
- 처방: SIGTERM → readiness 실패 전환 → 수 초 대기(또는 preStop sleep) → `Shutdown(ctx with timeout)` → 실패 시 `Close`. 장수 요청 취소가 필요하면 `BaseContext` 로 루트 ctx 를 주입해 직접 취소. 웹소켓은 `RegisterOnShutdown` 으로 종료 통지.
- 반례: 없음.
- 검증: 부하 중 롤링 배포에서 오류율 0 확인
- 근거: https://pkg.go.dev/net/http#Server.Shutdown · https://pkg.go.dev/net/http#Server

### GO-HTTP-11 · 상태 코드를 먼저 쓴 뒤 JSON 인코딩이 실패해 200 + 깨진 바디가 나간다
- 적용: `writeJSON(w, status, v)` 헬퍼
- 신호: `w.WriteHeader(status); json.NewEncoder(w).Encode(v)` 에서 Encode 에러 무시; 로그의 `http: superfluous response.WriteHeader call`
- 메커니즘: 헤더는 첫 Write/WriteHeader 에서 확정돼 이후 에러 응답으로 바꿀 수 없다. 인코딩 실패(NaN float, 순환, MarshalJSON 에러)는 잘린 바디 + 200 으로 나간다.
- 처방: 작은 응답은 `json.Marshal` 로 먼저 바이트를 만든 뒤 성공 시 헤더+바디, 실패 시 500. 큰 스트리밍 응답만 Encoder 직접 사용.
- 반례: 대용량 스트리밍은 버퍼링이 메모리를 키운다.
- 검증: NaN 등 인코딩 실패 값으로 핸들러 테스트
- 근거: https://pkg.go.dev/net/http#ResponseWriter

### GO-HTTP-12 · 쿠키 인증 API 의 CSRF 방어를 토큰 미들웨어로 직접 구현한다
- 적용: Go 1.25+, 브라우저 쿠키 세션을 쓰는 상태 변경 엔드포인트
- 신호: 직접 만든 CSRF 토큰 미들웨어, 또는 방어 없음
- 메커니즘: `http.CrossOriginProtection` 은 `Sec-Fetch-Site`/`Origin` 헤더로 안전하지 않은 메서드의 교차 출처 브라우저 요청을 거부한다 — 토큰·쿠키 불필요, 출처/패턴 기반 예외 지원.
- 처방: `cop := http.NewCrossOriginProtection(); handler = cop.Handler(mux)`; 신뢰 출처는 `AddTrustedOrigin`.
- 반례: Bearer 토큰(헤더) 인증 API 는 CSRF 대상이 아님. 오래된 브라우저 지원이 필요한 경우 문서의 동작 조건 확인.
- 검증: 교차 출처 POST 가 403 인지 테스트
- 근거: https://pkg.go.dev/net/http#CrossOriginProtection · https://go.dev/doc/go1.25

### GO-HTTP-13 · go-elasticsearch 클라이언트가 429 를 재시도하지 않고, bulk 부분 실패(HTTP 200)를 성공으로 처리한다
- 적용: `github.com/elastic/go-elasticsearch/v8` (esapi/typed client, `esutil.BulkIndexer`) 로 색인·검색하는 서비스
- 신호: 피크 색인 시 `es_rejected_execution_exception`(429) 이 그대로 에러로 올라옴; 색인 건수 < 원본 건수인데 에러 로그 없음; Bulk 호출 후 `res.StatusCode`/`res.IsError()` 만 확인
- 메커니즘: (1) `Config.RetryOnStatus` 기본값은 502·503·504 뿐이라 write/search 스레드풀 큐 포화로 나는 429 는 재시도되지 않는다(`MaxRetries` 기본 3, `RetryBackoff` 기본 nil = 대기 없이 즉시 재시도). (2) Bulk API 는 일부 문서가 실패해도 HTTP 200 에 응답 바디 `errors: true` 와 항목별 `status`/`error` 를 준다 — 상태 코드만 보면 문서가 조용히 유실된다. (3) `AutoDrainBody` 기본 false — 응답 Body 를 끝까지 읽고 닫지 않으면 커넥션이 재사용되지 않는다(GO-HTTP-03 과 동일).
- 처방: `RetryOnStatus: []int{429, 502, 503, 504}` + `RetryBackoff: func(i int) time.Duration { /* 지수 + 지터, 상한 */ }`. Bulk 는 `esutil.BulkIndexer` 의 항목별 `OnFailure` 콜백(그리고 `BulkIndexerStats.NumFailed`)으로 실패를 집계·재처리하거나, 직접 호출이면 응답의 `errors` 플래그와 각 item `status` 를 검사해 429 항목만 재큐잉. 모든 `esapi.Response` 는 `defer res.Body.Close()` 하고, 바디를 다 읽지 않는 경로가 있으면 `AutoDrainBody: true`.
- 반례: 429 를 무한·무지연 재시도하면 클러스터 과부하를 증폭한다 — 백오프 상한·재시도 횟수 제한 필수. 400(mapping 오류) 같은 항목 실패는 재시도해도 같은 결과이므로 DLQ 로.
- 검증: 스테이징에서 `thread_pool.write.queue_size` 를 작게 잡아 429 유발 → 재시도 로그·최종 색인 건수가 원본과 일치하는지; `_cat/thread_pool/write?v` 의 `rejected` 증가와 클라이언트 실패 카운터 대조
- 근거: https://pkg.go.dev/github.com/elastic/go-elasticsearch/v8#Config · https://pkg.go.dev/github.com/elastic/go-elasticsearch/v8/esutil#BulkIndexerItem · https://www.elastic.co/guide/en/elasticsearch/reference/current/docs-bulk.html
- 참고: ES 쿼리·매핑·클러스터 쪽 함정은 `search` 플러그인 `es-deep-patterns` 소관(Go 클라이언트 함정 전체는 `references/client-go.md` ES-CLI-10~13) — 이 항목은 Go 클라이언트 동작만 다룬다.
