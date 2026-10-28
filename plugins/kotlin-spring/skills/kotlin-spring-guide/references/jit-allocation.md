# JIT·할당·예외 비용 (JVM-JIT, KT-LOG)

> 이 파일의 항목은 **핫 경로에서 측정으로 확인된 뒤에만** 적용한다. 측정 없는 미시 최적화는 가독성만 해친다.
> 측정 도구: JMH(`-prof gc`), async-profiler, JFR — `observability.md` 참조.

### JVM-JIT-01 · 이스케이프 분석은 인라인이 전제다 — "할당 안 될 것"이 깨지는 조건
- 적용: C2 로 컴파일된 핫 메서드.
- 신호: 핫 경로의 작은 임시 객체(`Pair`, 작은 data class, iterator, 캡처 람다, 박싱)가 할당 프로파일 상위.
- 메커니즘: scalar replacement 는 객체가 탈출하지 않고 생성자·사용 메서드가 모두 인라인될 때만 일어난다. 인라인 한계: 핫 메서드 `FreqInlineSize`=325 바이트코드, 그 외 `MaxInlineSize`=35, 깊이 `MaxInlineLevel`=15(JDK 14+), 이미 컴파일된 피호출자는 네이티브 코드 크기 `InlineSmallCode`(플랫폼별 기본값) 초과 시 인라인 안 됨. 메가모픽 호출, 큰 메서드, 분기 합류 지점에서 서로 다른 할당이 만나는 경우에 실패한다.
- 처방: 핫 루프 메서드를 작게 유지, 분기 양쪽에서 만든 객체를 한 변수로 합류시키지 않기(JDK 21 이하 기준 — 이후 C2 는 `ReduceAllocationMerges` 로 일부 합류를 스칼라 치환하고 기본값이 릴리스마다 다르니 적용 전 `-prof gc` 로 확인), 핫 경로에서 `Pair`/`Triple` 반환 대신 원시 값 두 개를 다른 방식으로 전달.
- 반례: 핫이 아닌 경로.
- 검증: JMH `-prof gc` 의 `gc.alloc.rate.norm`, `-XX:+UnlockDiagnosticVMOptions -XX:+PrintInlining`, JITWatch.
- 근거: https://wiki.openjdk.org/display/HotSpot/EscapeAnalysis , https://bugs.openjdk.org/browse/JDK-8234863

### JVM-JIT-02 · 메가모픽 콜사이트 — 수신 타입이 고르게 3개 이상이면 인라인을 포기한다
- 적용: 인터페이스·람다를 받는 공용 함수가 핫 루프에서 여러 구현으로 호출될 때.
- 신호: async-profiler 에 `itable stub`/`vtable stub`. 공용 매퍼·전략 인터페이스, Kotlin non-inline 고차 함수, Sequence 연산자의 `invoke`.
- 메커니즘: C2 는 프로파일된 수신 타입이 1개(monomorphic)·2개(bimorphic)면 타입 가드와 함께 인라인한다. 3개 이상이어도 한 타입이 `TypeProfileMajorReceiverPercent`(기본 90%) 이상이면 그 타입만 가드 뒤에 인라인하고, 분포가 고를 때만 가상 호출로 남긴다 → 인라인이 막히면 이스케이프 분석·상수 전파도 연쇄로 막힌다.
- 처방: Kotlin `inline` 고차 함수로 호출 지점별로 특수화, 핫 경로는 `sealed` + `when` 으로 단형화.
- 반례: 한 타입이 지배적인 메가모픽 사이트는 재작성할 필요가 없다 — `PrintInlining` 출력부터 확인. `inline` 남용은 코드 크기를 늘려 상위 메서드가 인라인 한계를 넘게 만든다.
- 검증: `-XX:+PrintInlining` 출력, JMH 비교.
- 근거: https://shipilev.net/blog/2015/black-magic-method-dispatch/ , https://shipilev.net/jvm/anatomy-quarks/16-megamorphic-virtual-calls/ , https://github.com/openjdk/jdk/blob/master/src/hotspot/share/opto/c2_globals.hpp

