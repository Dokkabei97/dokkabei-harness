# 동시성 — 코루틴·가상 스레드·스레드 풀 (KT-CORO, JVM-CONC)

> 먼저 확인: 서블릿(MVC) vs WebFlux, 블로킹 드라이버(JDBC/JPA) vs 논블로킹(R2DBC), kotlinx.coroutines 버전,
> `spring.threads.virtual.enabled` 여부, JDK 버전(가상 스레드 pinning 은 JDK 24 에서 크게 바뀜).

### KT-CORO-01 · Dispatchers.IO 는 64 스레드 공용 풀 — 느린 의존 하나가 전부를 막는다
- 적용: kotlinx.coroutines 1.6+(`limitedParallelism`), 블로킹 클라이언트를 `withContext(Dispatchers.IO)` 로 감싼 코드.
- 신호: 동시 요청이 64 를 넘으면 지연이 계단식으로 증가. 스레드 덤프에 `DefaultDispatcher-worker-*` 가 모두 같은 소켓 read 에서 대기.
- 메커니즘: IO 병렬도 = max(64, 코어 수)(`kotlinx.coroutines.io.parallelism`). DB·외부 API·파일 I/O 가 같은 풀을 공유하므로 느린 외부 API 가 DB 호출까지 굶긴다.
- 처방: 의존별 벌크헤드 `val dbDispatcher = Dispatchers.IO.limitedParallelism(<커넥션 풀 크기>)`. IO 의 뷰는 64 상한과 별개로 탄력적으로 스레드를 늘린다(문서 예: 64 + 100 + 60). DB 뷰 병렬도를 Hikari `maximumPoolSize` 에 맞추면 풀 대기 대신 코루틴 큐잉이 된다.
- 반례: `Dispatchers.Default.limitedParallelism(n)` 은 Default 스레드 안에서 제한만 할 뿐 스레드를 늘리지 않는다 — 블로킹 용도로 쓰면 안 된다.
- 검증: 스레드 덤프, 의존별 지연 메트릭, 부하 테스트에서 한 의존을 지연시켜 다른 경로 영향 확인.
- 근거: https://kotlinlang.org/api/kotlinx.coroutines/kotlinx-coroutines-core/kotlinx.coroutines/-dispatchers/-i-o.html

### KT-CORO-02 · 요청 스레드의 `runBlocking`
- 적용: Spring MVC(서블릿)에서 suspend 라이브러리를 호출하는 코드.
- 신호: 컨트롤러/서비스의 `runBlocking { }`. 코루틴 안이나 Default 워커에서 중첩 `runBlocking` → 교착. 부하 시 Tomcat 워커(기본 max 200) 고갈.
- 메커니즘: `runBlocking` 은 호출 스레드를 이벤트 루프로 점유한다. 내부 작업이 끝날 때까지 요청 스레드가 묶여 이득이 없고, 내부에서 IO 로 옮기면 스레드를 2배 쓴다. Default 워커에서 호출하면 CPU 풀을 막아 내부 작업이 Default 를 기다릴 때 교착된다.
- 처방: Spring MVC 도 컨트롤러를 `suspend fun` 으로 선언할 수 있다(kotlinx-coroutines-reactor 필요). 아니면 블로킹 API 를 그대로 쓴다. `runBlocking` 은 main·테스트·브리지 최상단에만.
- 반례: 배치 진입점·CLI 최상단은 괜찮다.
- 검증: 스레드 덤프의 `BlockingCoroutine` 프레임.
- 근거: https://kotlinlang.org/api/kotlinx.coroutines/kotlinx-coroutines-core/kotlinx.coroutines/run-blocking.html , https://docs.spring.io/spring-framework/reference/languages/kotlin/coroutines.html

### KT-CORO-03 · `catch (e: Exception)`·`runCatching` 이 취소를 삼킨다
- 적용: suspend 호출을 감싼 예외 처리.
- 신호: `try { suspendCall() } catch (e: Exception) { log.error(...) }`, `runCatching { suspendCall() }`. 로그에 `JobCancellationException` 이 오류로 찍힘. 클라이언트가 끊었는데 DB 쓰기가 계속됨. 셧다운이 오래 걸림.
- 메커니즘: 취소는 `CancellationException` 으로 전달된다. 삼키면 취소된 코루틴이 다음 suspend 지점까지 계속 실행되고, 부모는 자식 완료를 기다려 구조적 동시성이 깨진다.
- 처방: `catch (e: CancellationException) { throw e }` 를 먼저 두거나 catch 뒤에 `currentCoroutineContext().ensureActive()`. suspend 경로에서 `runCatching` 을 쓰면 `onFailure` 에서 CancellationException 을 다시 던진다.
- 반례: suspend 가 없는 순수 코드의 runCatching 은 무관.
- 검증: `runTest` 에서 `job.cancel()` 후 부작용이 없음을 assert.
- 근거: https://kotlinlang.org/docs/cancellation-and-timeouts.html

