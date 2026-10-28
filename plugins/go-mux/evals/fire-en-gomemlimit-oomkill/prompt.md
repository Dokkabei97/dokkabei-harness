---
description: "should-fire (EN): GOMEMLIMIT 없음 → GO-GC-01"
tags: [should-fire, en]
max_turns: 12
timeout_seconds: 300
allowed_tools: [Read, Glob, Grep, Skill]
---

Our Go service runs in a container with a 1GiB memory limit and keeps getting OOMKilled, even though the live heap is only around 500MB. GOGC is at the default. How should we fix this?
