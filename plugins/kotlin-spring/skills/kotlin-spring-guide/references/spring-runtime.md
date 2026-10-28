# Spring 런타임 — JSON·종료·메트릭·검증 (SPR-JSON, SPR-OPS, KT-VAL)

> 먼저 확인: Spring Boot 메이저 버전(3.x = Jackson 2, 4.x = Jackson 3 기본), `jackson-module-kotlin` 의존성,
> 배포 환경(k8s 여부·terminationGracePeriodSeconds), Actuator/Micrometer 사용 여부.

### SPR-JSON-01 · ObjectMapper 를 매번 만들거나 Boot 것과 따로 만든다
- 적용: Jackson 을 직접 쓰는 코드(Kafka·ES·Redis 직렬화, 로깅, 테스트 유틸).
- 신호: 메서드 안의 `jacksonObjectMapper()`/`ObjectMapper()`. HTTP 응답과 Kafka/ES 문서의 날짜 형식·null 처리가 서로 다름.
- 메커니즘: ObjectMapper 는 설정 후 스레드 안전하고 생성 비용이 크다 — 타입별 (역)직렬화기 캐시를 인스턴스에 보관하므로 매번 만들면 리플렉션·Kotlin 메타데이터 분석을 반복한다. Boot 가 구성한 매퍼(Kotlin 모듈, java.time 모듈, `spring.jackson.*`)와 별개 인스턴스는 설정이 다르다.
- 처방: Boot 매퍼를 주입해 재사용(Boot 4/Jackson 3 는 `JsonMapper`). 호출별로 다른 설정은 `readerFor(...)`/`writerWithView(...)` 같은 불변 `ObjectReader`/`ObjectWriter` 로. 전역 커스터마이즈는 Boot 3 `Jackson2ObjectMapperBuilderCustomizer`, Boot 4 는 레퍼런스의 JsonMapper 커스터마이즈 how-to 를 따른다.
- 반례: 의도적으로 다른 포맷이 필요한 외부 계약(레거시 시스템)은 별도 매퍼를 빈으로 명시해 공유한다.
- 검증: 프로파일 상위의 `BeanSerializerFactory`/`KotlinNamesAnnotationIntrospector`, JMH.
- 근거: https://docs.spring.io/spring-boot/reference/features/json.html , https://github.com/FasterXML/jackson-databind#1-minute-tutorial-pojos-to-json-and-back

### SPR-JSON-02 · Jackson 2 와 3 — Boot 4 에서 패키지가 바뀐다
- 적용: Spring Boot 4.x(Jackson 3 기본, 패키지 `tools.jackson.*`. `jackson-annotations` 는 `com.fasterxml.jackson.annotation` 유지). Boot 3.x 는 Jackson 2.
- 신호: 커스텀 Serializer/Module 이 `com.fasterxml.jackson.databind` 를 import 하는데 Boot 4 업그레이드 후 적용되지 않음(두 버전이 공존하면 조용히 무시).
- 메커니즘: Boot 4 의 자동 구성 매퍼는 Jackson 3 이라 Jackson 2 타입으로 만든 모듈·커스터마이저를 보지 않는다. Jackson 2 지원은 deprecated.
- 처방: 빌드 파일에서 Boot 버전을 먼저 확인하고 import 경로를 결정. 업그레이드 시 Spring 의 Jackson 3 마이그레이션 안내를 따른다.
- 반례: —
- 검증: 직렬화 결과 스냅샷 테스트.
- 근거: https://docs.spring.io/spring-boot/reference/features/json.html , https://spring.io/blog/2025/10/07/introducing-jackson-3-support-in-spring/

### SPR-JSON-03 · Kotlin 모듈의 기본값·nullability 시맨틱
- 적용: Kotlin data class 로 받는 요청 DTO·메시지.
- 신호: 필드 누락과 명시적 `null` 이 다르게 동작해 400 이 나거나, 컬렉션에 `null` 원소가 들어와 나중에 NPE.
- 메커니즘: Kotlin 모듈은 누락 필드에 생성자 기본값을 쓰고, non-null 파라미터에 명시적 `null` 이 오면 기본적으로 실패한다(`NullIsSameAsDefault` 기능을 켜면 기본값으로 대체). 컬렉션·맵 **원소**의 nullability 는 기본적으로 검사하지 않는다(엄격 null 검사 기능을 켜야 한다 — 기능 이름은 모듈 버전 README 확인).
- 처방: API 계약에 맞게 기능을 명시적으로 켜고, 입력 DTO 정책(nullable + Bean Validation vs non-null + 기본값)을 하나로 정한다.
- 반례: —
- 검증: 누락/`null`/`null` 원소 3종 입력 계약 테스트.
- 근거: https://github.com/FasterXML/jackson-module-kotlin

