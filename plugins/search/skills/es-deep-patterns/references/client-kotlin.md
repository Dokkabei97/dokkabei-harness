# Kotlin/Java 클라이언트 (ES-CLI)

> 적용 전 확인: 빌드 파일(`build.gradle.kts`)의 `co.elastic.clients:elasticsearch-java` 버전과 서버 버전, 트랜스포트(8.x 는 `RestClient`(Apache HC4), 9.x 기본은 `Rest5Client`(Apache HC5) — 레거시 RestClient 도 선택 가능), Spring Data Elasticsearch 사용 여부, 코루틴/WebFlux 사용 여부. 프로젝트 컨벤션이 있으면 그것이 우선.

### ES-CLI-01 · 클라이언트는 forward-compatible — 서버 먼저 올리고 클라이언트는 같거나 낮은 마이너로
- 적용: elasticsearch-java 8.x/9.x
- 신호: 서버 8.x 인데 클라이언트 9.x, 또는 서버 업그레이드 전에 클라이언트만 올림 → 미지원 필드/엔드포인트 에러
- 메커니즘: 클라이언트는 같거나 더 높은 마이너 서버와 통신 가능. 9.x 브랜치는 9.x 서버, 8.x 브랜치는 8.19 까지 지원
- 처방: 서버 → 클라이언트 순 업그레이드, 버전을 BOM/버전 카탈로그 한 곳에서 관리. Spring Boot 사용 시 Boot 가 관리하는 버전을 우선 확인
- 반례: 없음
- 검증: `GET /` 버전 vs 의존성 트리(`./gradlew dependencies --configuration runtimeClasspath | grep elasticsearch`)
- 근거: https://www.elastic.co/docs/reference/elasticsearch/clients/java

### ES-CLI-02 · 레거시 RestClient 기본 커넥션 풀은 노드당 10, 전체 30 — 고동시성 서비스의 숨은 큐
- 적용: `RestClient`(HC4) 기반 트랜스포트(8.x 기본, 9.x 레거시 선택 시). `RestClientBuilder` 기본 connect 1s, socket 30s
- 신호: ES `took` 은 짧은데 애플리케이션 측 지연이 길다, 부하 시 지연이 계단식 증가
- 메커니즘: 풀을 초과한 요청은 커넥션을 기다리며 대기 → ES 메트릭에 안 보이는 대기 시간
- 처방: `setHttpClientConfigCallback { it.setMaxConnPerRoute(n).setMaxConnTotal(m) }` 를 서비스 동시성에 맞춰 설정. 9.x `Rest5Client` 는 HC5 기반으로 설정 API·기본값이 다르니 빌더 문서를 확인
- 반례: 풀만 키우면 ES 스레드풀 거부(ES-JVM-05)로 문제가 이동 — 동시성 상한은 서버 용량 기준으로
- 검증: 클라이언트 측 지연 − `took` 차이, 커넥션 풀 메트릭(leased/pending)
- 근거: https://artifacts.elastic.co/javadoc/org/elasticsearch/client/elasticsearch-rest-client/6.2.4/constant-values.html (상수 값; 사용 버전 javadoc 으로 재확인), https://www.elastic.co/docs/reference/elasticsearch/clients/java/transport

### ES-CLI-03 · 클라이언트 socket timeout < 서버 `timeout` 이면 서버는 계속 일한다
- 적용: 검색 API 에 `timeout` 을 쓰거나 클라이언트 타임아웃을 짧게 둔 서비스
- 신호: 클라이언트 타임아웃 후 재시도 → ES CPU 가 더 오름(같은 무거운 쿼리가 중복 실행), `_tasks` 에 같은 쿼리 다수
- 메커니즘: 검색 `timeout` 은 샤드별 best-effort 이며 부분 결과(`timed_out: true`)를 돌려준다(ES-QRY-13). 클라이언트가 먼저 끊으면 — 취소 가능한 검색은 HTTP 연결 종료 시 태스크 취소가 시도되지만 협조적이라 즉시 멈추지 않고, 프록시 경유·취소 불가 API 에선 계속 실행된다 — 그 위에 재시도가 겹쳐 부하를 증폭
- 처방: 서버 `timeout` < 클라이언트 socket timeout < 상위 호출 타임아웃 순서로 계층화. 무거운 검색의 맹목 재시도 금지, 응답의 `timed_out` 을 확인해 부분 결과 처리
- 반례: 저지연 자동완성처럼 결과보다 응답 시간이 중요한 경로는 짧은 타임아웃 + 재시도 없음
- 검증: `GET _tasks?actions=*search*&detailed`, 클라이언트 타임아웃 로그와 ES slowlog 대조
- 근거: https://www.elastic.co/docs/solutions/search/the-search-api (search timeout), https://www.elastic.co/docs/reference/elasticsearch/clients/java/transport