### JVM-JIT-03 · 정규식 재컴파일 — Java `split`/`replaceAll` 와 Kotlin `Regex(...)`
- 적용: 요청·레코드마다 문자열을 나누거나 치환하는 코드.
- 신호: 프로파일 상위 `Pattern.compile`. 루프 안 `Regex("\\s+")`, `"...".toRegex()`, Java 스타일 `split("\\s+")`, `replaceAll`, `matches`.
- 메커니즘: Java `String.split` 은 메타문자가 아닌 1글자(또는 역슬래시 + 비영숫자 2글자)만 fast path 이고 나머지는 매번 `Pattern.compile`. `replaceAll`/`replaceFirst`/`matches` 도 매번 컴파일. Kotlin `Regex(...)` 생성도 매번 컴파일. 반대로 Kotlin `String.split(String)` 은 정규식이 아니라 **리터럴 구분자**다 — `"a.b".split(".")` 는 Kotlin 에서 `[a, b]`, Java 에서는 빈 배열.
- 처방: `private val WHITESPACE = Regex("\\s+")` 를 companion/top-level 로 끌어올린다. 리터럴 분할·치환은 Kotlin `split(String)`·`replace(String, String)`.
- 반례: —
- 검증: JFR CPU/할당 상위의 `java.util.regex` 클래스.
- 근거: https://docs.oracle.com/en/java/javase/21/docs/api/java.base/java/lang/String.html#split(java.lang.String,int) , https://kotlinlang.org/api/core/kotlin-stdlib/kotlin.text/split.html

### JVM-JIT-04 · 예외 생성 비용은 스택 워크다 — 제어 흐름용 예외
- 적용: 정상 흐름에서 자주 던지는 예외(캐시 미스, 파싱 시도 실패, "없음" 예외).
- 신호: 프로파일 상위 `Throwable.fillInStackTrace`, `StackTraceElement`.
- 메커니즘: 비용 대부분은 생성 시 스택 캡처이고 깊이에 비례한다(Spring 프록시·필터 체인으로 100 프레임 이상 흔함). throw/catch 자체는 인라인되면 싸다.
- 처방: 기대된 실패는 예외 대신 nullable·sealed 결과로 표현. 꼭 예외여야 하는 고빈도 비즈니스 예외는 서브클래스에서 protected 4-인자 생성자를 호출 — `class NotFoundFast(msg: String) : RuntimeException(msg, null, false, false)`(writableStackTrace=false), 또는 `fillInStackTrace()` 오버라이드 — 진단성 손실을 감수할 지점에만.
- 반례: 버그를 알리는 예외에는 스택이 필수.
- 검증: JMH, async-profiler CPU.
- 근거: https://docs.oracle.com/en/java/javase/21/docs/api/java.base/java/lang/Throwable.html , https://shipilev.net/blog/2014/exceptional-performance/

### JVM-JIT-05 · 운영 로그의 스택 없는 NPE — OmitStackTraceInFastThrow
- 적용: HotSpot C2(기본 on).
- 신호: 로그에 `java.lang.NullPointerException` 한 줄(스택·메시지 없음). 재시작 직후엔 스택이 있다가 반복되면 사라진다. ArithmeticException, ArrayIndexOutOfBounds, ClassCastException, ArrayStoreException 도 동일.
- 메커니즘: 자주 발생하는 암시적 예외를 C2 가 미리 할당된 스택 없는 예외로 대체한다. Helpful NPE 메시지(JDK 14+)도 붙지 않는다.
- 처방: 진단 기간에 `-XX:-OmitStackTraceInFastThrow`, 또는 재시작 직후 첫 발생 로그를 찾는다. 근본적으로는 빈발 예외 자체를 고친다.
- 반례: 상시 off 는 빈발 예외 경로를 느리게 한다.
- 검증: 로그 검색으로 같은 위치의 첫 발생 스택 확보.
- 근거: https://github.com/openjdk/jdk/blob/master/src/hotspot/share/runtime/globals.hpp (OmitStackTraceInFastThrow), https://openjdk.org/jeps/358

