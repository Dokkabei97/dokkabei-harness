---
description: "hard: JDK 17 패치 업데이트 후 availableProcessors=노드 코어 → JVM-GC-03 (JDK-8281181, 17.0.5 백포트)"
tags: [hard, should-fire, ko]
max_turns: 12
timeout_seconds: 300
allowed_tools: [Read, Glob, Grep, Skill]
---

k8s 에서 돌리는 Kotlin Spring Boot 서비스인데, 베이스 이미지를 `eclipse-temurin:17.0.4_8-jre` → `eclipse-temurin:17.0.12_7-jre` 로 **패치 버전만** 올렸어. 코드·JVM 옵션·매니페스트는 그대로야.

그 뒤로 파드당 스레드 수가 확 늘었어. 스레드 덤프에 `GC Thread#0` ~ `GC Thread#42`, `DefaultDispatcher-worker-*` 도 수십 개고, 기동 로그에 찍은 `Runtime.getRuntime().availableProcessors()` 가 64 야(노드가 64코어). 업그레이드 전에는 2 였어.

파드 스펙:
```yaml
resources:
  requests:
    cpu: "2"
    memory: 4Gi
  limits:
    memory: 4Gi   # CPU limit 은 스로틀링 때문에 일부러 안 걸었음
```
JVM 옵션은 `-XX:MaxRAMPercentage=70` 하나뿐이고 UseContainerSupport 는 기본값이야.

패치 버전 하나 올렸을 뿐인데 왜 이렇게 된 건지, CPU limit 을 다시 걸지 않고 어떻게 잡아야 하는지 알려줘.
