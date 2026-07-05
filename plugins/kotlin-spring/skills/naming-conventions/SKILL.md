---
name: naming-conventions
description: |
  Kotlin 네이밍 관용구 — 목적 중심 네이밍(is_expired vs expired_at), Enum value/name 통일, 변환 함수 동사형(convertTo~), const 대문자, 파라미터/도메인 용어 일관성, Map 파라미터 지양, 확장함수 vs 일반함수. Kotlin 작성/리팩토링/코드 리뷰 시 참조.
  Kotlin naming idiom reference — purpose-driven naming (is_expired vs expired_at), consistent Enum value/name, verb-form conversion functions (convertTo~), uppercase const, consistent parameter/domain terminology, avoiding Map parameters, extension vs regular functions. Use when: writing or refactoring Kotlin code, doing Kotlin code review, or settling naming debates.
---

# Kotlin 네이밍 관용구

> 네이밍은 저수준 문제가 아니라 **의도·도메인 용어·유지보수성**의 문제다.
> "이 이름을 처음 보는 사람이 의미를 정확히 추론할 수 있는가?"

---

## 1. 목적 중심 vs 구현 중심 네이밍

외부 인터페이스(public API, 응답 DTO, 도메인 질의)는 **목적**으로 명명한다. 내부 구현 필드는 구현 세부를 드러내도 된다.

### 원칙
- 외부에서 "왜/무엇을 판단하는가"가 중요할 때 → **목적 중심**
- 내부에서 "어떻게 저장/계산되는가"가 중요할 때 → **구현 중심**

### 나쁜 예
```kotlin
data class ProductSearchFieldKey(
    val expired_at: Instant?,  // 외부에서는 "만료 여부"만 궁금
    val created_at: Instant,
    val updated_at: Instant,
)

// 호출부
if (product.expired_at != null && product.expired_at.isBefore(now)) { ... }
```

### 좋은 예
```kotlin
data class ProductSearchFieldKey(
    val isExpired: Boolean,       // 목적: 만료 여부
    val createdAt: Instant,
    val updatedAt: Instant,
) {
    companion object {
        fun from(entity: Product, now: Instant): ProductSearchFieldKey = ProductSearchFieldKey(
            isExpired = entity.expiredAt?.isBefore(now) ?: false, // 내부 구현
            createdAt = entity.createdAt,
            updatedAt = entity.updatedAt,
        )
    }
}
```

### 체크리스트
- [ ] Boolean 필드는 `is`/`has`/`can` 접두사로 **목적**을 표현
- [ ] "판단"은 외부에 노출, "데이터"는 내부에 숨김
- [ ] 계산식이 반복되면 필드를 목적 기반으로 정의

---

## 2. Enum value / name 일치 (불변한 성질 우선)

Enum의 **이름**과 **실제 값**이 시간이 지나도 불변한 성질을 담도록 짓는다.

### 나쁜 예
```kotlin
enum class CatalogSortType {
    RECENT_SCORE,  // score 기반인지 rank 기반인지 바뀔 수 있음
    POPULARITY_SCORE,
    DATE_SCORE,
}
```

### 좋은 예
```kotlin
enum class CatalogSortType {
    RECENT,       // 정렬 기준의 "성질"만 표현
    POPULARITY,   // score를 쓰든 rank를 쓰든 변함 없음
    DATE,
}
```

### 원칙
- Enum value 이름은 구현(`SCORE`, `COUNT`)이 아니라 **의미**를 나타낸다
- 구현 방식이 바뀌어도 이름이 유효해야 한다

### 체크리스트
- [ ] Enum value에 구현 세부(`SCORE`, `RANK`, `INDEX`) 접미사 지양
- [ ] 성질/분류만 이름에 담았는가

---

## 3. 변환 함수는 동사형

Kotlin 관용구상 `to~`는 **단순 표현 전환**(`toInt()`, `toString()`)에 쓴다. 실질적 변환(매핑/검증/조립)은 **`convertTo~`, `mapTo~`, `buildFrom~`** 처럼 동사형으로 명명한다.

### 나쁜 예
```kotlin
fun KeywordResult.toLegacySync(): LegacySync {
    // 여러 필드 매핑 + 검증 + 조립 로직 50줄
    validateKeyword(this)
    val mapped = ...
    return LegacySync(mapped)
}
```

