# JVM · Kotlin · Spring 테스트 함정

적용 전 확인: Spring Boot/Framework 버전(`build.gradle.kts`), 테스트 프레임워크(Kotest vs JUnit5), mock 라이브러리(MockK/SpringMockK vs Mockito).

### TST-JVM-01 · 테스트 클래스마다 다른 mock 빈 조합 = 컨텍스트를 매번 새로 띄운다
- 적용: Spring TestContext 를 쓰는 `@SpringBootTest`/슬라이스 테스트가 많은 스위트
- 신호: 스위트 시간이 테스트 클래스 수에 비례해 늘어남, 로그에 Spring 배너/`Started ... in` 이 반복
- 메커니즘: 컨텍스트 캐시 키에 `contextCustomizers` 가 포함되고, 여기에 `@DynamicPropertySource`, 빈 오버라이드(`@MockitoBean`, `@MockitoSpyBean`, `@TestBean`, SpringMockK `@MockkBean`)가 들어간다. 클래스마다 mock 조합이 다르면 캐시 히트가 0. 캐시는 기본 최대 32개(LRU)라 그 이상이면 축출 후 재기동까지 생긴다.
- 처방: mock 조합을 표준화한 추상 베이스 클래스/메타 애노테이션으로 모은다. 서비스 로직은 Spring 없이 단위 테스트로 내리고, Spring 테스트는 배선·매핑 검증에만 쓴다. 필요하면 `-Dspring.test.context.cache.maxSize=N`.
- 반례: 베이스 클래스에 mock 을 과하게 모으면 실제 빈을 써야 할 테스트까지 mock 이 된다 — 공유 대상은 "외부 경계" mock 만.
- 검증: `logging.level.org.springframework.test.context.cache=DEBUG` 로 캐시 hit/miss 통계 확인.
- 근거: https://docs.spring.io/spring-framework/reference/testing/testcontext-framework/ctx-management/caching.html

### TST-JVM-02 · `@DirtiesContext` 는 캐시를 버리는 망치다
- 적용: 테스트 간 상태 누수를 `@DirtiesContext` 로 막고 있는 스위트
- 신호: 클래스/메서드 레벨 `@DirtiesContext` 다수, CI 시간 증가
- 메커니즘: 표시된 컨텍스트를 닫고 캐시에서 제거 → 다음 테스트가 전체 재기동.
- 처방: 누수의 실제 원천(싱글턴 빈의 가변 상태, 캐시, 인메모리 큐, static)을 테스트 후 리셋하는 빈/훅으로 정리.
- 반례: 컨텍스트 자체를 바꾸는 테스트(빈 정의 변경 등)는 정당한 사용.
- 검증: 제거 전후 `./gradlew test --rerun` 시간 비교.
- 근거: https://docs.spring.io/spring-framework/reference/testing/annotations/integration-spring/annotation-dirtiescontext.html

### TST-JVM-03 · `RANDOM_PORT` + `@Transactional` 테스트는 롤백되지 않는다
- 적용: `@SpringBootTest(webEnvironment = RANDOM_PORT | DEFINED_PORT)` + 테스트 메서드/클래스 `@Transactional`
- 신호: 테스트 순서에 따라 결과가 달라짐, 테스트 후 DB 에 행이 남음
- 메커니즘: 실제 서블릿 환경에서는 HTTP 클라이언트와 서버가 다른 스레드 → 다른 트랜잭션. 서버 쪽에서 커밋된 쓰기는 테스트 트랜잭션 롤백 대상이 아니다.
- 처방: 테스트별 데이터 정리(테이블 truncate, 고유 키 네임스페이스) 또는 MockMvc(`MOCK` 환경, 같은 스레드)로 전환.
- 반례: 실제 네트워크 스택·필터 체인을 검증해야 하는 테스트는 RANDOM_PORT 가 맞다 — 정리 전략을 같이 둔다.
- 검증: 테스트 직후 대상 테이블 count assert.
- 근거: https://docs.spring.io/spring-boot/reference/testing/spring-boot-applications.html

### TST-JVM-04 · 트랜잭션 롤백 JPA 테스트는 flush 를 안 해서 "그린"이다
- 적용: `@DataJpaTest`(기본 `@Transactional`) 또는 `@Transactional` 테스트에서 저장 후 조회
- 신호: 테스트는 그린, 운영에서 unique/FK 제약 위반, `LazyInitializationException`, 잘못된 컬럼 매핑
- 메커니즘: 저장한 엔티티가 1차 캐시에 남아 같은 인스턴스가 반환되고 SQL 이 나가지 않는다. 롤백으로 끝나므로 커밋 시점 flush 도 없다. 지연 로딩도 같은 세션 안이라 예외가 안 난다.
- 처방: 저장 후 `entityManager.flush(); entityManager.clear()`(또는 `TestEntityManager.flush()/clear()`) 하고 다시 조회해 assert. 제약 위반 테스트는 `saveAndFlush`.
- 반례: 순수 도메인 로직 검증에는 불필요.
- 검증: `spring.jpa.show-sql`/p6spy 로 INSERT·SELECT 가 실제 나가는지 확인.
- 근거: https://docs.spring.io/spring-boot/reference/testing/spring-boot-applications.html (Data JPA tests 절)