### ES-CLI-04 · bulk 응답은 200 이어도 아이템 실패가 있다 — 실패를 상태 코드로 분류
- 적용: 모든 bulk 경로(BulkRequest, BulkIngester)
- 신호: `response.errors()` 미확인, 또는 모든 실패를 일괄 재시도/일괄 DLQ
- 메커니즘: bulk 는 아이템별 결과를 반환. 429(거부·브레이커)는 일시적, 400 계열(`mapper_parsing_exception`, `document_parsing_exception`)은 재시도해도 실패, 409 는 버전 충돌
- 처방: `errors()` true 면 아이템을 순회해 429 → 백오프 재시도, 4xx 파싱 오류 → DLQ(원본+에러), 409 → 외부 버전 사용 시 정상 무시(ES-ING-01)
- 반례: 없음
- 검증: 의도적으로 잘못된 타입 문서를 섞은 통합 테스트(Testcontainers)
- 근거: https://www.elastic.co/docs/reference/elasticsearch/clients/java/usage/indexing-bulk

### ES-CLI-05 · BulkIngester 기본값: 1,000 ops / 5MiB / 동시 요청 1 — `add()` 가 블록된다
- 적용: elasticsearch-java `BulkIngester`
- 신호: 기본값 그대로 사용하면서 처리량 부족, 코루틴 안에서 `add()` 호출로 스레드 블로킹
- 메커니즘: 동시 요청 한도에 도달하면 `add()` 가 블록(배압). `flushInterval` 은 기본 없음 → 저트래픽 시 버퍼가 오래 머문다. 리스너의 `afterBulk` 는 성공/실패 두 오버로드(요청 자체 실패 포함)
- 처방: `maxOperations`/`maxSize`/`maxConcurrentRequests`/`flushInterval` 명시, 리스너에서 ES-CLI-04 분류. 코루틴에서는 `Dispatchers.IO` 경계 안에서 호출하거나 자체 채널 + 동기 bulk 로 배압을 명시적으로 설계. 종료 시 `close()` 로 잔여 flush
- 반례: Kafka 오프셋과 묶어야 하는 경로에선 비동기 ingester 보다 "poll 단위 동기 bulk → 커밋" 이 단순·안전(ES-ING-03)
- 검증: 리스너 메트릭(배치 크기, 소요, 실패 수)
- 근거: https://www.elastic.co/docs/reference/elasticsearch/clients/java/usage/indexing-bulk

### ES-CLI-06 · 동기 클라이언트를 코루틴에서 쓰면 `withTimeout` 이 호출을 끊지 못한다
- 적용: Kotlin 코루틴 + `ElasticsearchClient`(blocking)
- 신호: `withTimeout(500) { withContext(Dispatchers.IO) { client.search(...) } }` 인데 실제 대기가 socket timeout(30s)까지 감
- 메커니즘: 코루틴 취소는 협조적이라 블로킹 I/O 를 중단시키지 않는다 — 호출이 끝난 뒤에야 취소 예외가 난다. 또 `Dispatchers.Default` 에서 블로킹 호출을 하면 CPU 풀이 고갈
- 처방: `ElasticsearchAsyncClient` + `kotlinx.coroutines.future.await()`(코루틴 취소 시 CompletableFuture 도 취소됨) 사용, 실제 HTTP 중단 여부는 사용하는 트랜스포트로 확인. 또는 트랜스포트 socket timeout 자체를 경로별로 설정(`RequestOptions`/`TransportOptions`)
- 반례: 배치 잡처럼 지연 허용 경로는 IO 디스패처 + 동기 클라이언트로 충분
- 검증: ES 를 지연시키는 toxiproxy/Testcontainers 테스트에서 실제 반환 시간 측정
- 근거: https://kotlinlang.org/api/kotlinx.coroutines/kotlinx-coroutines-core/kotlinx.coroutines.future/await.html, https://kotlinlang.org/docs/cancellation-and-timeouts.html

