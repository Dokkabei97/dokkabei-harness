---
title: Clear, Action-Oriented Title (e.g., "Use keyword Type for Exact-Match Fields")
impact: MEDIUM
impactDescription: 5-20x query speedup for filtered queries
tags: mapping, query-optimization, performance
---

## [Rule Title]

[1-2 sentence explanation of the problem and why it matters. Focus on performance impact.]

**Incorrect (describe the problem):**

```json
// Comment explaining what makes this slow/problematic
PUT /my-index
{
  "mappings": {
    "properties": {
      "status": {
        "type": "text"
      }
    }
  }
}
```

```json
// Querying text field for exact match — invokes analysis, no term-level optimization
GET /my-index/_search
{
  "query": {
    "match": {
      "status": "active"
    }
  }
}
```

**Correct (describe the solution):**

```json
// Comment explaining why this is better
PUT /my-index
{
  "mappings": {
    "properties": {
      "status": {
        "type": "keyword"
      }
    }
  }
}
```

```json
// keyword field enables term-level query, skips analysis, uses doc values
GET /my-index/_search
{
  "query": {
    "term": {
      "status": "active"
    }
  }
}
```

[Optional: Additional context, edge cases, or trade-offs]

Reference: [Elasticsearch Docs](https://www.elastic.co/guide/en/elasticsearch/reference/current/index.html)
