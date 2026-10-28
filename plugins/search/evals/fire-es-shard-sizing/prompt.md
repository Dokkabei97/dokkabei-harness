---
description: "should-fire: 샤드 개수 산정 → ES-SHD-01"
tags: [should-fire, ko]
max_turns: 12
timeout_seconds: 300
allowed_tools: [Read, Glob, Grep, Skill]
---

ES 샤드를 몇 개로 잡아야 해? 애플리케이션 로그가 하루 50GB 씩 들어오고 30일 보관해. 지금은 날짜별 인덱스에 프라이머리 10개로 만들고 있어.
