# ProductLegacySyncListener에서 ConsumerCallbackManager 제거

## Context

`ProductLegacySyncListener`는 레거시 시스템으로의 역싱크를 담당하는 Kafka 리스너다. 현재 `FlinkCdcBatchListener`를 상속하여 `ConsumerCallbackManager`, `rewindIfNeeded()`, `ConsumerSeekAware` 콜백 등을 물려받고 있지만, 역싱크 리스너에서는 이 기능들이 불필요하다.

## 현재 상속 구조

```
FlinkCdcBatchListener(groupId, consumerCallbackManager) : ConsumerSeekAware
├── CatalogDynamicIndexListener  ← rewindIfNeeded(), ConsumerSeekAware 모두 사용
├── ProductDynamicIndexListener  ← rewindIfNeeded(), ConsumerSeekAware 모두 사용
└── ProductLegacySyncListener    ← 불필요 (단순 역싱크, offset seek 불필요)
```

`FlinkCdcBatchListener`의 모든 기능(`createConsumerManager`, `rewindIfNeeded`, `checkToSeek`, `ConsumerSeekAware` 콜백)이 `ConsumerCallbackManager`에 의존하므로, ProductLegacySyncListener가 사용하는 부모 기능은 사실상 없다.

---

## 방안 A: ProductLegacySyncListener 상속 제거 (권장)

FlinkCdcBatchListener를 건드리지 않고, ProductLegacySyncListener만 독립시킨다.

### 변경 대상 파일

**1. `ProductLegacySyncListener.kt`**
- 경로: `inbound-adapter/handler/.../listener/ProductLegacySyncListener.kt`
- `FlinkCdcBatchListener` 상속 제거, 생성자에서 `groupId`/`consumerCallbackManager` 제거
- `BatchAcknowledgingConsumerAwareMessageListener` 직접 구현
- `rewindIfNeeded()` 호출 제거, 불필요한 import 정리

**2. `LegacySyncKafkaConfig.kt`**
- 경로: `inbound-adapter/handler/.../config/LegacySyncKafkaConfig.kt`
- 생성자에서 `consumerCallbackManager` 의존성 제거
- `ProductLegacySyncListener` 생성 시 `groupId`, `consumerCallbackManager` 인자 제거

### 장점
- 변경 범위 최소 (2개 파일)
- 기존 Dynamic Index 리스너에 영향 없음
- 역할이 명확해짐 (역싱크 리스너는 seek 불필요)

---

## 방안 B: FlinkCdcBatchListener 리팩터링

ConsumerCallbackManager를 optional로 만들어 seek 기능이 필요 없는 리스너도 상속 가능하게 한다.

### 변경 대상 파일

**1. `FlinkCdcBatchListener.kt`**
- `consumerCallbackManager: ConsumerCallbackManager` → `consumerCallbackManager: ConsumerCallbackManager? = null`
- `ConsumerSeekAware` 콜백들: null이면 no-op
- `rewindIfNeeded()`, `checkToSeek()`: null이면 no-op
- `createConsumerManager().commit()`: null이면 seekMap 처리 스킵

**2. `ProductLegacySyncListener.kt`**
- 생성자에서 `consumerCallbackManager` 제거 (부모에 null 전달)
- `rewindIfNeeded()` 호출은 유지해도 되고 제거해도 됨 (null이면 no-op)

**3. `LegacySyncKafkaConfig.kt`**
- `consumerCallbackManager` 인자 제거

### 단점
- FlinkCdcBatchListener 전체에 null 체크 분산
- "항상 필요한 의존성"을 optional로 만드는 것은 설계 의도를 흐림
- CatalogDynamicIndexListener, ProductDynamicIndexListener에도 간접적 영향

---

## 권장: 방안 A

방안 A가 변경 범위가 작고, 설계 의도가 더 명확하다. `ProductLegacySyncListener`는 offset seek가 필요 없으므로 `FlinkCdcBatchListener` 상속 자체가 불필요하다.

## 검증

```bash
./gradlew :inbound-adapter:handler:test
./gradlew :inbound-adapter:handler:ktlintCheck
```