### JVM-JIT-06 · 코드 캐시 고갈 — JIT 가 멈추고 서서히 느려진다
- 적용: 클래스·프록시가 많은 대형 Spring 앱, 장기 실행 프로세스.
- 신호: 로그 `CodeCache is full. Compiler has been disabled.`, 며칠에 걸친 점진적 성능 저하, JFR `jdk.CodeCacheFull`.
- 메커니즘: 티어드 컴파일 시 `ReservedCodeCacheSize` 기본 240MB. 가득 차면 새 컴파일이 멈춰 인터프리터·C1 코드로 돈다.
- 처방: `jcmd <pid> Compiler.codecache` 로 사용량을 보고 `-XX:ReservedCodeCacheSize` 상향(그만큼 RSS 예산에 반영).
- 반례: —
- 검증: `jcmd Compiler.codecache` 추이, JFR `jdk.CodeCacheStatistics`.
- 근거: https://docs.oracle.com/en/java/javase/21/docs/specs/man/java.html

### JVM-JIT-07 · 배포 직후 p99 급등 — 클래스 로딩·워밍업과 CDS/AOT 캐시
- 적용: Spring Boot 3.3+ CDS 지원, JDK 24 AOT 클래스 로딩·링킹(JEP 483), JDK 25 AOT 명령 간소화·메서드 프로파일(JEP 514/515).
- 신호: 롤링 배포 후 새 파드의 첫 수 분간 p99 급등, HPA 스케일아웃 효과가 늦다. 1 vCPU 파드에서 JIT 컴파일러 스레드가 요청과 CPU 경쟁.
- 메커니즘: 기동 시 클래스 로딩·링킹 + 인터프리터/C1 단계를 거쳐야 C2 코드가 된다.
- 처방: 이미지 빌드에 CDS/AOT 캐시 생성(training run) 단계 추가, readiness 전에 워밍업 트래픽, 기동 구간 CPU 여유.
- 반례: AOT/CDS 캐시는 같은 JDK·같은 클래스패스여야 유효 — 불일치 시 경고 후 무시된다.
- 검증: 기동 시간, 배포 직후 N분 p99 비교.
- 근거: https://docs.spring.io/spring-boot/reference/packaging/class-data-sharing.html , https://openjdk.org/jeps/483 , https://openjdk.org/jeps/515

### KT-LOG-01 · Kotlin 문자열 템플릿 로그는 레벨과 무관하게 평가된다
- 적용: 핫 경로의 debug/trace 로그.
- 신호: `log.debug("result=$result")`, `log.debug("payload=${mapper.writeValueAsString(x)}")`.
- 메커니즘: 인자는 호출 전에 평가된다 — 비활성 레벨이어도 `toString`·직렬화 비용과 할당이 발생한다. SLF4J `{}` 는 메시지 조립과 `toString` 만 미룰 뿐 **인자 식은 여전히 평가**한다 — `log.debug("payload={}", mapper.writeValueAsString(x))` 는 매번 직렬화한다.
- 처방: 값 자체가 싼 경우만 `{}`. 비싼 인자(직렬화 등)는 지연 평가 람다 — kotlin-logging `logger.debug { "payload=${mapper.writeValueAsString(x)}" }`(inline 아님: 비캡처 람다는 싱글턴, 캡처 람다는 호출마다 할당되지만 비활성이면 본문 평가 안 함), SLF4J 2 fluent `atDebug().addArgument { ... }`(Supplier), 또는 `if (log.isDebugEnabled)` 가드.
- 반례: 항상 출력되는 info 이상 로그는 차이가 없다.
- 검증: 할당 프로파일에서 `StringBuilder`/`toString` 출처.
- 근거: https://www.slf4j.org/faq.html#logging_performance , https://github.com/oshai/kotlin-logging
