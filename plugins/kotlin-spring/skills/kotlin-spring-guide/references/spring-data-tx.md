# Spring 트랜잭션·JPA·커넥션 풀 (SPR-TX, SPR-JPA, SPR-POOL)

> 먼저 확인: `build.gradle.kts` 의 Spring Boot/Framework 버전, 데이터 접근 기술(JPA/Hibernate·jOOQ·JdbcTemplate·R2DBC·Exposed),
> DB 종류, Kotlin 컴파일러 플러그인(`plugin.spring`, `plugin.jpa`, `allOpen`), `application.yml` 의 `spring.jpa.*`·`spring.datasource.hikari.*`.
> JPA 를 쓰지 않는 프로젝트면 SPR-JPA 는 건너뛴다.

### SPR-TX-01 · Kotlin final 클래스와 프록시 — `plugin.spring` 과 엔티티 allOpen
- 적용: Kotlin + 프록시 기반 AOP(@Transactional, @Cacheable, @Async), Hibernate 엔티티.
- 신호: 빌드에 `kotlin("plugin.spring")` 이 없으면 기동 시 CGLIB 가 final 클래스를 상속하지 못해 실패. `kotlin("plugin.jpa")` 만 있고 엔티티 allOpen 이 없으면 `@ManyToOne(fetch = LAZY)` 인데 즉시 로딩 SQL 이 나가고 프록시 생성 실패 경고가 찍힌다.
- 메커니즘: Kotlin 클래스·메서드는 기본 final. `plugin.spring`(all-open)은 `@Component`·`@Async`·`@Transactional`·`@Cacheable`·`@SpringBootTest`(및 이를 메타 애노테이션으로 가진) 클래스를 open 한다. `plugin.jpa` 는 no-arg 생성자만 만들고 open 하지 않는다 → 엔티티 lazy to-one 프록시를 만들 수 없다.
- 처방: `allOpen { annotation("jakarta.persistence.Entity"); annotation("jakarta.persistence.MappedSuperclass"); annotation("jakarta.persistence.Embeddable") }`.
- 반례: Hibernate 바이트코드 enhancement 를 쓰는 프로젝트는 lazy 메커니즘이 다르다 — 빌드 설정 확인.
- 검증: `@DataJpaTest` 에서 `Hibernate.isInitialized(order.member) == false`, SQL 로그.
- 근거: https://kotlinlang.org/docs/all-open-plugin.html#spring-support , https://kotlinlang.org/docs/no-arg-plugin.html#jpa-support , https://spring.io/guides/tutorials/spring-boot-kotlin

### SPR-TX-02 · 자기 호출·가시성 — 그리고 Spring 6 에서 바뀐 점
- 적용: 프록시 모드(기본)의 @Transactional/@Cacheable/@Async.
- 신호: 같은 클래스 안에서 애노테이션 메서드를 호출, private 메서드에 애노테이션.
- 메커니즘: 프록시를 거친 외부 호출만 가로챈다. Spring 6.0 부터 CGLIB 클래스 프록시에선 protected·package-visible 메서드도 트랜잭션이 적용된다(이전엔 public 만). private 은 여전히 불가. Kotlin `internal` 은 바이트코드상 public(이름 맹글링).
- 처방: 트랜잭션 경계를 별도 빈으로 분리하거나 `TransactionTemplate`(`transactionTemplate.execute { ... }`)으로 프로그래밍 방식 사용 — 자기 호출 문제 자체가 사라진다.
- 반례: AspectJ 위빙 모드 프로젝트는 해당 없음.
- 검증: 테스트에서 `TransactionSynchronizationManager.isActualTransactionActive()` assert, `logging.level.org.springframework.transaction.interceptor=TRACE`.
- 근거: https://docs.spring.io/spring-framework/reference/data-access/transaction/declarative/annotations.html

### SPR-TX-03 · Kotlin 에는 checked 예외가 없지만 Spring 롤백 규칙엔 있다
- 적용: Kotlin 에서 `Exception`/`IOException` 계열(RuntimeException 이 아닌) 예외를 던지는 서비스.
- 신호: `class PaymentFailedException : Exception()`. 실패했는데 DB 에 반영됨.
- 메커니즘: 기본 롤백 대상은 RuntimeException 과 Error 뿐이다. Kotlin 컴파일러는 checked 를 강제하지 않아 이 구분을 놓치기 쉽다.
- 처방: 커스텀 예외는 RuntimeException 상속. Spring 6.2+ 는 `@EnableTransactionManagement(rollbackOn = RollbackOn.ALL_EXCEPTIONS)` — javadoc 이 Kotlin 앱에 권장한다(직접 선언하면 Boot 기본 구성 대신 적용됨).
- 반례: 의도적으로 커밋시키는 비즈니스 예외가 있으면 `noRollbackFor` 로 명시.
- 검증: 예외 후 롤백되는지 통합 테스트.
- 근거: https://docs.spring.io/spring-framework/docs/current/javadoc-api/org/springframework/transaction/annotation/EnableTransactionManagement.html

