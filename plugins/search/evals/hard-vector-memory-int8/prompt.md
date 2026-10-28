---
description: "hard (EN): dense_vector RAM 산정 — 8.15 기본 int8_hnsw, dims+16, 그래프 4*m, 레플리카, off-heap → VEC-MEM-01/VEC-IDX-01"
tags: [hard, en]
max_turns: 12
timeout_seconds: 300
allowed_tools: [Read, Glob, Grep, Skill]
---

We're on Elasticsearch 8.15. One index holds 20 million documents, each with a 768-dimension float `dense_vector` field; the mapping does not set `index_options`. number_of_replicas is 1. Roughly how much memory across the data nodes do we need for approximate kNN search to stay fast, and should we give that memory to the JVM heap? Show the arithmetic.
