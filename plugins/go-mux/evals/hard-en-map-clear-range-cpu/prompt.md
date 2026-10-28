---
description: "hard (EN): clear(m) 도 용량 유지 + range 비용은 피크 용량 비례 + Swiss map 도 축소 안 함 → GO-MAP-02"
tags: [should-fire, hard, en]
max_turns: 12
timeout_seconds: 300
allowed_tools: [Read, Glob, Grep, Skill]
---

Our Go service (toolchain 1.25) keeps an in-flight dedupe set `map[string]struct{}` guarded by a mutex. During a replay storm last week it grew to about 4 million keys. Since then a janitor calls `clear(m)` every minute and `len(m)` normally sits below 50.

Two things still look wrong: the heap never came back down after the storm, and a background reconciler that does `for k := range m { ... }` every 10ms is now the top CPU consumer — the profile shows the map iterator (`runtime.(*Iter).Next` / `mapiternext`) at the top even though the map is almost empty. I thought the Swiss-table maps in Go 1.24+ fixed the "maps never shrink" problem. What is going on, and what is the right fix?