### SPR-TX-04 · 내부 REQUIRED 실패를 잡아도 전체가 롤백된다
- 적용: 트랜잭션 메서드가 다른 @Transactional(REQUIRED) 메서드를 호출하고 그 예외를 catch.
- 신호: `UnexpectedRollbackException: Transaction silently rolled back because it has been marked as rollback-only`.
- 메커니즘: 내부 메서드가 RuntimeException 으로 빠져나가는 순간 인터셉터가 공유 트랜잭션을 rollback-only 로 표시한다. 외부에서 catch 해도 커밋 시점에 롤백.
- 처방: 부분 실패를 허용할 단위는 내부 메서드에 트랜잭션을 붙이지 않고 내부에서 예외를 처리. 독립 커밋이 필요하면 REQUIRES_NEW(커넥션 2개 — SPR-POOL-02). NESTED 는 savepoint 를 지원하는 매니저에서만.
- 반례: —
- 검증: 통합 테스트.
- 근거: https://docs.spring.io/spring-framework/reference/data-access/transaction/declarative/tx-propagation.html

### SPR-TX-05 · `readOnly` 의 실제 효과와 레플리카 라우팅 함정
- 적용: JpaTransactionManager + Hibernate, `AbstractRoutingDataSource` 로 읽기 레플리카 분기.
- 신호: readOnly 로 레플리카 라우팅을 기대했는데 항상 primary. 대량 조회 트랜잭션의 메모리 사용이 큼.
- 메커니즘: readOnly 면 Spring 이 Hibernate Session 을 FlushMode.MANUAL + 기본 read-only 로 설정 → 엔티티 스냅샷(dirty checking 용)을 보관하지 않아 메모리·CPU 절감. JDBC `Connection.setReadOnly(true)` 힌트도 준다. 그런데 커넥션은 트랜잭션 시작 시점, readOnly 플래그가 동기화되기 **전에** 획득되므로 `isCurrentTransactionReadOnly()` 로 고르는 라우팅은 항상 기본값을 본다.
- 처방: 라우팅 DataSource 를 `LazyConnectionDataSourceProxy` 로 감싸 첫 쿼리 시점까지 획득을 미룬다(최신 Spring 은 `setReadOnlyDataSource` 로 직접 지원 — 사용 버전 javadoc 확인). Spring Data JPA 기본 리포지토리 메서드는 이미 readOnly.
- 반례: readOnly 는 쓰기 차단을 보장하지 않는다(네이티브·벌크 쿼리는 통과 가능, DB 수준 READ ONLY 일 때만 차단).
- 검증: 쿼리가 실제로 레플리카에서 실행되는지 DB 측 확인(PostgreSQL `pg_is_in_recovery()`).
- 근거: https://docs.spring.io/spring-framework/docs/current/javadoc-api/org/springframework/jdbc/datasource/LazyConnectionDataSourceProxy.html

### SPR-JPA-01 · `open-in-view` 기본 true — 영속성 컨텍스트가 요청 끝까지 산다
- 적용: Spring Boot + JPA, `spring.jpa.open-in-view` 미설정(기동 시 WARN 로그가 이를 알린다).
- 신호: 컨트롤러·직렬화 중 lazy 로딩 SQL. 느린 외부 호출이 섞인 엔드포인트에서 Hikari 풀 고갈.
- 메커니즘: `OpenEntityManagerInViewInterceptor` 가 요청 내내 EntityManager 를 유지해 트랜잭션 밖(뷰·Jackson 직렬화)에서도 lazy 로딩이 일어나고, 커넥션 점유가 서비스 계층 경계를 넘어 길어진다(정확한 점유 범위는 Hibernate 커넥션 핸들링 모드에 따름).
- 처방: `spring.jpa.open-in-view=false` 로 두고 서비스 계층에서 fetch join/@EntityGraph 로 필요한 연관을 읽어 DTO 변환까지 끝낸다.
- 반례: 기존 대형 코드베이스는 끄는 순간 LazyInitializationException 이 쏟아진다 — 통합 테스트로 범위를 확인하고 단계적으로.
- 검증: Hikari `connections.usage` 히스토그램, 엔드포인트별 SQL 수.
- 근거: https://docs.spring.io/spring-boot/appendix/application-properties/index.html , https://vladmihalcea.com/the-open-session-in-view-anti-pattern/

