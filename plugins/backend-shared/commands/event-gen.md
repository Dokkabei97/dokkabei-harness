---
name: event-gen
description: |
  이벤트 기반 코드 스캐폴딩 생성 — Kafka Producer/Consumer, Spring ApplicationEvent, AsyncAPI 스펙
  Scaffolds event-driven code — Kafka Producer/Consumer, Spring ApplicationEvent, and AsyncAPI specs. Use when: adding Kafka producers or consumers, wiring Spring application events, writing an AsyncAPI spec for event contracts.
category: scaffold
complexity: basic
mcp-servers: []
personas: []
---

# /event-gen - 이벤트 기반 코드 스캐폴딩

## Triggers
- Kafka Producer/Consumer 코드를 새로 작성할 때
- 도메인 이벤트 기반 아키텍처를 구현할 때
- 이벤트 발행/구독 코드의 보일러플레이트를 줄이고 싶을 때
- 기존 동기 호출을 이벤트 기반으로 전환할 때
- AsyncAPI 스펙 문서가 필요할 때

## Usage
```
/event-gen [설명] [옵션]

Options:
  --lang kotlin|python|auto       대상 언어 (기본: auto-detect)
  --type kafka|app-event|both     이벤트 타입 (기본: kafka)
  --with-test                     테스트 스텁 포함
  --with-spec                     AsyncAPI 스펙 생성
  --with-dlq                      Dead Letter Queue 설정 포함
```

## Behavioral Flow

### 생성 플로우
1. **Discover**: 프로젝트 구조 분석, Kafka 의존성/설정 탐지, 기존 이벤트/메시지 패턴 파악
2. **Design**: 토픽 네이밍 (`{도메인}.{엔티티}.{액션}`), 이벤트 페이로드 스키마, 키 전략, 파티셔닝
3. **Generate**:
   - **Kafka Kotlin**: ProducerConfig, KafkaTemplate wrapper, @KafkaListener consumer, Event DTO, Serializer/Deserializer
   - **Kafka Python**: aiokafka producer/consumer, Pydantic event schema, serializer
   - **ApplicationEvent Kotlin**: Event class, Publisher service, @TransactionalEventListener handler
   - **Both**: Producer + Consumer + Event DTO + DLQ handler + Test
4. **Validate**: 컴파일/타입 체크
5. **Document**: (--with-spec) AsyncAPI 2.6 YAML 스펙 생성

## Generated Files

### Kotlin Kafka 예시
```
src/main/kotlin/{package}/
├── event/
│   ├── OrderCompletedEvent.kt           # Event DTO
│   ├── OrderEventProducer.kt            # KafkaTemplate 래퍼
│   ├── OrderEventConsumer.kt            # @KafkaListener
│   └── OrderEventDeadLetterHandler.kt   # DLQ 핸들러 (--with-dlq)
├── config/
│   └── KafkaConfig.kt                   # Producer/Consumer 설정
└── test/
    ├── OrderEventProducerTest.kt        # (--with-test)
    └── OrderEventConsumerTest.kt        # (--with-test)
```

### Python Kafka 예시
```
app/
├── events/
│   ├── schemas.py                       # Pydantic event models
│   ├── producer.py                      # AIOKafkaProducer wrapper
│   ├── consumer.py                      # AIOKafkaConsumer handler
│   └── dlq.py                           # DLQ 핸들러 (--with-dlq)
└── tests/
    ├── test_producer.py                 # (--with-test)
    └── test_consumer.py                 # (--with-test)
```

## Tool Coordination
- **Glob**: 프로젝트 구조 탐색, 기존 이벤트 파일 확인
- **Read**: build.gradle.kts / pyproject.toml 의존성 확인, 기존 이벤트 패턴 분석
- **Write**: 새 파일 생성
- **Grep**: 기존 토픽명, 이벤트 클래스 검색
- **Bash**: 컴파일/타입 검증

## Examples

### Kotlin Kafka 이벤트 생성
```
/event-gen 주문 완료 이벤트
# order.completed 토픽으로 Producer/Consumer 생성
# Event DTO, KafkaConfig, KafkaTemplate 래퍼 포함
```

### Python Kafka 이벤트 생성 + 테스트
```
/event-gen 결제 승인 이벤트 --lang python --with-test
# payment.approved 토픽으로 Producer/Consumer 생성
# Pydantic schema, aiokafka 래퍼, pytest 테스트 스텁 포함
```

### Spring ApplicationEvent 생성
```
/event-gen 재고 변경 알림 --type app-event
# InventoryChangedEvent 클래스 생성
# Publisher 서비스, @TransactionalEventListener 핸들러 포함
```

### AsyncAPI 스펙 포함 생성
```
/event-gen 배송 상태 변경 --type both --with-spec --with-dlq
# Kafka + ApplicationEvent 양쪽 모두 생성
# AsyncAPI 2.6 YAML 스펙, DLQ 핸들러 포함
```

## Output Format
```
## Event Gen 생성 결과

### 요약
- 이벤트 타입: Kafka Producer/Consumer
- 대상 언어: Kotlin
- 토픽: order.order.completed
- 생성 파일: 5개

### 생성 파일 목록
| 파일 | 역할 | 설명 |
|------|------|------|
| OrderCompletedEvent.kt | Event DTO | 이벤트 페이로드 데이터 클래스 |
| OrderEventProducer.kt | Producer | KafkaTemplate 기반 발행 서비스 |
| OrderEventConsumer.kt | Consumer | @KafkaListener 기반 구독 핸들러 |
| KafkaConfig.kt | Config | Producer/Consumer Bean 설정 |
| OrderEventProducerTest.kt | Test | Testcontainers Kafka 통합 테스트 |
```

## Boundaries

**Will:**
- Kafka Producer/Consumer, ApplicationEvent 보일러플레이트 코드 생성
- 이벤트 DTO/Schema, 설정 파일, DLQ 핸들러 스캐폴딩
- AsyncAPI 스펙 문서 생성
- 테스트 스텁 생성 (Testcontainers Kafka)

**Will Not:**
- Kafka 토픽 생성, 파티션 설정 등 인프라 관리
- 기존 이벤트 코드 리팩터링
- Avro/Protobuf 스키마 레지스트리 설정
- 운영 환경 배포 및 모니터링 설정

## Related
- `async-event-patterns` 스킬 — 이벤트 패턴 레퍼런스
- `/api-gen --style event` — REST/GraphQL + 이벤트 통합 스캐폴딩
- `/api-test --with-events` — 이벤트 검증 테스트
