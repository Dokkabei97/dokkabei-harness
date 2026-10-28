# 분산 시스템 스페셜리스트 항목 (DIST)

영역: TMO 타임아웃 · RTY 재시도/서킷 · IDEM 멱등 · MSG 메시지 정합성 · CACHE 캐시 · NET 연결 · OBS 관측 · OPS 운영.

---

## TMO

### DIST-TMO-01 · 타임아웃은 호출 체인 전체의 "남은 예산" 으로 전파해야 한다
- 적용: A→B→C 다단 호출, 요청 경로 안의 DB·캐시·Kafka publish
- 신호: 상위가 이미 포기한 요청을 하위가 계속 처리(고아 작업), 하위 타임아웃 합 > 상위 타임아웃
- 메커니즘: 상위 1s 타임아웃 아래에서 하위가 각자 1s·재시도 3회를 가지면 상위가 실패한 뒤에도 하위 부하가 지속된다.
- 처방: 진입점에서 deadline 을 정하고 각 홉에 남은 시간만 넘긴다 — Go 는 `context.WithTimeout` 을 끝까지 전달(`http.NewRequestWithContext`, `db.QueryContext`), gRPC 는 deadline 자동 전파, Kotlin 코루틴은 `withTimeout` 이 하위 suspend 호출을 취소. HTTP 간에는 남은 예산 헤더를 팀 규약으로.
- 반례: 비동기 큐 뒤의 작업은 원 요청 deadline 과 분리.
- 검증: 하위 서비스 지연 주입 시 상위 실패 후 하위 처리 중단 여부.
- 근거: https://grpc.io/docs/guides/deadlines/ , https://pkg.go.dev/context

### DIST-TMO-02 · 주요 HTTP 클라이언트 기본값은 "타임아웃 없음"
- 적용: 외부/내부 HTTP 호출 전부
- 신호: 클라이언트 생성 시 타임아웃 미설정, Go `http.DefaultClient`/`http.Get`
- 메커니즘: Go `http.Client.Timeout` 기본 0(무제한), Java `java.net.http.HttpClient` 는 요청 타임아웃 미설정 시 무제한, Reactor Netty(WebClient) 는 `responseTimeout` 미설정, Spring `SimpleClientHttpRequestFactory`(RestTemplate 기본)는 연결·읽기 무제한, Python `requests` 는 무제한(httpx 는 기본 5s). 하위 하나가 멈추면 호출 스레드·코루틴·연결이 쌓여 풀 고갈로 번진다.
- 처방: 연결 타임아웃과 응답(전체) 타임아웃을 모두 명시. 상한값은 → [team-conventions.md](team-conventions.md) §타임아웃.
- 반례: 대용량 다운로드·스트리밍은 전체 타임아웃 대신 유휴(읽기) 타임아웃.
- 검증: 응답하지 않는 목 서버(accept 후 무응답)로 호출해 반환 시간 확인.
- 근거: https://pkg.go.dev/net/http#Client , https://docs.oracle.com/en/java/javase/21/docs/api/java.net.http/java/net/http/HttpRequest.Builder.html#timeout(java.time.Duration) , https://projectreactor.io/docs/netty/release/reference/http-client.html#timeout-configuration , https://www.python-httpx.org/advanced/timeouts/

