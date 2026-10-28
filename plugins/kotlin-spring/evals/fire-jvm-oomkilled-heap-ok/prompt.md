---
description: "should-fire: 컨테이너 OOMKilled, 힙 여유 → JVM-GC-02/JVM-MEM-01/JVM-GC-09"
tags: [should-fire, ko]
max_turns: 12
timeout_seconds: 300
allowed_tools: [Read, Glob, Grep, Skill]
---

쿠버네티스에 띄운 Spring Boot(Kotlin, JDK 21) 파드가 컨테이너에서 계속 OOMKilled(exit 137)로 죽어. 메모리 limit 은 2Gi 이고, 힙 사용량 그래프를 보면 힙은 여유가 있어. 왜 이런 거고 뭘 확인하고 어떻게 잡아야 해?