### TST-JVM-05 · Kotest `beforeEach` 는 leaf 에만 — Given/When 본문이 먼저 실행된다
- 적용: Kotest BehaviorSpec/DescribeSpec 등 중첩 스타일
- 신호: Given 블록에서 건 `every {}` stub 이 Then 에서 사라짐, 또는 When 본문에서 계산한 값이 이전 상태 기준
- 메커니즘: `beforeEach` 는 `TestType.Test`(leaf)에만, `beforeContainer` 는 컨테이너에만, `beforeAny`(=`beforeTest`)는 둘 다 실행된다. 컨테이너 본문(Given/When)의 코드는 그 아래 leaf 의 `beforeEach` 보다 **먼저** 실행된다. `beforeEach { clearAllMocks() }` + Given 에서 stub 하는 흔한 패턴은 stub 을 Then 직전에 지운다(When 본문에서 이미 호출했다면 우연히 통과).
- 처방: stub 과 호출을 같은 leaf 안에 두거나, 정리는 `afterTest`/`beforeContainer` 로 의도에 맞게 선택. 의미가 모호하면 FunSpec/StringSpec 처럼 평평한 스타일.
- 반례: 플랫 스타일에서는 `beforeEach` 가 직관대로 동작한다.
- 검증: 훅 안에 `println(testCase.name)` 으로 실행 순서 출력.
- 근거: https://kotest.io/docs/framework/lifecycle-hooks.html

### TST-JVM-06 · Kotest 기본 격리는 SingleInstance — 스펙 레벨 `val` 은 모든 테스트가 공유
- 적용: Kotest 스펙 생성자 블록에 `val repo = mockk<...>()`, 가변 리스트 등을 선언
- 신호: `verify(exactly = 1)` 이 단독 실행은 통과·전체 실행은 실패, 테스트 순서 의존
- 메커니즘: 기본 `IsolationMode.SingleInstance` 는 스펙 인스턴스 1개로 모든 테스트를 실행 → mock 의 호출 기록·stub 이 누적.
- 처방: leaf 마다 새로 만들거나, 공유한다면 `afterTest { clearMocks(repo) }`. 스펙 단위로 격리가 필요하면 `isolationMode` 설정(프로젝트의 Kotest 버전 문서에서 지원 모드 확인).
- 반례: 비싼 리소스(컨테이너, 컨텍스트)는 공유가 맞다 — 가변 상태만 분리.
- 검증: 해당 테스트만 단독 실행 vs 스펙 전체 실행 결과 비교.
- 근거: https://kotest.io/docs/framework/isolation-mode.html

### TST-JVM-07 · `mockkObject`/`mockkStatic` 은 JVM 전역 — `clearAllMocks` 로는 원복되지 않는다
- 적용: MockK 로 object/top-level 함수/static/생성자 mock
- 신호: 해당 테스트 이후 실행되는 무관한 테스트가 mock 된 값을 받음
- 메커니즘: object·static mock 은 클래스 바이트코드를 계측해 프로세스 전역에 적용된다. `clearAllMocks` 는 stub·기록만 지우고 계측은 남긴다. 원복은 `unmockkObject`/`unmockkStatic`/`unmockkAll`.
- 처방: `afterTest { unmockkAll() }` 또는 범위 함수 `mockkObject(X) { ... }`. 더 나은 해법은 시간·ID 생성 같은 전역 호출을 생성자 주입(`Clock`, `IdGenerator`)으로 바꾸는 것.
- 반례: 없음 — 전역 mock 은 정리가 필수.
- 검증: 테스트 순서 랜덤화(JUnit `MethodOrderer.Random`, Kotest `specExecutionOrder`)로 재현.
- 근거: https://mockk.io/#object-mocks