### DIST-TMO-03 · k8s 종료: 엔드포인트 제거는 비동기 — preStop 지연 없이 즉시 종료하면 배포마다 5xx
- 적용: 롤링 배포되는 HTTP 서비스, Kafka 컨슈머
- 신호: 배포 시점에만 짧은 502/503·connection reset
- 메커니즘: 파드 종료 시 SIGTERM 과 엔드포인트/LB 제거가 병렬로 일어난다. 앱이 즉시 리스너를 닫으면 아직 라우팅되는 요청이 실패한다. Spring Boot 는 3.4 부터 graceful shutdown 이 기본(이전 버전은 `server.shutdown=graceful` 필요), Go 는 `http.Server.Shutdown(ctx)` 을 직접 호출해야 한다. 예산 부등식: `preStop 시간 + 앱 종료 단계 시간 < terminationGracePeriodSeconds` — 둘 다 기본 30s(`spring.lifecycle.timeout-per-shutdown-phase`, k8s grace period)라 preStop 을 더하는 순간 기본값 그대로면 SIGKILL 로 끝날 수 있다.
- 처방: `preStop` 에 수 초 sleep(또는 readiness 를 먼저 내리기) + 앱 graceful shutdown + `terminationGracePeriodSeconds` > preStop + 처리 시간. distroless/scratch 이미지(Go 서비스에 흔함)는 `sleep` 바이너리가 없어 `exec: ["sleep","5"]` preStop 이 실패한다 — k8s 내장 `lifecycle.preStop.sleep.seconds`(KEP-3960: 1.30 beta 기본 활성, 1.34 GA)를 쓴다. 컨슈머는 종료 시 `close()`/`wakeup()` 으로 그룹 이탈과 커밋.
- 반례: —
- 검증: 부하 중 롤링 배포를 반복하며 오류율 측정.
- 근거: https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/#pod-termination , https://docs.spring.io/spring-boot/reference/web/graceful-shutdown.html , https://pkg.go.dev/net/http#Server.Shutdown , https://kubernetes.io/docs/concepts/containers/container-lifecycle-hooks/ , https://www.kubernetes.dev/resources/keps/3960/

## RTY

### DIST-RTY-01 · 계층마다 재시도하면 곱으로 증폭된다 — 재시도는 한 계층, 그리고 예산으로
- 적용: 게이트웨이·서비스·클라이언트 라이브러리·SDK 가 각각 재시도
- 신호: 하위 장애 시 하위 유입 트래픽이 평시의 수 배~수십 배
- 메커니즘: 3계층 × 각 3회 시도 = 최대 27배. 장애 중인 하위를 회복 불가능하게 만든다(재시도 폭풍).
- 처방: 재시도는 가장 바깥(또는 가장 안쪽) 한 곳만. 재시도 예산(요청 대비 재시도 비율 상한, 예: 10% — gRPC retry throttling, Envoy retry budget) 적용. 클라이언트 SDK 의 숨은 재시도(AWS SDK, Lettuce 재연결, Kafka 프로듀서) 목록화. 남은 한 곳의 지수 백오프는 full jitter(`sleep = random(0, min(cap, base·2^attempt))`) — `base·2^n` 그대로면 같은 시각 실패한 클라이언트들이 같은 시각에 다시 몰린다(Resilience4j `IntervalFunction.ofExponentialRandomBackoff`, tenacity `wait_random_exponential`).
- 반례: —
- 검증: 하위 100% 실패 주입 시 하위 유입 RPS 배율.
- 근거: https://grpc.io/docs/guides/retry/#throttling-retry-attempts-and-hedged-rpcs , https://sre.google/sre-book/handling-overload/ (Retries 절) , https://aws.amazon.com/blogs/architecture/exponential-backoff-and-jitter/

### DIST-RTY-03 · Resilience4j: 기본 서킷은 최소 100회 호출 전에는 열리지 않고, Retry 가 가장 바깥에서 열린 서킷까지 재시도한다
- 적용: Resilience4j(Spring Boot 어노테이션)
- 신호: 저트래픽 엔드포인트에서 서킷이 한 번도 안 열림, `CallNotPermittedException` 이 재시도됨
- 메커니즘: 기본 `slidingWindowSize`=100, `minimumNumberOfCalls`=100, `failureRateThreshold`=50%, `waitDurationInOpenState`=60s, `slowCallDurationThreshold`=60s. 어노테이션 기본 순서는 `Retry(CircuitBreaker(RateLimiter(TimeLimiter(Bulkhead(fn)))))`.
- 처방: 트래픽에 맞게 윈도우·최소 호출 수 축소, slow call 임계를 SLO 로. Retry 의 `ignoreExceptions` 에 `CallNotPermittedException`, 4xx 성격 예외 추가.
- 반례: 고트래픽 경로는 기본 윈도우가 오히려 안정적.
- 검증: `/actuator/circuitbreakers`, 메트릭 `resilience4j_circuitbreaker_state`.
- 근거: https://resilience4j.readme.io/docs/circuitbreaker , https://resilience4j.readme.io/docs/getting-started-3

