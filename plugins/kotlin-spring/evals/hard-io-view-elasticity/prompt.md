---
description: "hard (EN): IO 뷰 탄력성 + Default.limitedParallelism 반례 → KT-CORO-01"
tags: [hard, should-fire, en]
max_turns: 12
timeout_seconds: 300
allowed_tools: [Read, Glob, Grep, Skill]
---

We run a Kotlin Spring Boot service (kotlinx.coroutines 1.8, 8 vCPU pods, HikariCP maximumPoolSize = 30). We split our blocking work into two dispatchers:

```kotlin
object AppDispatchers {
    // JDBC calls (blocking). Put on Default so slow partner calls on IO can't starve the DB path.
    val db = Dispatchers.Default.limitedParallelism(30)

    // Blocking partner HTTP client, sometimes slow
    val partner = Dispatchers.IO.limitedParallelism(100)
}
```

A reviewer left this comment on the PR:

> `Dispatchers.IO.limitedParallelism(100)` is pointless — Dispatchers.IO is capped at 64 threads and limitedParallelism can only lower parallelism, never raise it, so you effectively get 64. Change it to 64 and set `-Dkotlinx.coroutines.io.parallelism=200` globally instead. The `db` dispatcher on Default is fine.

Is the reviewer right? Please review both dispatchers and tell us what to change.
