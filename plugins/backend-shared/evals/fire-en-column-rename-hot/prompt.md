---
description: "should-fire (EN): 무중단 컬럼 rename → PG-MIG-14 expand-contract"
tags: [should-fire, en]
max_turns: 12
timeout_seconds: 300
allowed_tools: [Read, Glob, Grep, Skill]
---

We need to rename the column user_name to username on a hot Postgres table without downtime, while old app pods are still running during a rolling deploy. How should the migration and deploy sequence go?