## IDEM

### DIST-IDEM-01 · 멱등 키는 비즈니스 쓰기와 같은 트랜잭션의 유니크 제약으로 — "먼저 조회 후 삽입" 은 경합에 진다
- 적용: 결제·주문 생성 등 재시도되는 비멱등 API, 중복 전달되는 이벤트 소비
- 신호: `if (!exists(key)) { process(); save(key) }`, Valkey `GET` 후 처리
- 메커니즘: 동시 요청 두 개가 둘 다 "없음" 을 본다. 처리와 키 기록이 분리되면 그 사이 장애로 중복 또는 누락.
- 처방: `INSERT INTO idempotency(key, status) ... ON CONFLICT DO NOTHING` 를 비즈니스 쓰기와 같은 트랜잭션에서 수행, 영향 행 0이면 저장된 응답 반환 / 처리 중이면 409. 응답 본문·상태를 저장하고 보존 기간(TTL) 정의. HTTP 는 `Idempotency-Key` 헤더(IETF 초안).
- 반례: 자연 멱등 연산(PUT 전체 교체, 상태를 절대값으로 설정)은 키 불필요.
- 검증: 같은 키로 동시 요청 N 개 → 부작용 1회 단언.
- 근거: https://datatracker.ietf.org/doc/draft-ietf-httpapi-idempotency-key-header/ , https://www.postgresql.org/docs/current/sql-insert.html#SQL-ON-CONFLICT

## MSG

### DIST-MSG-01 · DB 커밋 + Kafka publish 는 원자적이지 않다 — `AFTER_COMMIT` 리스너도 크래시 시 유실
- 적용: 상태 변경 후 이벤트 발행
- 신호: `@Transactional` 안의 `kafkaTemplate.send()`(롤백돼도 발행됨), `@TransactionalEventListener(AFTER_COMMIT)` 에서 발행(커밋 후 프로세스 종료 시 유실)
- 메커니즘: 두 시스템 간 이중 쓰기는 한쪽만 성공하는 창이 항상 있다.
- 처방: transactional outbox — 같은 트랜잭션에서 outbox 테이블에 이벤트 기록, 별도 릴레이(폴링 또는 CDC/Debezium)가 발행. 소비자는 멱등(DIST-IDEM-01). 순서가 필요하면 outbox 키를 Kafka 키로.
- 반례: 유실 허용 알림성 이벤트는 AFTER_COMMIT 발행으로 충분.
- 검증: 커밋 직후 kill 시나리오에서 이벤트 누락 0 단언.
- 근거: https://microservices.io/patterns/data/transactional-outbox.html , https://debezium.io/documentation/reference/stable/transformations/outbox-event-router.html

## CACHE

### DIST-CACHE-01 · 스탬피드: 키 단위 single-flight + 만료 전 확률적 갱신(XFetch)
- 적용: 비싼 원천 조회 + 높은 동시성 키
- 신호: 인기 키 만료 순간 DB 동시 쿼리 급증
- 메커니즘: 만료 순간 모든 요청이 동시에 미스→원천 조회.
- 처방: 프로세스 내 합치기 — Go `golang.org/x/sync/singleflight`, Caffeine `LoadingCache`/`AsyncCache.get(key, fn)`(키당 한 번 로드) + `refreshAfterWrite`(만료 전 백그라운드 갱신). 프로세스 간은 짧은 lease 락(VK-LOCK-01, 실패 시 stale 반환). 확률적 조기 만료: `now - delta * beta * ln(rand()) >= expiry` 이면 갱신(delta=재계산 시간, beta≈1). 배치 적재·워밍으로 같은 시각에 생성된 키는 같은 시각에 만료되므로 TTL 에 지터(예: ±10%)를 섞는다.
- 반례: 원천이 싸면 단순 TTL 로 충분.
- 검증: 인기 키 만료 순간 원천 호출 수 측정.
- 근거: https://pkg.go.dev/golang.org/x/sync/singleflight , https://github.com/ben-manes/caffeine/wiki/Refresh , https://cseweb.ucsd.edu/~avattani/papers/cache_stampede.pdf

