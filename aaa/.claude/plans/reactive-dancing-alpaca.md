# Legacy Sync categoryId NPE 수정 계획

## Context

Kafka CDC로 들어오는 Product 데이터의 `categoryId`가 null인 경우 NPE가 발생.
Avro 스키마에서 Product의 모든 필드가 nullable (`["null", "int"]`)이지만,
Kotlin 코드에서 non-null로 받고 있어 타입 불일치 발생.

에러: `getCategoryId(...) must not be null` at `LegacySyncMapper.kt:130`

## 수정 파일 (2개)

### 1. `inbound-adapter/legacy/.../LegacyReserveSyncListener.kt`

**라인 31** — `product.categoryId > 0`에서 categoryId가 null이면 unboxing NPE

```kotlin
// Before
product != null && product.categoryId > 0
// After
product != null && (product.categoryId ?: 0) > 0
```

### 2. `application/index/.../LegacySyncMapper.kt`

**라인 127** — `shopId = mallId`에서 mallId도 `java.lang.Integer` (nullable)

```kotlin
// Before
shopId = mallId,
// After
shopId = mallId ?: 0,
```

> 라인 130 `categoryId = categoryId ?: 0`은 이미 수정 완료

## 검증

```bash
./gradlew :application:index:test
./gradlew :inbound-adapter:legacy:test
./gradlew ktlintCheck
```
