# 통합 테스트 · 데이터 · flaky 함정 (스택 공통)

ES 운영 지식(refresh 비용, 샤드 설계)은 `es-deep-patterns` 레퍼런스, DB 드라이버 세부는 각 스택 가이드 참조.

### TST-INT-01 · ES 는 near-real-time — 색인 직후 검색은 0건일 수 있다
- 적용: 색인 → 검색을 연속 수행하는 통합 테스트
- 신호: 로컬은 가끔 그린, CI 에서 0건 / 이전 데이터 기준 결과
- 메커니즘: 문서는 refresh(기본 `index.refresh_interval` 1s, 단 검색 요청이 없던 인덱스는 search idle 상태로 refresh 를 건너뜀) 이후에만 검색에 보인다. GET-by-id 는 실시간이라 "저장은 됐다"고 오판하기 쉽다.
- 처방: 테스트 셋업 색인에 `refresh=wait_for`(또는 셋업 끝에 `POST /<index>/_refresh` 1회). 운영 코드에 `refresh=true` 를 넣어 테스트를 통과시키지 말 것(ES-IDX-05).
- 반례: refresh 자체를 검증하는 테스트가 아니라면 `Thread.sleep`/`time.Sleep` 폴링은 금지 — 느리고 여전히 flaky.
- 검증: 셋업 직후 `_count` assert.
- 근거: https://www.elastic.co/guide/en/elasticsearch/reference/current/near-real-time.html · https://www.elastic.co/guide/en/elasticsearch/reference/current/docs-refresh.html

### TST-INT-02 · 랭킹 assert 가 가끔 깨진다 = 샤드별 IDF
- 적용: 검색 결과 **순서·점수**를 assert 하는 테스트, 프라이머리 샤드 2개 이상 테스트 인덱스
- 신호: 같은 데이터인데 1·2위가 실행마다 바뀜, 적은 문서 수에서 특히 심함
- 메커니즘: BM25 의 IDF·평균 필드 길이는 기본(`query_then_fetch`)으로 샤드 로컬 통계를 쓴다. 문서가 적으면 샤드 간 통계 편차가 커서 점수가 달라진다. 동점은 내부 문서 순서에 좌우된다.
- 처방: 테스트 인덱스는 `number_of_shards: 1`, 또는 해당 테스트만 `search_type=dfs_query_then_fetch`. 동점 가능성이 있으면 tie-breaker sort(`_score` 다음 고유 필드).
- 반례: 운영에 `dfs_query_then_fetch` 를 일괄 적용하지 말 것 — 라운드트립 추가 비용.
- 검증: 같은 테스트 20회 반복.
- 근거: https://www.elastic.co/guide/en/elasticsearch/reference/current/search-search.html#search-type · https://www.elastic.co/blog/practical-bm25-part-1-how-shards-affect-relevance-scoring-in-elasticsearch

### TST-INT-03 · ES 8 Testcontainers 는 보안·HTTPS 가 켜진 채 뜬다
- 적용: Testcontainers `ElasticsearchContainer` + ES 8.x 이미지
- 신호: 연결 거부, SSL handshake 실패, 401
- 메커니즘: ES 8+ 이미지는 보안과 HTTPS 가 기본 활성. 7.x 시절 HTTP 무인증 클라이언트 설정이 그대로면 실패한다.
- 처방: 클라이언트에 `container.createSslContextFromCa()` 로 만든 SSLContext + 기본 계정 자격증명, 또는 테스트 한정으로 `xpack.security.transport.ssl.enabled=false`, `xpack.security.http.ssl.enabled=false` env. 운영과 같은 보안 경로를 검증하려면 전자.
- 반례: 보안을 끈 테스트는 인증·TLS 설정 버그를 못 잡는다.
- 검증: 컨테이너 기동 후 `_cluster/health` 호출.
- 근거: https://java.testcontainers.org/modules/elasticsearch/