### SPR-JPA-02 · 컬렉션 fetch join + 페이징 = 메모리에서 페이징
- 적용: `@OneToMany` fetch join(또는 컬렉션 @EntityGraph) + `Pageable`.
- 신호: 로그 `HHH90003004: firstResult/maxResults specified with collection fetch; applying in memory`(Hibernate 5 는 `HHH000104`). 20건 페이지 요청에 전체 행 로딩.
- 메커니즘: 조인 결과 행 수 ≠ 루트 엔티티 수라 SQL LIMIT 을 적용할 수 없어 전체를 읽은 뒤 메모리에서 자른다.
- 처방: `spring.jpa.properties.hibernate.query.fail_on_pagination_over_collection_fetch=true` 로 즉시 실패시키고, ID 만 페이징 → `where id in (:ids)` fetch join 의 2단계 쿼리, 또는 batch fetch(SPR-JPA-03).
- 반례: —
- 검증: SQL 로그에 LIMIT 존재 여부.
- 근거: https://docs.jboss.org/hibernate/orm/current/userguide/html_single/Hibernate_User_Guide.html

### SPR-JPA-03 · N+1 의 기본 해법은 batch fetch — 그리고 MultipleBagFetchException
- 적용: lazy 연관을 순회하는 조회.
- 신호: 같은 SELECT 가 N 번 반복(SQL 로그, Hibernate statistics). 두 개의 `List` 컬렉션을 함께 fetch join 하면 `MultipleBagFetchException: cannot simultaneously fetch multiple bags`.
- 메커니즘: `hibernate.default_batch_fetch_size`(또는 `@BatchSize`)는 lazy 초기화 시 같은 영속성 컨텍스트의 미초기화 프록시·컬렉션을 IN 절로 묶어 N+1 을 N/size+1 로 줄인다. 여러 bag 동시 fetch join 은 카테시안 곱이라 금지된다.
- 처방: 전역 batch fetch size(100 전후) + to-one 은 fetch join, to-many 는 batch fetch. 다중 컬렉션은 `Set` 으로 바꿔 예외만 피하지 말고(카테시안 곱은 그대로) 쿼리를 나눈다.
- 반례: batch fetch 는 영속성 컨텍스트 안에서만 묶인다 — 루프마다 `clear()` 하는 처리에선 효과가 줄어든다.
- 검증: `spring.jpa.properties.hibernate.generate_statistics=true`, 테스트에서 쿼리 수 assert(datasource-proxy 등).
- 근거: https://docs.jboss.org/hibernate/orm/current/userguide/html_single/Hibernate_User_Guide.html#fetching-batch

### SPR-JPA-04 · 대량 쓰기 — IDENTITY 는 JDBC 배치를 끄고, flush AUTO 는 O(n²) 이 된다
- 적용: 배치 적재·동기화 잡의 JPA 쓰기.
- 신호: `saveAll(10만건)` 이 행마다 INSERT 왕복. 루프 안의 JPQL 조회가 갈수록 느려지고 힙이 증가.
- 메커니즘: `GenerationType.IDENTITY` 는 INSERT 를 실행해야 ID 를 알 수 있어 Hibernate 가 insert 배치를 끈다. `hibernate.jdbc.batch_size` 가 없으면 배치 자체가 없다. FlushMode.AUTO 에선 JPQL·네이티브 쿼리 전에 영속성 컨텍스트 전체 dirty check + flush 가 일어나 컨텍스트가 커질수록 쿼리당 비용이 증가한다.
- 처방: (0단계: 마이그레이션 도구와 기존 ID 전략·시퀀스 정의를 먼저 확인) DB 가 시퀀스를 지원하면 SEQUENCE + pooled optimizer(allocationSize 50 등 — DB 시퀀스 `INCREMENT BY` 와 같게), `hibernate.jdbc.batch_size=50`, `hibernate.order_inserts=true`, `hibernate.order_updates=true`, N건마다 `flush(); clear()`. 드라이버 재작성 옵션(MySQL `rewriteBatchedStatements=true`, PostgreSQL `reWriteBatchedInserts=true`). 초대량은 JdbcTemplate `batchUpdate`/COPY.
- 반례: 기존 스키마에선 엔티티 매핑만 바꾸지 않는다 — DB 시퀀스 `INCREMENT BY` ≠ allocationSize 면 Hibernate 가 기동 시 실패하거나(`hibernate.id.sequence.increment_size_mismatch_strategy` 기본 EXCEPTION) 한쪽만 맞추면 ID 충돌·공백이 난다. 시퀀스 변경은 마이그레이션으로. 운영 중 테이블의 IDENTITY → SEQUENCE 전환은 별도 마이그레이션 계획(시퀀스 시작값 = 현재 max(id)+여유)이 필요하다.
- 검증: Hibernate statistics 의 JDBC batch 수, DB 쪽 실행 문장 수.
- 근거: https://docs.jboss.org/hibernate/orm/current/userguide/html_single/Hibernate_User_Guide.html#batch , https://jdbc.postgresql.org/documentation/use/

