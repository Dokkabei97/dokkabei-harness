---
description: "hard: 기본 할당 전략 목록이면 cooperative-sticky 전환은 롤링 1회 (KFK-CON-02)"
tags: [hard, should-fire, secondary, ko]
max_turns: 12
timeout_seconds: 300
allowed_tools: [Read, Glob, Grep, Skill]
---

Spring Boot 3.3 + spring-kafka 3.2 (kafka-clients 3.7) 로 돌리는 컨슈머 그룹이 있어(파드 30개, 토픽 파티션 120개). 배포할 때마다 그룹 전체가 수십 초씩 처리를 멈춰서 CooperativeStickyAssignor 로 바꾸려고 해.
partition.assignment.strategy 는 지금까지 한 번도 설정한 적 없고(application.yml 에도, 코드에도 없음), 브로커도 3.7 이라 KIP-848 새 group.protocol 은 아직 못 써.
처리 중단 없이 전환하려면 롤링 배포를 몇 번 해야 하고, 각 배포에서 partition.assignment.strategy 를 정확히 뭘로 둬야 하는지 단계별로 알려줘.
