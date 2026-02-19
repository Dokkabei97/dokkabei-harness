---
title: Clear, Action-Oriented Title (e.g., "Use filter Instead of must for Non-Scoring Clauses")
impact: MEDIUM
impactDescription: 2-10x query speedup with filter cache utilization
tags: query, performance, optimization
---

## [Rule Title]

[1-2 sentence explanation of the problem and why it matters. Focus on performance impact.]

**Incorrect (describe the problem):**

```json
// Comment explaining what makes this slow/problematic
{
  "query": {
    "bool": {
      "must": [
        { "term": { "status": "active" } }
      ]
    }
  }
}
```

**Correct (describe the solution):**

```json
// Comment explaining why this is better
{
  "query": {
    "bool": {
      "filter": [
        { "term": { "status": "active" } }
      ]
    }
  }
}
```

[Optional: Additional context, edge cases, or trade-offs]

Reference: [Elasticsearch Docs](https://www.elastic.co/guide/en/elasticsearch/reference/current/)