### DIST-CACHE-02 · 캐시-DB 무효화 경합: "읽기 미스 → 구 값 조회 → (그 사이 쓰기+삭제) → 구 값 SET" 은 TTL 없이 영원히 stale
- 적용: cache-aside + 쓰기 시 삭제
- 신호: 드물게 갱신이 반영되지 않는 캐시, TTL 없는 캐시 키
- 메커니즘: 읽기 경로의 SET 이 쓰기 경로의 DEL 보다 늦게 도착하면 오래된 값이 남는다.
- 처방: 모든 캐시 키에 TTL(최후 안전망). 정합성이 중요하면 값에 버전/updated_at 을 담아 더 새로운 값만 덮어쓰기(Lua 비교), 또는 CDC 기반 무효화. 쓰기 경로는 "DB 커밋 후 삭제".
- 반례: —
- 검증: 동시 읽기/쓰기 퍼징 테스트로 stale 잔존 여부.
- 근거: https://www.usenix.org/system/files/conference/nsdi13/nsdi13-final170_update.pdf (Facebook memcache, leases)

## NET

### DIST-NET-01 · HTTP/2·gRPC 장수명 연결은 k8s Service(L4) 뒤에서 부하를 한 파드에 고정시킨다
- 적용: gRPC, HTTP/2, 커넥션 풀을 오래 유지하는 HTTP/1.1 클라이언트
- 신호: 스케일아웃 후에도 신규 파드 트래픽 0, 파드별 CPU 편차
- 메커니즘: kube-proxy 는 연결 단위로 분산한다. 연결이 재사용되는 한 요청은 기존 파드로만 간다.
- 처방: 서버 측 `MaxConnectionAge`(gRPC keepalive 정책)로 주기적 재연결, 클라이언트 측 L7 분산(headless Service + 클라이언트 LB) 또는 서비스 메시.
- 반례: 짧은 연결 위주 트래픽.
- 검증: 파드별 RPS 분포.
- 근거: https://kubernetes.io/blog/2018/11/07/grpc-load-balancing-on-kubernetes-without-tears/ , https://grpc.io/docs/guides/keepalive/

### DIST-NET-02 · Go `http.Transport` 는 호스트당 유휴 연결을 2개만 남긴다 — 단일 내부 호스트 고 QPS 에서 연결 churn
- 적용: Go 서비스가 소수 호스트(내부 API·게이트웨이·ES 노드)로 높은 동시성 HTTP/1.1 호출
- 신호: `http.DefaultClient`/`http.DefaultTransport` 또는 `MaxIdleConnsPerHost` 없이 만든 `&http.Transport{}`, 호출 측 `TIME_WAIT` 수천~수만, 간헐적 `connect: cannot assign requested address`(ephemeral port 고갈), p99 에 TLS 핸드셰이크 비용
- 메커니즘: `DefaultMaxIdleConnsPerHost = 2` 라 동시 요청 수십 개가 끝나면 2개만 풀에 남고 나머지는 닫힌다 — 다음 버스트에서 다시 연결(+TLS). 또한 응답 바디를 끝까지 읽고 `Close()` 하지 않으면 그 연결은 재사용되지 않는다(에러 응답 바디를 읽지 않고 버리는 코드가 흔한 원인).
- 처방: 공유 전용 Transport — `MaxIdleConnsPerHost` 를 예상 동시성 근처로, `MaxIdleConns`(전체 상한, 기본 100)·`IdleConnTimeout`(기본 transport 90s)을 함께 지정하고 클라이언트를 재사용. 응답 처리 후 `io.Copy(io.Discard, resp.Body); resp.Body.Close()`(바디가 매우 클 수 있으면 `io.LimitReader` 로 상한). 필요 시 `MaxConnsPerHost` 로 호스트 보호.
- 반례: 저 QPS 이거나 수많은 서로 다른 호스트로 흩어진 호출은 기본값으로 충분 — 유휴 연결을 크게 잡으면 상대 서버 연결 수만 늘린다. HTTP/2 호스트는 연결 하나에 다중화되므로 해당 없음(DIST-NET-01 참고).
- 검증: `httptrace.ClientTrace{GotConn: …}` 의 `GotConnInfo.Reused` 비율, 호출 측 `ss -s`/`ss -tan state time-wait | wc -l`.
- 근거: https://pkg.go.dev/net/http#DefaultMaxIdleConnsPerHost , https://pkg.go.dev/net/http#Transport , https://pkg.go.dev/net/http/httptrace#GotConnInfo