### TST-JVM-08 · `runTest` 의 가상 시간은 주입되지 않은 디스패처에선 무력하다
- 적용: kotlinx-coroutines-test `runTest`
- 신호: `delay` 가 실제로 기다려 테스트가 느림, 기본 타임아웃(현재 문서 기준 60초) 초과
- 메커니즘: delay 스킵은 `TestCoroutineScheduler` 를 쓰는 디스패처에서만 일어난다. 코드 안의 `withContext(Dispatchers.IO/Default)` 는 실제 시간으로 흐른다.
- 처방: 디스패처를 생성자 주입하고 테스트에서 `StandardTestDispatcher(testScheduler)` 를 넘긴다. 시간 진행은 `advanceTimeBy`/`advanceUntilIdle`. `Dispatchers.Main` 을 쓰면 `Dispatchers.setMain`.
- 반례: 실제 블로킹 I/O 를 검증하는 통합 테스트는 가상 시간 대상이 아니다.
- 검증: `currentTime` 출력, 테스트 wall time 측정.
- 근거: https://kotlinlang.org/api/kotlinx.coroutines/kotlinx-coroutines-test/kotlinx.coroutines.test/run-test.html

### TST-JVM-09 · Gradle 은 입력이 안 바뀌면 테스트를 실행하지 않는다
- 적용: Gradle 빌드, 특히 환경변수·외부 리소스·테스트 리소스 밖 파일에 의존하는 테스트
- 신호: `> Task :test UP-TO-DATE`/`FROM-CACHE` 인데 "통과"로 보고, 수정이 반영 안 된 것처럼 보임
- 메커니즘: test 태스크는 입력(클래스패스·설정)이 같으면 up-to-date/빌드 캐시로 스킵된다. 테스트가 읽는 환경변수나 외부 파일은 선언하지 않으면 입력이 아니다.
- 처방: 강제 재실행은 `./gradlew test --rerun`(Gradle 7.6+ 내장 옵션) 또는 `cleanTest test`. 의존하는 환경 값은 `inputs.property(...)` 로 선언.
- 반례: CI 에서 매번 `--rerun` 을 쓰면 빌드 캐시 이득을 버린다 — 로컬 RED 확인용.
- 검증: 태스크 출력의 `UP-TO-DATE`/`FROM-CACHE` 표기 확인.
- 근거: https://docs.gradle.org/current/userguide/command_line_interface.html#sec:builtin_task_options

### TST-JVM-10 · JDK 를 올리면 JaCoCo·Mockito/MockK 에이전트가 먼저 깨진다
- 적용: JDK 업그레이드(예: 17→21+), Mockito 5(기본 inline mock maker)·MockK(ByteBuddy)
- 신호: JaCoCo `Unsupported class file major version`, JDK 21+ 에서 "A Java agent has been loaded dynamically" 경고
- 메커니즘: JaCoCo 는 지원하는 클래스 파일 버전이 정해져 있다(0.8.11 이 Java 21 공식 지원). JDK 21 의 JEP 451 은 런타임 동적 에이전트 로딩에 경고를 내며, 향후 기본 차단을 예고한다 — mock 라이브러리의 self-attach 가 해당된다.
- 처방: `jacoco { toolVersion = "<JDK 지원 버전>" }` 를 명시. Mockito 는 공식 문서대로 테스트 JVM 에 `-javaagent` 로 등록, 또는 임시로 `-XX:+EnableDynamicAgentLoading`.
- 반례: 경고만 있고 동작은 하므로 급하면 후순위 — 다만 JDK 업그레이드 계획에 포함.
- 검증: `./gradlew test` 출력의 경고 문구, JaCoCo 리포트 생성 여부.
- 근거: https://openjdk.org/jeps/451 · https://www.jacoco.org/jacoco/trunk/doc/changes.html · https://javadoc.io/doc/org.mockito/mockito-core/latest/org/mockito/Mockito.html#0.3

### TST-JVM-11 · "Kotlin final 클래스는 Mockito 로 mock 불가"는 낡은 상식이다
- 적용: Mockito 5+ (inline mock maker 기본), Spring Framework 6.2+/Boot 3.4+
- 신호: Mockito 를 쓰는 기존 코드베이스에 MockK 를 이중 도입하려는 제안, `@MockBean` deprecation 경고
- 메커니즘: Mockito 5 는 inline mock maker 가 기본이라 final 클래스 mock 이 된다. 남는 Kotlin 문제는 `any()` 가 `null` 을 반환해 non-null 파라미터에서 NPE 가 나는 것(mockito-kotlin 이 해결). Spring Boot 3.4 에서 `@MockBean` 은 deprecated, Framework 의 `@MockitoBean` 이 대체.
- 처방: 프로젝트가 이미 쓰는 mock 라이브러리를 유지(혼용 금지). Mockito 면 mockito-kotlin + `@MockitoBean`, MockK 면 SpringMockK `@MockkBean`.
- 반례: 코루틴·확장함수·object mock 이 많으면 MockK 가 더 자연스럽다 — 신규 프로젝트 선택 기준.
- 검증: 빌드 파일의 mockito-core 버전, deprecation 경고.
- 근거: https://github.com/mockito/mockito/releases/tag/v5.0.0 · https://docs.spring.io/spring-framework/reference/testing/annotations/integration-spring/annotation-mockitobean.html