### SPR-JPA-05 · 할당 ID 엔티티의 `save()` 는 SELECT 후 INSERT (merge)
- 적용: Spring Data JPA, Kotlin 에서 `val id: UUID = UUID.randomUUID()` 처럼 생성 시 ID 를 채우는 엔티티.
- 신호: INSERT 전마다 같은 PK 의 SELECT, `saveAll` 이 기대의 절반 속도.
- 메커니즘: `SimpleJpaRepository.save` 는 `isNew` 판정을 한다 — 버전 속성(래퍼 타입)이 있으면 그 null 여부, 없으면 ID 가 null(원시 타입이면 0)인지. ID 가 이미 차 있으면 not-new → `em.merge` → SELECT.
- 처방: `Persistable<ID>` 구현(`@Transient` isNew 플래그를 `@PostPersist`/`@PostLoad` 에서 false 로) 또는 `@Version var version: Long? = null`.
- 반례: —
- 검증: SQL 로그.
- 근거: https://docs.spring.io/spring-data/jpa/reference/jpa/entity-persistence.html

### SPR-JPA-06 · 대량 조회 — 드라이버가 ResultSet 전체를 메모리에 올린다
- 적용: PostgreSQL(pgjdbc)·MySQL(Connector/J), 대량 export·배치 조회. JPA `Stream<T>`/Kotlin `Sequence` 로 받아도, JdbcTemplate 이어도 같다.
- 신호: 대량 SELECT 동안 힙 급증·OOM, 힙 덤프에 드라이버의 행 버퍼(`byte[][]` 등) 다수. "스트림으로 받았는데 왜 OOM?"
- 메커니즘: 기본값은 결과 전체 버퍼링이다. pgjdbc 는 autocommit=false + `fetchSize > 0` + forward-only ResultSet 일 때만 커서로 나눠 읽는다. Connector/J 는 `fetchSize = Integer.MIN_VALUE`(행 단위 스트리밍) 또는 `useCursorFetch=true` + `fetchSize > 0` 일 때만 나눠 읽는다. 게다가 JPA 영속성 컨텍스트가 읽은 엔티티를 모두 보관한다.
- 처방: `@Transactional(readOnly = true)` 안에서 fetch size 지정 — `hibernate.jdbc.fetch_size`, `JdbcTemplate.setFetchSize`, Spring Data `@QueryHints(QueryHint(name = HibernateHints.HINT_FETCH_SIZE, value = "1000"))` + `Stream` 반환(트랜잭션 필수, `use {}` 로 닫기). 처리하면서 주기적으로 `em.detach`/`clear()`, 또는 DTO 프로젝션·StatelessSession.
- 반례: 결과가 작으면 불필요. 스트리밍 동안 트랜잭션·커넥션을 계속 점유한다(SPR-POOL-01) — 느린 소비자(외부 호출)를 스트림 안에 두지 않는다. MySQL `Integer.MIN_VALUE` 스트리밍 중엔 같은 커넥션으로 다른 쿼리를 못 낸다.
- 검증: 같은 쿼리를 fetch size 유무로 실행하며 힙 사용량(JFR `jdk.GCHeapSummary`) 비교.
- 근거: https://jdbc.postgresql.org/documentation/query/#getting-results-based-on-a-cursor , https://dev.mysql.com/doc/connector-j/en/connector-j-reference-implementation-notes.html , https://docs.spring.io/spring-data/jpa/reference/repositories/query-methods-details.html