### KT-CORO-04 · `withTimeout` 은 예외가 아니라 "취소"로 끝난다
- 적용: 외부 호출 타임아웃.
- 신호: 타임아웃 후 로그 없이 `launch` 블록이 조용히 종료. 블로킹 JDBC 호출이 타임아웃을 넘겨도 끊기지 않음.
- 메커니즘: `TimeoutCancellationException` 은 `CancellationException` 하위라 `launch` 에서 던져지면 정상 취소로 취급되어 예외 핸들러에 잡히지 않는다. 타임아웃은 suspend 지점에서만 동작한다 — 블로킹 호출 중에는 개입하지 못한다.
- 처방: 결과가 필요한 곳은 `withTimeoutOrNull` 로 받아 도메인 예외로 변환. 블로킹 호출은 드라이버 수준 타임아웃(JDBC `queryTimeout`, HTTP read timeout)을 함께 건다.
- 반례: —
- 검증: 지연 주입 테스트로 로그·메트릭이 남는지 확인.
- 근거: https://kotlinlang.org/api/kotlinx.coroutines/kotlinx-coroutines-core/kotlinx.coroutines/with-timeout.html

### KT-CORO-05 · MDC·SecurityContext·JPA 트랜잭션은 스레드에 붙어 있다
- 적용: 코루틴 + SLF4J MDC, Spring Security, Micrometer tracing, JPA(ThreadLocal 바인딩 트랜잭션).
- 신호: 코루틴 안 로그에 traceId/userId 누락. `withContext(Dispatchers.IO)` 이후 SecurityContext 가 비어 있음. `@Transactional` JPA 메서드 안 `withContext(Dispatchers.IO) { repo.save(x) }` 가 트랜잭션 밖에서 실행(롤백 안 됨, LazyInitializationException).
- 메커니즘: ThreadLocal 은 스레드 귀속인데 코루틴은 재개될 때 스레드가 바뀐다. `PlatformTransactionManager`(JPA)의 트랜잭션도 ThreadLocal 로 묶여 있다.
- 처방: MDC 는 kotlinx-coroutines-slf4j `withContext(MDCContext())`. 임의 ThreadLocal 은 `threadLocal.asContextElement(value)`. 관측 컨텍스트는 Micrometer context-propagation(Spring 문서의 `PropagationContextElement`, 사용 버전 확인). JPA 트랜잭션 안에서는 스레드를 바꾸지 않는다 — 블로킹 서비스는 suspend 로 만들지 말고 호출 측에서 한 번만 IO 로 감싼다. suspend + 트랜잭션은 리액티브 매니저(R2DBC) + `TransactionalOperator.executeAndAwait`.
- 반례: —
- 검증: 통합 테스트에서 MDC 값과 `TransactionSynchronizationManager.isActualTransactionActive()` 를 assert.
- 근거: https://kotlinlang.org/api/kotlinx.coroutines/kotlinx-coroutines-slf4j/ , https://docs.spring.io/spring-framework/reference/languages/kotlin/coroutines.html

### KT-CORO-06 · Dispatchers.Default 에서 블로킹
- 적용: CPU 작업용 디스패처에 블로킹 호출이 섞인 코드(기본 `launch`/`async` 는 Default).
- 신호: CPU 는 낮은데 지연이 크다. Default 워커(코어 수, 최소 2) 전부가 BLOCKED/WAITING.
- 메커니즘: 블로킹 몇 건으로 CPU 풀 전체가 멈춘다. 코어 수 자체가 컨테이너 설정에 좌우된다(JVM-GC-03).
- 처방: 블로킹은 IO 또는 전용 뷰로. 동기 ES/HTTP 클라이언트, `File.readText` 처럼 숨은 블로킹 API 를 확인.
- 반례: —
- 검증: 스레드 덤프, kotlinx-coroutines-debug.
- 근거: https://kotlinlang.org/api/kotlinx.coroutines/kotlinx-coroutines-core/kotlinx.coroutines/-dispatchers/-default.html

### JVM-CONC-01 · 가상 스레드 pinning — synchronized 는 JDK 24 에서 해결, 나머지는 남는다
- 적용: JDK 21~23 은 `synchronized` 블록/메서드 안 블로킹 시 캐리어가 고정된다. JDK 24+(JEP 491)는 synchronized 문제를 없앴지만 native 콜백 안 블로킹·클래스 초기화 중 블로킹은 여전히 pin. Spring Boot 3.2+ `spring.threads.virtual.enabled=true`.
- 신호: JFR `jdk.VirtualThreadPinned`(기본 임계 20ms). 처리량이 캐리어 수(= availableProcessors)에서 포화. JDK 21~23 은 `-Djdk.tracePinnedThreads=full`(JDK 24 에서 제거됨).
- 메커니즘: 캐리어는 ForkJoinPool 이고 pin 된 캐리어는 다른 가상 스레드를 돌리지 못한다. 흔한 원인: 오래된 JDBC 드라이버·풀 내부의 synchronized, `ConcurrentHashMap.computeIfAbsent` 안의 I/O, Kotlin `lazy`(기본 SYNCHRONIZED) 초기화 블록의 I/O.
- 처방: JDK 24+ 로 올리는 것이 최선. 불가하면 해당 라이브러리 버전업 또는 `ReentrantLock` 로 교체.
- 반례: CPU 바운드 작업은 가상 스레드 이득이 없다.
- 검증: JFR 이벤트 스택, 부하 테스트에서 캐리어 사용률.
- 근거: https://openjdk.org/jeps/444 , https://openjdk.org/jeps/491