### TST-INT-04 · 컨테이너는 테스트 클래스마다 재시작된다 — singleton 패턴
- 적용: Testcontainers(JUnit5 `@Testcontainers`/`@Container`, Kotest extension, testcontainers-go, testcontainers-python)
- 신호: 스위트 시간 대부분이 컨테이너 기동, 클래스 수에 비례 증가
- 메커니즘: 클래스 필드의 `@Container` 는 클래스 단위 수명이다. 여러 클래스가 같은 DB 를 쓰면 매번 새로 띄운다. Spring 과 결합하면 포트가 바뀌어 컨텍스트 캐시(TST-JVM-01)도 깨진다.
- 처방: 추상 베이스/공유 object 의 static 블록에서 한 번 `start()` 하는 singleton container 패턴(종료는 Ryuk 이 처리). 로컬 반복 개발은 `withReuse(true)` + `~/.testcontainers.properties` 의 `testcontainers.reuse.enable=true`.
- 반례: reuse 는 CI 에 쓰지 말 것 — 이전 실행 데이터가 남는다. 컨테이너를 공유하면 데이터 격리(스키마/인덱스 접두어/정리)는 별도로 필요.
- 검증: 스위트 로그의 컨테이너 기동 횟수.
- 근거: https://java.testcontainers.org/test_framework_integration/manual_lifecycle_control/#singleton-containers · https://java.testcontainers.org/features/reuse/

### TST-INT-05 · 시간대: 로컬 KST, CI UTC — 날짜 경계 테스트가 CI 에서만 깨진다
- 적용: "오늘", 월말, 일 단위 집계, `LocalDate.now()`/`time.Now()`/`new Date()` 를 쓰는 코드
- 신호: 한국 시간 오전 9시 이전(= UTC 전날)에만 실패, 또는 CI 에서만 실패
- 메커니즘: 시스템 기본 시간대가 환경마다 다르다. KST(UTC+9)는 UTC 와 날짜가 9시간 동안 다르다.
- 처방: 현재 시각은 주입(`java.time.Clock`, Go 는 `func() time.Time`/인터페이스, Python 은 인자 기본값)하고 테스트에서 고정값. 시간대는 비즈니스 규칙으로 명시(`ZoneId.of("Asia/Seoul")`). 테스트 JVM 은 `-Duser.timezone`, Go/Node/Python 은 `TZ` 로 고정해 재현.
- 반례: 시간대 변환 자체를 검증하는 테스트는 여러 TZ 로 반복 실행.
- 검증: `TZ=UTC` 와 `TZ=Asia/Seoul` 두 번 실행.
- 근거: https://docs.oracle.com/en/java/javase/21/docs/api/java.base/java/time/Clock.html

### TST-INT-06 · 순서를 보장하지 않는 것을 순서로 assert
- 적용: `ORDER BY` 없는 SQL 결과, Go map 순회, `HashMap`/`HashSet`/`toSet()` 결과, 병렬 처리 결과 리스트
- 신호: 데이터가 늘거나 실행 계획이 바뀌면(병렬 스캔·인덱스 변경) 실패, Go 는 실행마다 다름
- 메커니즘: SQL 표준상 `ORDER BY` 없는 결과 순서는 정의되지 않는다(Postgres 는 병렬 seq scan·synchronized scan 으로 실제로 바뀐다). Go 는 map 순회 순서를 의도적으로 무작위화한다.
- 처방: 순서가 요구사항이면 코드에 `ORDER BY`/정렬을 넣고 테스트, 아니면 순서 무관 비교(Kotest `shouldContainExactlyInAnyOrder`, Go `slices.Sort` 후 비교 또는 `cmpopts.SortSlices`, Jest `expect.arrayContaining` + 길이).
- 반례: 없음.
- 검증: 데이터 수를 늘려 반복 실행.
- 근거: https://www.postgresql.org/docs/current/queries-order.html · https://go.dev/ref/spec#For_range
