---
description: "should-fire (EN): 초기 대량 적재 → ES-IDX-02/ES-IDX-03"
tags: [should-fire, en]
max_turns: 12
timeout_seconds: 300
allowed_tools: [Read, Glob, Grep, Skill]
---

We're bulk indexing about 200 million documents into a brand-new Elasticsearch index for the initial load and it's very slow. What index settings and bulk request sizing should we change during the load?