### JVM-CONC-02 · 가상 스레드는 암묵적 동시성 상한을 없앤다 — 병목이 풀·하류로 이동
- 적용: 가상 스레드를 켠 Spring MVC.
- 신호: `SQLTransientConnectionException: ... Connection is not available, request timed out after 30000ms`, 하류 서비스 rate limit 초과.
- 메커니즘: 플랫폼 스레드 풀(Tomcat 200)이 하던 동시성 제한이 사라져 요청이 그대로 커넥션 풀·하류로 몰린다. ThreadLocal 에 비싼 객체를 캐싱하던 코드는 가상 스레드 수만큼 객체를 만든다.
- 처방: 의존별 `Semaphore` 로 동시성 제한(가상 스레드는 풀링하지 않는다), Hikari `connectionTimeout` 단축 + 빠른 실패, ThreadLocal 캐시 제거.
- 반례: —
- 검증: 부하 테스트에서 `hikaricp.connections.pending`, 하류 429 비율.
- 근거: https://openjdk.org/jeps/444 ("Do not pool virtual threads")

### JVM-CONC-03 · Boot 기본 `@Async` 실행기: max-size 를 올려도 스레드가 늘지 않는다
- 적용: Spring Boot 자동 구성 `ThreadPoolTaskExecutor`(가상 스레드 비활성).
- 신호: `spring.task.execution.pool.max-size` 를 올렸는데 스레드는 8개 고정, 큐와 지연만 증가.
- 메커니즘: 기본 core 8, queue-capacity 무제한. `ThreadPoolExecutor` 는 큐가 가득 찰 때만 core 를 넘어 확장하므로 max 가 영영 쓰이지 않는다. 가상 스레드를 켜면 `SimpleAsyncTaskExecutor`(가상 스레드)로 바뀌어 동시성 제한이 없어진다.
- 처방: `queue-capacity` 를 유한하게 + 거부 정책, 또는 core = max. 가상 스레드 모드에서는 simple 실행기의 concurrency limit 설정(키 이름은 사용 Boot 버전 레퍼런스 확인).
- 반례: —
- 검증: `ThreadPoolTaskExecutor` 메트릭(`executor.active`, `executor.queued`).
- 근거: https://docs.spring.io/spring-boot/reference/features/task-execution-and-scheduling.html , https://docs.oracle.com/en/java/javase/21/docs/api/java.base/java/util/concurrent/ThreadPoolExecutor.html

### JVM-CONC-04 · commonPool 에 블로킹 — `parallelStream`·executor 없는 `supplyAsync`
- 적용: `CompletableFuture.supplyAsync { }`(executor 인자 없음), `parallelStream()` 안 I/O.
- 신호: 관련 없는 기능까지 함께 느려진다. 1코어 컨테이너에서 작업마다 새 스레드 생성.
- 메커니즘: `ForkJoinPool.commonPool()` 은 JVM 전역 공유(병렬도 = 코어 수 − 1). 병렬도가 2 미만이면 `CompletableFuture` 는 작업마다 새 스레드를 만든다(javadoc).
- 처방: 전용 executor 를 항상 넘긴다. 코루틴이면 KT-CORO-01 의 뷰를 쓴다.
- 반례: 순수 CPU 분할 작업은 commonPool 이 맞다.
- 검증: 스레드 덤프의 `ForkJoinPool.commonPool-worker-*` 상태.
- 근거: https://docs.oracle.com/en/java/javase/21/docs/api/java.base/java/util/concurrent/CompletableFuture.html

### JVM-CONC-05 · 경합 카운터·false sharing
- 적용: 멀티스레드가 같이 갱신하는 카운터·통계 필드.
- 신호: 핫스팟이 `AtomicLong.incrementAndGet`, 코어를 늘려도 처리량이 정체. `perf c2c` 에서 HITM.
- 메커니즘: 같은 64바이트 캐시라인의 변수를 여러 코어가 쓰면 라인이 코어 사이를 왕복한다. AtomicLong 은 CAS 재시도까지 붙는다.
- 처방: 카운터는 `LongAdder`(내부 셀이 `@Contended` 로 패딩됨). 사용자 클래스의 `@jdk.internal.vm.annotation.Contended` 는 `-XX:-RestrictContended` 와 모듈 export 가 필요해 보통 쓰지 않는다 — 스레드별 분할 집계가 대안.
- 반례: 읽기가 잦고 쓰기가 드문 값은 `LongAdder.sum()` 비용이 더 크다.
- 검증: JMH `@Threads(N)` 비교, `perf c2c`.
- 근거: https://docs.oracle.com/en/java/javase/21/docs/api/java.base/java/util/concurrent/atomic/LongAdder.html , https://openjdk.org/jeps/142
