# 직렬화 스페셜리스트 항목 (DTO-S)

언어·라이브러리 메이저 버전이 기본값을 바꾼다 — 먼저 빌드 파일에서 Jackson(2 `com.fasterxml` / 3 `tools.jackson`)·Spring Boot·Go·Pydantic 버전을 확인한다.

---

### DTO-S-01 · Kotlin + Jackson: non-null 파라미터에 JSON 이 명시적 `null` 을 보내면 기본값이 아니라 예외
- 적용: jackson-module-kotlin, 기본값 있는 non-null 생성자 파라미터 (Jackson 2 `com.fasterxml.jackson.module.kotlin` / Jackson 3·Spring Boot 4 `tools.jackson.module.kotlin` — 빌드 파일에서 메이저 확인. Jackson 3 에서의 동작은 아래 `검증` 3종 테스트로 해당 버전에서 직접 확인)
- 신호: 클라이언트가 `"paging": null` 을 보냈을 때 400(`MissingKotlinParameterException`/`MismatchedInputException`), 필드 누락은 정상
- 메커니즘: 필드 **누락**이면 Kotlin 기본값이 쓰이지만 명시적 `null` 은 non-null 타입에 대입할 수 없어 실패한다.
- 처방: 계약상 null 을 허용할지 결정. 허용하면 `KotlinModule.Builder().enable(KotlinFeature.NullIsSameAsDefault)` (전역 영향 주의) 또는 해당 필드를 nullable + 서비스 진입에서 기본값.
- 반례: null 을 거부하는 것이 의도된 계약이면 그대로 두고 오류 메시지만 명확히.
- 검증: `null`/누락/값 3가지 JSON 으로 역직렬화 테스트.
- 근거: https://github.com/FasterXML/jackson-module-kotlin#configuration

### DTO-S-02 · Spring Boot 의 JSON 매퍼는 알 수 없는 필드를 조용히 무시한다 — Jackson 3 부터는 순수 매퍼도 무시한다
- 적용: Spring Boot 3.x 자동 구성 `ObjectMapper`(Jackson 2, `Jackson2ObjectMapperBuilder`), Spring Boot 4 자동 구성 `JsonMapper`(Jackson 3), 직접 생성한 `JsonMapper`/`ObjectMapper`
- 신호: 클라이언트 오타 필드(`chanel`)가 무시되고 기본값/검증 오류로만 드러남, Kafka 페이로드 스키마 변경이 조용히 유실
- 메커니즘: Jackson 2 는 `FAIL_ON_UNKNOWN_PROPERTIES` 기본 **활성**이지만 Spring 의 `Jackson2ObjectMapperBuilder`(Boot 3.x 자동 구성)가 비활성화한다. **Jackson 3.0 은 이 기능의 기본값 자체를 비활성으로 바꿨다**(databind `DeserializationFeature` 주석: "disabled by default as of Jackson 3.0"). 그래서 Boot 4 의 자동 구성 `JsonMapper` 와 `JsonMapper.builder().build()` 모두 무시가 기본이다 — Jackson 2 시절 "테스트에선 순수 ObjectMapper 라 strict" 라는 가정이 깨진다. (Boot 4 의 `spring.jackson.use-jackson2-defaults=true` 는 Boot 3 시절 기본값 묶음을 재현하는 이행용 스위치.) 하위 호환에는 유리하지만 계약 오류를 숨긴다.
- 처방: 외부 공개 API 는 관대하게 두되 필수 필드 검증(DTO-T-01)으로 오타를 잡는다. 내부 이벤트 계약 테스트에서는 `FAIL_ON_UNKNOWN_PROPERTIES` 를 **명시적으로 enable** 한 매퍼로 역직렬화해 스키마 드리프트를 감지(Jackson 3 에서는 기본값에 기대면 strict 가 아니다).
- 반례: 롤링 배포 중 신규 필드를 구버전 소비자가 받는 경우 무시가 필요하다 — 운영 매퍼를 strict 로 바꾸지 말 것.
- 검증: 계약 테스트에 unknown 필드 케이스 추가.
- 근거: https://docs.spring.io/spring-framework/docs/current/javadoc-api/org/springframework/http/converter/json/Jackson2ObjectMapperBuilder.html , https://github.com/FasterXML/jackson-databind/blob/3.x/src/main/java/tools/jackson/databind/DeserializationFeature.java (FAIL_ON_UNKNOWN_PROPERTIES) , https://github.com/spring-projects/spring-boot/blob/main/module/spring-boot-jackson/src/main/java/org/springframework/boot/jackson/autoconfigure/JacksonProperties.java (useJackson2Defaults)

