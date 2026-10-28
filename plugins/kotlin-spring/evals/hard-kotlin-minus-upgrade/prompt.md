---
description: "hard: Kotlin 1.5→2.0 업그레이드 후 list - list O(n·m) → KT-COL-05"
tags: [hard, should-fire, ko]
max_turns: 12
timeout_seconds: 300
allowed_tools: [Read, Glob, Grep, Skill]
---

Kotlin Spring Boot 정산 배치 얘기야. Kotlin 을 1.5.31 → 2.0.21 로, Spring Boot 를 2.7 → 3.3 으로 올린 뒤 야간 배치 하나가 20분 → 3시간 넘게 걸려. 이 구간 코드는 1년 넘게 안 바뀌었어.

```kotlin
val existingIds: List<Long> = settlementRepository.findAllIdsByDate(date)   // 약 40만 건
val incomingIds: List<Long> = partnerFile.lines().map { it.toLong() }        // 약 40만 건

val toDelete = existingIds - incomingIds
val toInsert = incomingIds - existingIds
```

async-profiler 로 보니 CPU 대부분이 `ArrayList.indexOf` 랑 `CollectionsKt` 의 `minus` 아래에 있어. 업그레이드 때 다른 건 JDK 11 → 21 정도야.
코드가 그대로인데 왜 업그레이드 후에 이렇게 느려졌는지, 그리고 어떻게 고치면 되는지 알려줘.
