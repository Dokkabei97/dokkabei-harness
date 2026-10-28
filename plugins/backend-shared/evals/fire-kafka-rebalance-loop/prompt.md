---
description: "should-fire (secondary, async-event-patterns): Kafka 리밸런스 반복 → KFK-CON-01/02"
tags: [should-fire, secondary, ko]
max_turns: 12
timeout_seconds: 300
allowed_tools: [Read, Glob, Grep, Skill]
---

Spring Kafka 컨슈머 리밸런스가 계속 일어나. 레코드마다 외부 API 를 호출하는데 그게 느려지면 같은 메시지가 계속 다시 처리되는 것 같아. 설정은 거의 기본값이야. 원인이랑 해결책 알려줘.
