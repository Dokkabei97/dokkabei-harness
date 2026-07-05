---
name: dto-design-patterns
description: |
  Kotlin DTO 설계 패턴 — Request/Response/Projection 구분, Map 지양 data class 우선, 필수 필드 명시(channel), 확장성 vs 단순성 결정 기준, nullable 정책, Jackson/Pydantic 직렬화. DTO/Request/Response 작성·리뷰 시 참조.
  Kotlin DTO design patterns — Request/Response/Projection separation, preferring data classes over Maps, explicit required fields (channel), extensibility vs simplicity criteria, nullable policy, and Jackson/Pydantic serialization. Use when: writing or reviewing DTOs, request/response models, or serialization mappings.
---

# Kotlin DTO 설계 패턴

> DTO(Data Transfer Object)는 **경계를 건너는 데이터의 계약**이다. 구조가 명확할수록 호출자의 실수를 막는다.
> 이 가이드는 Kotlin/Spring Boot 기준이지만 Python/FastAPI에도 유사한 원칙 적용.

---

## 1. Map<String, Any> 지양 — 구조가 명확하면 data class

### 원칙
- 파라미터/리턴의 **키와 타입을 호출 시점에 알 수 있다면** 반드시 data class
- 진짜 동적인 경우만 `Map<String, Any>` 허용 (설정 로더, generic adapter)
- **도메인/application 레이어에서 Map<*, *>은 금지**

### 나쁜 예
```kotlin
// Kafka 메시지 핸들러 — 페이로드 구조가 알려져 있는데 Map으로 받음
fun handleAdminKafkaMessage(payload: Map<String, Any>) {
    val id = payload["id"] as? Long ?: error("id missing")
    val op = payload["op"] as? String ?: error("op missing")
    val data = payload["data"] as? Map<String, Any> ?: emptyMap()
    // 런타임 타입 체크 + 에러 메시지 문자열 — IDE 지원 0
}
```

### 좋은 예
```kotlin
data class AdminKafkaPayload(
    val id: Long,
    val op: Operation,
    val data: AdminData,
)

enum class Operation { CREATE, UPDATE, DELETE, READ }

data class AdminData(
    val channel: Channel,
    val metadata: Map<String, String> = emptyMap(), // 실제 동적 부분만 Map
)

fun handleAdminKafkaMessage(payload: AdminKafkaPayload) {
    // 컴파일 타임 타입 검증 + IDE 자동완성 + refactor safe
}
```

### 체크리스트
- [ ] `Map<String, Any>` 파라미터/리턴이 있는가 → 구조 명확성 확인
- [ ] `Map<String, String>` 중 키 목록이 고정적이면 data class화
- [ ] 중첩 Map은 nested data class로

---

## 2. Request — 필수 필드는 nullable 금지, 명시 강제

클라이언트가 반드시 전달해야 하는 값은 **non-null**로 두어 컴파일/검증 단계에서 강제한다. nullable로 두면 누락 시 런타임 NPE로 이어진다.

### 나쁜 예
```kotlin
data class SearchAdminCatalogRequest(
    val keyword: String?,        // 검색어는 필수 아닐 수 있음 (OK)
    val channel: Channel?,       // 채널은 서비스상 필수인데 nullable로?
    val page: Int?,              // 페이지는 기본값이 있어야지 nullable은 부적절
    val size: Int?,
)

// 서비스 로직
fun search(req: SearchAdminCatalogRequest) {
    val channel = req.channel ?: error("channel required") // 런타임 폭발
    val page = req.page ?: 1
    val size = req.size ?: 20
}
```

### 좋은 예
```kotlin
data class SearchAdminCatalogRequest(
    val keyword: String? = null,  // 진짜 선택적 — nullable + default
    val channel: Channel,         // 필수 — non-null
    val paging: SearchPaging = SearchPaging.DEFAULT, // 기본값 있는 필수
)

data class SearchPaging(
    val page: Int,
    val size: Int,
) {
    init {
        require(page >= 1) { "page must be >= 1" }
        require(size in 1..200) { "size must be 1..200" }
    }

    companion object {
        val DEFAULT = SearchPaging(page = 1, size = 20)
    }
}
```

### 체크리스트
- [ ] 비즈니스상 **필수**인 필드가 nullable로 선언되지 않았는가
- [ ] 기본값이 있는 옵션은 default value 활용 (nullable 남용 금지)
- [ ] 검증 규칙(`init`/`@field:Min`/`@field:NotBlank`)으로 호출자 실수 방지

