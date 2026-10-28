---
description: "should-fire: 대량 HashMap 적재 → JVM-COL-01/KT-COL-02"
tags: [should-fire, ko]
max_turns: 12
timeout_seconds: 300
allowed_tools: [Read, Glob, Grep, Skill]
---

Kotlin 배치에서 DB 조회 결과 수백만 건을 맵에 넣는데 너무 느리고 메모리도 많이 먹어. 코드는 이래:

```kotlin
val byId = HashMap<Long, Order>(rows.size)
rows.forEach { byId[it.id] = it }
```

HashMap에 수백만 건 넣는 배치가 느린 이유랑 고칠 방법 알려줘.