### ES-CLI-07 · 커스텀 ObjectMapper 를 `JacksonJsonpMapper` 에 넘기면 기본 `NON_NULL` 이 사라진다 — Kotlin 모듈과 함께 직접 설정
- 적용: Kotlin data class 를 `_source` 타입으로 사용(Kotlin 모듈 때문에 커스텀 매퍼가 사실상 필수)
- 신호: (1) `InvalidDefinitionException: ... no Creators, like default constructor` — Kotlin 모듈 누락. (2) partial `update` 후 다른 필드가 `null` 로 지워짐, `_source` 에 `"field": null` 이 가득. (3) 매핑에 필드를 추가한 뒤 구 버전 앱에서 `UnrecognizedPropertyException`
- 메커니즘: 무인자 `JacksonJsonpMapper()` 는 내부 ObjectMapper 에 `setSerializationInclusion(NON_NULL)` 을 건다. `JacksonJsonpMapper(objectMapper)` 는 넘긴 매퍼에 `ACCEPT_SINGLE_VALUE_AS_ARRAY` 만 추가하므로 NON_NULL 이 빠지고 → nullable 프로퍼티가 명시적 `null` 로 직렬화돼 부분 update 문서가 기존 값을 덮어쓴다. `FAIL_ON_UNKNOWN_PROPERTIES` 는 어느 생성자도 끄지 않으며 Jackson 기본은 true
- 처방: `JacksonJsonpMapper(jacksonObjectMapper().registerModule(JavaTimeModule()).setSerializationInclusion(JsonInclude.Include.NON_NULL).configure(DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES, false))` — 또는 `_source` 타입에 `@JsonIgnoreProperties(ignoreUnknown = true)`. Spring 의 ObjectMapper 를 재사용한다면 그 설정(NON_NULL 여부)을 확인. 날짜 포맷은 매핑 `format` 과 일치(epoch vs ISO). 의도적으로 필드를 지우는 update 는 별도 DTO/스크립트로
- 반례: 필드를 `null` 로 명시 초기화하는 것이 의도인 전체 문서 index 경로
- 검증: 왕복(serialize→index→get) 테스트 + 부분 update 후 미포함 필드가 보존되는지 확인 테스트, 모르는 필드가 추가된 `_source` 역직렬화 테스트
- 근거: https://github.com/elastic/elasticsearch-java/blob/main/java-client/src/main/java/co/elastic/clients/json/jackson/JacksonJsonpMapper.java (생성자별 설정), https://www.elastic.co/docs/reference/elasticsearch/clients/java/setup/connecting, https://github.com/FasterXML/jackson-module-kotlin

### ES-CLI-08 · Spring Data Elasticsearch 의 자동 인덱스 생성은 운영 매핑을 오염시킨다
- 적용: `@Document` 엔티티 사용 서비스
- 신호: 운영 인덱스가 애플리케이션 기동 시 동적 매핑으로 생성됨, alias 대신 실제 인덱스명 하드코딩
- 메커니즘: `@Document(createIndex = true)`(기본)면 리포지토리 초기화 시 인덱스가 없으면 엔티티 기반 매핑으로 생성 — 분석기·템플릿이 빠진 인덱스가 먼저 생겨버린다
- 처방: `createIndex = false`, 인덱스·템플릿은 마이그레이션 단계(인프라 코드/스크립트)에서 생성, `@Document(indexName = "alias명")` 으로 alias 접근
- 반례: 로컬 개발 프로파일에선 자동 생성이 편리 — 프로파일로 분리
- 검증: 빈 클러스터에서 기동 후 `GET _cat/indices`
- 근거: https://docs.spring.io/spring-data/elasticsearch/reference/elasticsearch/object-mapping.html

### ES-CLI-09 · 쿠버네티스/클라우드 환경에서 sniffing 은 끈다
- 적용: LB/Ingress/Cloud 엔드포인트 뒤의 클러스터
- 신호: Sniffer 가 내부 publish_address(접근 불가 IP)를 받아 연결 실패
- 메커니즘: sniff 는 노드가 광고하는 주소로 직접 연결 — 프록시/서비스 경유 환경과 충돌
- 처방: 단일 서비스 엔드포인트(또는 노드 목록 고정) 사용, sniffer 미사용
- 반례: 클라이언트가 노드에 직접 라우팅 가능한 self-managed 네트워크
- 검증: 클라이언트 연결 대상 로그
- 근거: https://www.elastic.co/docs/reference/elasticsearch/clients/java/transport/rest-client/sniffer