### DTO-S-03 · Go `encoding/json`: nil slice 는 `null`, 값 타입은 누락과 0 을 구분 못 하고, `omitempty` 는 구조체 0값을 생략하지 않는다
- 적용: Go HTTP 핸들러/이벤트 DTO
- 신호: 빈 결과가 `"items": null` 로 응답, PATCH 에서 `0`/`false` 로 갱신 불가, `time.Time` 에 `omitempty`
- 메커니즘: `var s []T` 는 `null` 로, `[]T{}` 는 `[]` 로 마샬링된다. 값 타입 필드는 미전송과 0값이 같다. `omitempty` 는 빈 구조체(`time.Time{}` 포함)를 비어 있다고 보지 않는다. Go 1.24 는 `omitzero` 태그를 추가했다.
- 처방: 응답 컬렉션은 `make([]T, 0)` 로 초기화. 부분 갱신 입력은 포인터 필드(`*int`)로 "미전송" 표현. 구조체/시간 필드 생략은 Go 1.24+ `omitzero`. 엄격 입력이 필요하면 `dec.DisallowUnknownFields()`.
- 반례: —
- 검증: 빈 결과 응답 스냅샷 테스트.
- 근거: https://pkg.go.dev/encoding/json#Marshal , https://go.dev/doc/go1.24#encodingjsonpkgencodingjson

### DTO-S-04 · 2^53 을 넘는 int64 ID 는 JavaScript 클라이언트에서 조용히 반올림된다
- 적용: Snowflake/TSID 같은 64비트 ID, 큰 시퀀스, 프론트엔드·Node 소비자
- 신호: 프론트에서 받은 ID 로 재조회 시 404, 마지막 자릿수 변형
- 메커니즘: JS `Number` 는 IEEE 754 double 이라 `Number.MAX_SAFE_INTEGER`(2^53−1) 초과 정수를 정확히 표현하지 못한다. `JSON.parse` 에서 이미 손실된다.
- 처방: 외부 노출 ID 는 문자열로 직렬화(Jackson `@JsonFormat(shape = STRING)` 또는 `ToStringSerializer`, Go `json:",string"` 태그, Pydantic `PlainSerializer(str)`).
- 반례: 값 범위가 2^53 미만으로 보장되는 ID.
- 검증: 2^53+1 값을 왕복시키는 계약 테스트.
- 근거: https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Number/MAX_SAFE_INTEGER , https://pkg.go.dev/encoding/json#Marshal (",string" option)

### DTO-S-05 · Pydantic v2: `Optional[X]` 는 기본값 없이는 "필수(단 None 허용)" 다
- 적용: Pydantic v1 → v2 이전, FastAPI 요청 모델
- 신호: v2 업그레이드 후 필드 누락 요청이 422
- 메커니즘: v1 은 `Optional[X]` 에 암묵적 기본값 `None` 을 줬지만 v2 는 타입과 필수 여부를 분리한다 — 기본값이 없으면 필수다.
- 처방: 선택 필드는 `x: X | None = None` 으로 기본값을 명시. 외부 필드명 매핑은 `Field(validation_alias=...)`, 응답 별칭은 `serialization_alias`.
- 반례: —
- 검증: 누락 필드 요청 테스트.
- 근거: https://docs.pydantic.dev/latest/migration/#required-optional-and-nullable-fields
