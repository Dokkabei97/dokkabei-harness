---
description: "should-fire: map delete 후 메모리 미반환 → GO-MAP-02/GO-GC-08"
tags: [should-fire, ko]
max_turns: 12
timeout_seconds: 300
allowed_tools: [Read, Glob, Grep, Skill]
---

Go 서비스 RSS가 계속 늘어나. 세션을 `map[string]*Session` 에 넣고 세션이 끝나면 map에서 delete 하는데도 메모리가 안 줄어. 트래픽 피크 때 수백만 개까지 갔다가 지금은 몇천 개뿐이야. 누수야? 어떻게 해야 해?
