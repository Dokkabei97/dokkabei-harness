---
description: "hard: launch 위임 리스너 유실 → Spring Kafka 3.2+ suspend 리스너 (KFK-CON-04)"
tags: [hard, should-fire, secondary, ko]
max_turns: 12
timeout_seconds: 300
allowed_tools: [Read, Glob, Grep, Skill]
---

Spring Boot 3.4 + spring-kafka 3.3, Kotlin 이야. 컨테이너 설정(AckMode 등)은 전부 기본값이고, 리스너는 이렇게 생겼어.

```kotlin
@Component
class OrderEventListener(private val handler: OrderHandler) {
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    @KafkaListener(topics = ["order-events"], groupId = "order-sync")
    fun onMessage(record: ConsumerRecord<String, String>) {
        scope.launch { handler.handle(record.value()) } // handle 은 suspend fun, 안에서 외부 API 호출
    }
}
```

배포나 파드 재시작 뒤에 일부 이벤트가 처리 안 된 채로 사라지고, handle 이 예외를 던져도 재시도나 DLT 로 안 가. handler 는 코루틴 그대로 쓰고 싶어. 원인이랑, 가장 작은 변경으로 고치는 방법을 알려줘.