### 좋은 예
```kotlin
fun KeywordResult.convertToLegacySync(): LegacySync {
    validateKeyword(this)
    val mapped = ...
    return LegacySync(mapped)
}

// 단순 표현 전환은 to~ 유지
fun Instant.toEpochMicros(): Long = this.epochSecond * 1_000_000 + this.nano / 1_000
```

### 원칙
- `to~` = 타입 캐스팅 / 단순 표현
- `convertTo~` / `mapTo~` / `buildFrom~` = 실질 변환
- 매핑 로직이 길거나 검증이 포함되면 동사형

### 체크리스트
- [ ] 확장함수 `to~`가 실제로는 매핑/검증을 포함하고 있지 않은가
- [ ] 로직이 10줄 이상이면 `convertTo~`로 리네임 검토

---

## 4. const val 대문자 규칙

Kotlin `const val`은 컴파일 타임 상수. 관례는 `UPPER_SNAKE_CASE`.

### 나쁜 예
```kotlin
object SearchConfig {
    const val maxResults = 100
    const val defaultPage = 1
    const val indexPrefix = "product_"
}
```

### 좋은 예
```kotlin
object SearchConfig {
    const val MAX_RESULTS = 100
    const val DEFAULT_PAGE = 1
    const val INDEX_PREFIX = "product_"
}
```

### 원칙
- `const val` → `UPPER_SNAKE_CASE`
- 일반 `val` (런타임 초기화) → `camelCase`
- 클래스 내 `companion object` 안의 `const val`도 동일

### 체크리스트
- [ ] `const val [a-z]` 패턴 없는가
- [ ] 오브젝트 내 상수 네이밍 일관성

---

## 5. 함수 파라미터 네이밍 — 함수 입장 기준

파라미터 이름은 **호출부의 변수명**이 아니라 **함수 입장에서 자연스러운 역할 이름**으로 짓는다.

### 나쁜 예
```kotlin
// 호출부 변수명을 그대로 가져와 파라미터로
fun ProductDocument.defaultTime(collectedAt: Instant): ProductDocument {
    // 이 함수 입장에서 이 시각은 "수집 시점"이 아니라
    // "기본값으로 쓸 인스턴트"
    return this.copy(indexedAt = this.indexedAt ?: collectedAt)
}
```

### 좋은 예
```kotlin
fun ProductDocument.defaultTime(defaultInstant: Instant): ProductDocument {
    // 함수 내부에서 "기본값 인스턴트"로 쓰임이 드러남
    return this.copy(indexedAt = this.indexedAt ?: defaultInstant)
}

// 호출부
val doc = product.defaultTime(defaultInstant = collectedAt)
// 또는
val doc = product.defaultTime(collectedAt)
```

### 원칙
- 파라미터 이름은 **함수의 내부 시맨틱**을 반영
- 호출 시점의 변수명을 그대로 파라미터명으로 쓰지 않음
- named argument로 호출 측 명확성은 별도 확보

### 체크리스트
- [ ] 파라미터 이름이 함수 역할과 일치하는가
- [ ] 도메인 용어인지, 호출 컨텍스트 용어인지

---

## 6. 도메인 용어 일관성

같은 도메인 개념은 **접두/접미사 규칙**을 일관되게 적용한다. `Token`, `KeywordToken`, `TokenValue` 등 세분화 시 의미 차이가 명확해야 한다.

### 나쁜 예
```kotlin
data class SingleToken(val value: String)      // "단일"이 뭘 뜻하는지 불명확
data class TokenInfo(val tokens: List<String>) // Info는 범용 접미사
data class KeywordData(val text: String)       // Data도 의미 없음
```

### 좋은 예
```kotlin
// Token 자체가 단일 개념 — 접두 불필요
data class Token(val value: String)

// 토큰의 분류/집합 구조를 명확히
data class KeywordToken(val keyword: Keyword, val token: Token)
data class TokenGroup(val tokens: List<Token>, val strategy: TokenizationStrategy)
data class TokenValue(val raw: String, val normalized: String)
```

### 원칙
- 범용 접미사(`Info`, `Data`, `Wrapper`, `Util`) 지양
- 같은 개념은 같은 접두사, 다른 개념은 다른 단어
- "Single", "Simple" 같은 형용사 접두는 실제 대비 대상이 있을 때만

### 체크리스트
- [ ] `~Info`, `~Data`, `~Wrapper`, `~Util` 접미사가 있는가 → 구체화 검토
- [ ] "Single/Simple/Default" 접두가 대비 대상 없이 쓰이지 않았는가
- [ ] 같은 패키지 내 유사 네이밍 간 구분이 명확한가