---

## 3. Response — 도메인 엔티티 직접 노출 금지

### 원칙
- `@Entity`/`@Document`를 그대로 응답하지 않음 (내부 구조 누출)
- `Projection` / `Response` data class로 필요한 필드만 노출
- nullable 정책은 도메인 엔티티의 실제 상태를 반영 (not-null이면 non-null)

### 나쁜 예
```kotlin
@GetMapping("/users/{id}")
fun getUser(@PathVariable id: Long): ResponseEntity<UserEntity> {
    return ResponseEntity.ok(userRepository.findById(id).orElseThrow())
    // UserEntity 모든 필드 노출 (password hash 포함 가능)
}

data class AdminSearchResponse(
    val id: Long?,             // 도메인에서는 not-null인데 응답은 nullable?
    val name: String?,
    val isFeatured: Boolean?,  // default false로 충분
    val tags: List<String>?,   // null vs empty 구분 없음
)
```

### 좋은 예
```kotlin
@GetMapping("/users/{id}")
fun getUser(@PathVariable id: Long): ResponseEntity<UserResponse> {
    val user = userService.findById(id)
    return ResponseEntity.ok(UserResponse.from(user))
}

data class UserResponse(
    val id: Long,
    val name: String,
    val email: String,
) {
    companion object {
        fun from(user: User): UserResponse = UserResponse(
            id = user.id.value,
            name = user.name,
            email = user.email,
        )
    }
}

data class AdminSearchResponse(
    val id: Long,
    val name: String,
    val isFeatured: Boolean = false,  // not-null + default
    val tags: List<String> = emptyList(),
)
```

### 체크리스트
- [ ] `ResponseEntity<*Entity>` 패턴 없는가
- [ ] 도메인 엔티티에서 not-null인 필드가 응답에서 nullable로 바뀌지 않았는가
- [ ] List/Map/Set은 `?` 대신 default `emptyList()`/`emptyMap()`/`emptySet()`
- [ ] 민감 필드(password, token, internal ID) 누출 없는가

---

## 4. 확장성 vs 단순성 결정 기준

"나중에 필드가 늘어날 수도 있다"는 추측만으로 모든 필드를 nullable/선택적으로 만들면 계약이 모호해진다.