## OBS

### DIST-OBS-01 · 메트릭 라벨에 ID·원시 경로·에러 메시지를 넣으면 시계열이 폭발한다
- 적용: Micrometer/Prometheus/OTel 메트릭
- 신호: 태그 값에 userId, orderId, `request.requestURI`, 예외 메시지
- 메커니즘: 시계열 수 = 라벨 값 조합의 곱. TSDB 메모리·쿼리 비용이 비례 증가.
- 처방: 경로는 템플릿(`/orders/{id}`), ID 는 트레이스/로그로. Micrometer `MeterFilter.maximumAllowableTags` 로 상한. 
- 반례: 값 집합이 작고 고정된 라벨(상태 코드, 지역).
- 검증: `count by (__name__)({__name__=~".+"})` 로 메트릭별 시계열 수.
- 근거: https://prometheus.io/docs/practices/naming/#labels , https://docs.micrometer.io/micrometer/reference/concepts/meter-filters.html

### DIST-OBS-02 · 클라이언트 계산 백분위(summary)는 인스턴스 간 합칠 수 없다
- 적용: 지연 SLO 대시보드
- 신호: 파드별 p99 를 평균내어 서비스 p99 로 표시, Micrometer `publishPercentiles` 사용
- 메커니즘: 백분위의 평균은 백분위가 아니다. 히스토그램 버킷은 합산 후 `histogram_quantile` 로 계산 가능.
- 처방: `publishPercentileHistogram(true)`(또는 OTel 지수 히스토그램) + 서버 측 집계. SLO 임계값을 버킷 경계에 포함(`serviceLevelObjectives`).
- 반례: 단일 인스턴스 디버깅.
- 검증: 버킷 합산 p99 와 파드 p99 평균 비교.
- 근거: https://prometheus.io/docs/practices/histograms/ , https://docs.micrometer.io/micrometer/reference/concepts/histogram-quantiles.html

## OPS

### DIST-OPS-01 · liveness 프로브에 DB·외부 의존성을 넣으면 의존성 장애가 전 파드 재시작으로 번진다
- 적용: k8s 배포 서비스
- 신호: liveness 엔드포인트가 DB/Redis/Kafka 를 확인, DB 장애 시 CrashLoopBackOff
- 메커니즘: liveness 실패 = 컨테이너 재시작. 외부 장애는 재시작으로 고쳐지지 않고, 재기동 폭주가 회복을 방해한다.
- 처방: liveness 는 프로세스 자체 상태만, 의존성은 readiness 로(그것도 신중히 — 전 파드 동시 NotReady 위험). Spring Boot 는 `/actuator/health/liveness`·`/readiness` 그룹을 분리 제공.
- 반례: —
- 검증: 스테이징에서 DB 차단 시 파드 재시작 여부.
- 근거: https://docs.spring.io/spring-boot/reference/actuator/endpoints.html#actuator.endpoints.kubernetes-probes , https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/