### SPR-OPS-01 · Graceful shutdown 과 k8s 종료 순서
- 적용: Spring Boot 3.4+ 는 기본 graceful(이전은 `server.shutdown=graceful` 필요), `spring.lifecycle.timeout-per-shutdown-phase` 기본 30s, k8s `terminationGracePeriodSeconds` 기본 30s.
- 신호: 롤링 배포 때마다 502/connection reset 소량 발생.
- 메커니즘: SIGTERM 수신과 엔드포인트 제거(kube-proxy·Ingress 반영)가 비동기라 앱이 새 요청을 거부하기 시작한 뒤에도 트래픽이 들어온다. grace period 를 넘기면 SIGKILL.
- 처방: `preStop` 에서 5~10s 기다려 엔드포인트 제거를 기다린다 — k8s 1.30+(sleep 액션 beta 기본 on, 1.34 GA)는 바이너리 없이 `lifecycle.preStop.sleep.seconds: 10`. 그 미만에서 exec `sleep` 은 이미지에 sleep 바이너리가 있는지 확인한 뒤에만. `terminationGracePeriodSeconds` > preStop + timeout-per-shutdown-phase.
- 반례: distroless·Jib 이미지는 셸·sleep 이 없어 exec preStop 이 실패한다(이벤트 `FailedPreStopHook`) — 대기 효과가 사라진 채 바로 종료된다.
- 검증: 배포 중 부하 테스트에서 오류 0 확인.
- 근거: https://docs.spring.io/spring-boot/reference/web/graceful-shutdown.html , https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/#pod-termination , https://www.kubernetes.dev/resources/keps/3960/

### SPR-OPS-02 · Micrometer 태그 카디널리티 폭발
- 적용: Actuator + Micrometer(Prometheus 등).
- 신호: `/actuator/prometheus` 응답이 수십 MB, 힙의 Meter 객체 증가. `http.client.requests` 의 `uri` 태그에 실제 ID 가 들어간 값. 로그 `Reached the maximum number of URI tags for '...'` — 상한에 걸려 이후 메트릭이 조용히 버려지고 있다는 뜻.
- 메커니즘: 태그 값 조합마다 Meter 가 생긴다. RestClient/WebClient 에 URI 템플릿 없이 완성 문자열을 넘기면 `uri` 태그가 원문 경로가 된다. 사용자 ID·검색어를 태그로 넣는 것도 같다. Boot 는 `http.server/client.requests` 의 `uri` 태그에 기본 상한(`management.metrics.web.server.max-uri-tags`/`client.max-uri-tags`, 기본 100)을 걸어 초과분 Meter 를 거부(deny)하므로, uri 쪽 증상은 "폭발"보다 "상한 이후 메트릭 누락"으로 나타나고, 실제 폭발은 대개 커스텀 태그다.
- 처방: `.uri("/users/{id}", id)` 처럼 템플릿 사용. `MeterFilter.maximumAllowableTags(...)` 로 상한. 무한 값은 태그가 아니라 로그·트레이스로.
- 반례: —
- 검증: 메트릭 이름별 시계열 수(Prometheus `count by (__name__)`).
- 근거: https://docs.micrometer.io/micrometer/reference/concepts/meter-filters.html , https://docs.spring.io/spring-boot/appendix/application-properties/index.html

### KT-VAL-01 · 생성자 프로퍼티의 Bean Validation 애노테이션이 필드에 붙지 않는다
- 적용: Kotlin < 2.2, 또는 2.2+ 에서 `-Xannotation-default-target=param-property` 를 켜지 않은 빌드(2.2 는 preview 옵트인 — 기본화 여부는 사용 Kotlin 버전 문서 확인). Spring MVC/WebFlux `@Valid`, Hibernate Validator.
- 신호: `data class CreateReq(@NotBlank val name: String)` 처럼 use-site target(`@field:`/`@get:`) 없는 제약 애노테이션. 빈 값이 400 없이 서비스까지 들어온다. IDE 인스펙션 "AddExplicitTargetToParameterAnnotation".
- 메커니즘: 구 규칙은 적용 가능한 대상 중 **첫 번째 하나**(param → property → field)에만 붙인다. Bean Validation 애노테이션은 PARAMETER 를 허용하므로 생성자 파라미터에만 붙고, 필드·게터를 검사하는 Hibernate Validator 는 이를 보지 않는다. Kotlin 2.2 의 새 규칙(param + property, property 불가 시 field)은 param 과 field 양쪽에 붙인다.
- 처방: `@field:NotBlank` 로 명시하거나(버전 무관), Kotlin 2.2+ 에서 `freeCompilerArgs.add("-Xannotation-default-target=param-property")`. 플래그를 켜면 다른 애노테이션(Jackson·JPA 등)의 적용 대상도 바뀌니 함께 검증한다(구 동작 유지는 `-Xannotation-default-target=first-only`).
- 반례: 프로젝트가 이미 `@field:` 를 일관되게 쓰면 해당 없음.
- 검증: 잘못된 입력으로 요청해 400 이 나는지 `@WebMvcTest` 로 assert.
- 근거: https://kotlinlang.org/docs/whatsnew22.html#new-defaulting-rules-for-use-site-annotation-targets , https://kotlinlang.org/docs/annotations.html#annotation-use-site-targets , https://blog.jetbrains.com/idea/2025/09/improved-annotation-handling-in-kotlin-2-2-less-boilerplate-fewer-surprises/