### SPR-POOL-01 · HikariCP 풀 크기 — 크게 잡을수록 느려진다
- 적용: HikariCP(Spring Boot 기본 풀).
- 신호: 인스턴스당 `maximumPoolSize` 100+ × 파드 수 → DB `max_connections` 압박과 DB CPU 컨텍스트 스위칭. 반대로 가상 스레드 도입 후 풀 대기(JVM-CONC-02).
- 메커니즘: HikariCP 위키의 출발점 공식은 `connections = (DB 서버 core_count × 2) + effective_spindle_count`. 모든 인스턴스 풀 합계가 DB 한도 안이어야 한다.
- 처방: 작은 풀에서 시작해 부하 테스트로 조정. 지표 `hikaricp.connections.pending`, `hikaricp.connections.acquire`.
- 반례: 긴 트랜잭션·원격 호출을 트랜잭션 안에서 하는 앱은 공식이 맞지 않는다 — 그 구조부터 고친다.
- 검증: 풀 크기별 부하 테스트 처리량·p99.
- 근거: https://github.com/brettwooldridge/HikariCP/wiki/About-Pool-Sizing

### SPR-POOL-02 · 스레드당 커넥션 2개 — REQUIRES_NEW 풀 교착
- 적용: REQUIRES_NEW, 트랜잭션 안에서 다른 DataSource/풀 호출.
- 신호: 부하가 오르면 모든 스레드가 `getConnection` 에서 대기하다 `connectionTimeout` 후 일제히 실패.
- 메커니즘: 외부 트랜잭션이 커넥션 1개를 쥔 채 두 번째를 요청한다. 동시 스레드 수 ≥ 풀 크기면 모두가 첫 커넥션만 쥐고 서로를 기다린다. 위키 공식: `pool size ≥ Tn × (Cm − 1) + 1`(Tn = 최대 스레드 수, Cm = 스레드당 최대 동시 커넥션).
- 처방: REQUIRES_NEW 최소화 — 감사 로그처럼 독립 커밋이 꼭 필요하지 않은 쓰기는 같은 트랜잭션에 넣거나 transactional outbox(같은 트랜잭션에 outbox INSERT 후 별도 발행). 원 트랜잭션 종료 후 실행이 필요하면 `@TransactionalEventListener(AFTER_COMMIT)` + `@Async` 로 다른 스레드에서(원 커넥션 반납 후) 실행. 그 밖엔 공식대로 풀 크기 산정, 진입 동시성 제한.
- 반례: 동기 `AFTER_COMMIT` 리스너는 대안이 아니다 — 원 트랜잭션 자원이 아직 바인딩된 상태라 그 안의 쓰기는 커밋되지 않고 조용히 사라지며, 커밋하려면 `@Transactional(propagation = REQUIRES_NEW)` 가 필요해(Spring 6.1+ 는 리스너에 REQUIRES_NEW/NOT_SUPPORTED 외 `@Transactional` 을 거부) 원 커넥션을 쥔 채 두 번째를 요청하는 같은 구조가 된다.
- 검증: 풀 크기 = 동시 스레드 수로 낮춘 부하 테스트에서 재현.
- 근거: https://github.com/brettwooldridge/HikariCP/wiki/About-Pool-Sizing , https://docs.spring.io/spring-framework/docs/current/javadoc-api/org/springframework/transaction/event/TransactionalEventListener.html

### SPR-POOL-03 · `maxLifetime` 은 DB·인프라 타임아웃보다 몇 초 짧게
- 적용: DB `wait_timeout`, NAT/프록시/LB idle 타임아웃이 있는 경로(AWS NLB TCP 기본 350초, 사내 방화벽).
- 신호: 간헐적 `Communications link failure`/`Connection reset`, Hikari 경고 `Failed to validate connection ... (This connection has been closed.)`, 유휴 후 첫 요청 실패.
- 메커니즘: 중간 장비가 먼저 끊으면 풀에 죽은 커넥션이 남는다. `maxLifetime` 기본 30분, `keepaliveTime` 은 최신 README 기준 2분(구버전은 기본 비활성).
- 처방: `maxLifetime` = 가장 짧은 인프라 타임아웃 − 수 초 이상, `keepaliveTime` 을 인프라 idle 보다 짧게. 사용 중인 Hikari 버전의 기본값을 확인.
- 반례: —
- 검증: 유휴 시간 > 인프라 타임아웃 후 요청 재현 테스트.
- 근거: https://github.com/brettwooldridge/HikariCP#gear-configuration-knobs-baby