### 결정 원칙
- **단순 구조가 안전한 기본** — YAGNI (You Aren't Gonna Need It)
- 확장 필요 **시점에** 구조를 고민 (그때는 이미 요구사항이 명확)
- 진짜 확장 가능성이 있는 경우 → **전략 패턴/sealed class** 활용

### 나쁜 예
```kotlin
// "향후 aggregation 종류가 여러 개가 될 수 있다"며 모든 필드 nullable
data class CountRequest(
    val categoryField: String?,      // 뭐가 들어가는지 불명확
    val filterRequest: FilterRequest?, // 모든 filter 필드 nullable이라 조합 검증 불가능
    val groupBy: String?,
    val having: String?,
    val topN: Int?,
)
```

### 좋은 예 — 현재 요구사항에 맞춰 단순하게
```kotlin
data class CategoryCountRequest(
    val category: Category,        // 현재는 category 단일 집계만
    val filters: CategoryFilters,  // 필요 필드만 명시
)

data class CategoryFilters(
    val channel: Channel,          // 필수
    val dateRange: DateRange? = null,
    val productIds: List<Long> = emptyList(),
)
```

### 좋은 예 — 진짜 확장 필요 시 sealed class
```kotlin
sealed interface AggregationRequest {
    val channel: Channel

    data class CategoryCount(
        override val channel: Channel,
        val category: Category,
    ) : AggregationRequest

    data class BrandCount(
        override val channel: Channel,
        val brandId: Long,
    ) : AggregationRequest
}
```

### 체크리스트
- [ ] "향후 확장"이라는 이유로 모든 필드를 nullable/String으로 두지 않았는가
- [ ] 현재 요구사항에 **최소한의 구조**인가
- [ ] 확장 가능성이 현실이면 sealed class/전략 패턴으로 **구조적 분기**

---

## 5. 파라미터 설계 — ids vs variables

단일 식별자 리스트인지, **다조건 객체**인지 의도를 명확히 구분한다.

### 나쁜 예
```kotlin
// 처음엔 ids만 필요해서 List<Long>으로 받음
fun query(ids: List<Long>): List<Product> = ...

// 2주 후 "status, channel 같이 받아야 한다"는 요구
fun query(ids: List<Long>, status: Status, channel: Channel): List<Product> = ...
// → 호출부 전부 수정, named argument 강제, overload 난립
```

### 좋은 예
```kotlin
// 처음부터 조건 객체로 받음
data class ProductQueryVariables(
    val ids: List<Long> = emptyList(),
    val status: Status? = null,
    val channel: Channel? = null,
)

fun query(variables: ProductQueryVariables): List<Product> = ...

// 확장 시 호출부 영향 최소화
```

### 원칙
- 파라미터가 "조건 모음"이면 **처음부터 객체**로
- 정말 단일 식별자만 받으면 `List<Long>` OK
- GraphQL `variables`, SQL `WHERE` 조건, ES Query 필터는 객체로 받는 게 일반적

---

## 6. 외부 API 응답 → DTO 매핑 (신뢰 경계)

Third-party API 응답은 **신뢰할 수 없는 데이터**로 간주. 반드시 DTO로 매핑하고 유효성 검증한 후 도메인으로 전달.

### 나쁜 예
```kotlin
fun fetchLegacyProduct(id: Long): Map<String, Any> {
    return legacyApiClient.get("/products/$id")
    // 외부 응답을 그대로 사용 — 필드 변경 시 전사적 영향
}
```

### 좋은 예
```kotlin
data class LegacyProductResponse(
    @JsonProperty("prd_id") val productId: Long,
    @JsonProperty("prd_nm") val name: String,
    @JsonProperty("reg_dt") val registeredAt: String, // "2025-11-12T00:00:00"
)

fun fetchLegacyProduct(id: Long): Product {
    val dto = legacyApiClient.get<LegacyProductResponse>("/products/$id")
    return Product(
        id = ProductId(dto.productId),
        name = dto.name.trim().also { require(it.isNotBlank()) },
        registeredAt = Instant.parse(dto.registeredAt + "Z"),
    )
}
```

### 체크리스트
- [ ] 외부 API 응답이 `Map<*, *>`나 `String` 그대로 돌아다니지 않는가
- [ ] DTO → 도메인 전환 지점에 **검증 코드**가 있는가
- [ ] 외부 필드명(snake_case)과 내부 필드명(camelCase) 매핑이 명확한가

---

## 7. Jackson / Pydantic 직렬화 경계

### Kotlin + Jackson
- `@JsonProperty`는 **외부 필드명이 Kotlin 규칙과 다를 때**만
- `@JsonIgnore`는 민감 필드 응답 제외
- `jackson-module-kotlin`: data class에 기본 생성자 자동 생성 (반드시 의존성 포함)

### Python + Pydantic v2
- `model_config = ConfigDict(strict=True)` — 타입 변환 금지
- `Field(..., validation_alias='prd_id')` — 외부 필드 매핑
- `field_validator` — 값 변환/검증 분리

### 체크리스트
- [ ] 응답 DTO에 `@JsonIgnore`로 민감 필드 제외했는가
- [ ] `@JsonProperty` 명명은 외부 계약 기준 (snake_case 등)
- [ ] 역직렬화 실패 시 에러 메시지가 충분히 설명적인가

---

## 빠른 참조 — DTO 설계 의사결정

| 상황 | 원칙 |
|---|---|
| 파라미터/리턴 타입 선택 | `Map<String, Any>` 지양, 구조 명확하면 data class |
| Request nullable | 비즈니스 필수 = non-null, 진짜 옵션 = nullable + default |
| Response 설계 | Entity 직접 노출 금지, Projection/Response로 매핑 |
| List/Map 필드 | `List<*>?`, `Map<*, *>?` 지양 → default `emptyList()` / `emptyMap()` |
| 확장성 vs 단순성 | 단순함이 기본값, 확장 가능성이 **현실이면** sealed class |
| 다조건 파라미터 | 처음부터 조건 객체로 (SQL WHERE, GraphQL variables) |
| 외부 API 응답 | 반드시 DTO → 도메인 매핑 + 검증 |
| Jackson 사용 | `@JsonProperty` 외부 이름만, `@JsonIgnore` 민감 필드 |

---

## 관련 스킬/하네스

- `naming-conventions` — 목적 중심 네이밍 / enum 통일 / 변환 함수 동사형
- `hexagonal-architecture` — 레이어별 데이터 모델 (Domain Entity vs DTO vs Adapter DTO)
- Hook: `kotlin-nullable-policy` — data class nullable 비율 >70% 감지
- Hook: `hexagonal-boundary-check` — 도메인 레이어의 Spring/Jackson import 감지