---

## 7. Map 파라미터 지양 — 구조가 명확하면 data class

`Map<String, Any>` 파라미터는 타입 안정성/IDE 지원을 잃는다. **구조가 명확한 경우** data class를 쓴다.

### 나쁜 예
```kotlin
fun handleAdminKafkaMessage(payload: Map<String, Any>) {
    val id = payload["id"] as? Long ?: error("id missing")
    val op = payload["op"] as? String ?: error("op missing")
    val data = payload["data"] as? Map<String, Any> ?: emptyMap()
    // 런타임까지 구조 보장 없음
}
```

### 좋은 예
```kotlin
data class AdminKafkaPayload(
    val id: Long,
    val op: Operation,
    val data: AdminData,
)

fun handleAdminKafkaMessage(payload: AdminKafkaPayload) {
    // IDE 자동 완성 + 컴파일 타임 타입 검증
}
```

### 원칙
- 파라미터의 키/타입을 **호출 시점에 알 수 있다면** data class
- 진짜 동적이면 `Map<String, Any>` 허용 (예: 설정 로더, generic 어댑터)
- 도메인/application 레이어에서 `Map<String, Any>` 절대 지양

### 체크리스트
- [ ] 파라미터/리턴 타입에 `Map<String, Any>`가 있는가 → data class화 검토
- [ ] 중첩 Map은 nested data class로
- [ ] 도메인 레이어에서 Map<*,*> 사용 중이면 리팩토링 우선순위

---

## 8. 확장함수 vs 일반함수 — primitive 확장 지양

확장함수는 **도메인 타입에 한정**한다. `String`, `Int`, `Long` 같은 primitive에 확장함수를 만들면 **컨텍스트 손실**이 크다.

### 나쁜 예
```kotlin
// 어디서든 "".toKeyword() 호출 가능 → 의미 파악 어려움
fun String.toKeyword(): Keyword = Keyword(this.lowercase())
fun Long.toProductId(): ProductId = ProductId(this)
```

### 좋은 예
```kotlin
// 도메인 객체의 팩토리 메서드 또는 일반함수
object KeywordFactory {
    fun from(raw: String): Keyword = Keyword(raw.lowercase())
}

// 또는 생성자 안에 흡수
data class ProductId(val value: Long) {
    companion object {
        fun from(value: Long): ProductId = ProductId(value)
    }
}
```

### 원칙
- 확장함수는 **도메인 타입에 의미 있는 동작이 있을 때**만
- primitive 타입 확장은 호출부에서 "이게 어떤 데이터인지" 컨텍스트 파악 불가
- 팩토리 패턴 또는 companion object 메서드 우선

### 체크리스트
- [ ] `String.*`, `Int.*`, `Long.*` 확장함수가 있는가
- [ ] 도메인 의미를 담은 확장은 도메인 타입에 붙였는가

---

## 빠른 참조 — 검색 테크리더 리뷰 규칙 요약

| 상황 | 규칙 |
|---|---|
| Boolean 필드 | `isExpired` (목적) vs `expiredAt` (구현) — 외부는 목적 중심 |
| Enum value | `POPULARITY` (성질) — `POPULARITY_SCORE` (구현 세부) 금지 |
| 매핑 함수 | `convertToX()` — `toX()`는 단순 캐스팅만 |
| const 상수 | `const val MAX_RESULTS` — 소문자 금지 |
| 파라미터 네이밍 | 함수 내부 역할 (`defaultInstant`) > 호출부 변수명 (`collectedAt`) |
| 도메인 용어 | `~Info`, `~Data`, `~Wrapper` 범용 접미사 지양 |
| 파라미터 타입 | `Map<String, Any>` 지양, data class 우선 |
| 확장함수 | 도메인 타입만, primitive 확장 지양 |

---

## 네이밍 의사결정 순서

1. 이 이름을 **처음 보는 동료**가 맥락 없이 의미를 추론할 수 있는가?
2. **외부 인터페이스**인가 **내부 구현**인가? (목적 vs 구현)
3. **시간이 지나도** 이름이 유효한 성질을 담았는가?
4. 같은 도메인에서 **유사 이름**과 구분이 명확한가?
5. IDE 자동완성 시 **자동완성 목록**에서 혼동이 없는가?
