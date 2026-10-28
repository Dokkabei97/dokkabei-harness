---
description: "should-fire (EN): Dispatchers.IO 64 상한 포화 → KT-CORO-01"
tags: [should-fire, en]
max_turns: 12
timeout_seconds: 300
allowed_tools: [Read, Glob, Grep, Skill]
---

Our Kotlin Spring Boot service wraps blocking JDBC calls and a slow external HTTP API in withContext(Dispatchers.IO). Once concurrent requests go past roughly 64, latency spikes and thread dumps show every IO worker waiting. What's going on and how should we fix it?
