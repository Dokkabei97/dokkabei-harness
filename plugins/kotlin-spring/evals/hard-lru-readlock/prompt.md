---
description: "hard: access-order LinkedHashMap + read lock 의 get → JVM-COL-05"
tags: [hard, should-fire, ko]
max_turns: 12
timeout_seconds: 300
allowed_tools: [Read, Glob, Grep, Skill]
---

Kotlin Spring 서비스에서 토큰 캐시를 이렇게 만들어 쓰고 있어. 읽기는 read lock, 쓰기는 write lock 으로 나눴으니 스레드 안전하다고 생각했는데,
트래픽이 몰리면 가끔 `/actuator/tokens` (아래 `snapshot()`) 에서 `ConcurrentModificationException` 이 나고, 드물게 요청 스레드 하나가 CPU 100% 로 안 끝나거나 캐시 크기가 `max` 를 넘어 있는 게 보여.

```kotlin
class TokenCache(private val max: Int) {
    private val lock = ReentrantReadWriteLock()
    private val map = object : LinkedHashMap<String, Token>(16, 0.75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, Token>?) = size > max
    }

    fun get(key: String): Token? = lock.read { map[key] }
    fun put(key: String, token: Token) = lock.write { map[key] = token }
    fun snapshot(): List<Token> = lock.read { map.values.toList() }
}
```

put 은 write lock 안에 있는데 왜 이런 일이 생기는지, 어떻게 고쳐야 하는지 리뷰해줘.
