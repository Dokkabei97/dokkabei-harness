---
title: Use Profile API to Diagnose Slow Queries
impact: MEDIUM
impactDescription: Pinpoints exact query component causing latency with per-shard breakdown
tags: query, profile, diagnosis, slow-query
---

## Use Profile API to Diagnose Slow Queries

When a query is slow, guessing the cause wastes time. The Profile API provides per-shard, per-query-component timing breakdown in nanoseconds, showing exactly which clause is the bottleneck.

**Incorrect (guessing query bottleneck without profiling data):**

```json
// "This query is slow, let me rewrite it" → might optimize the wrong part
// Without profiling, you can't distinguish between:
// - Slow match clause vs slow range filter
// - Single slow shard vs uniform slowness
// - Scoring overhead vs collection overhead
GET /products/_search
{
  "query": {
    "bool": {
      "must": [
        { "match": { "description": "noise cancelling wireless" } }
      ],
      "filter": [
        { "range": { "price": { "gte": 50, "lte": 500 } } },
        { "term": { "status": "active" } },
        { "nested": {
            "path": "reviews",
            "query": { "range": { "reviews.rating": { "gte": 4 } } }
          }
        }
      ]
    }
  }
}
```

**Correct (add "profile": true to identify the bottleneck):**

```json
GET /products/_search
{
  "profile": true,
  "query": {
    "bool": {
      "must": [
        { "match": { "description": "noise cancelling wireless" } }
      ],
      "filter": [
        { "range": { "price": { "gte": 50, "lte": 500 } } },
        { "term": { "status": "active" } },
        { "nested": {
            "path": "reviews",
            "query": { "range": { "reviews.rating": { "gte": 4 } } }
          }
        }
      ]
    }
  }
}
```

**Reading the profile output:**

```json
// Key fields in profile response (times in nanoseconds)
{
  "profile": {
    "shards": [{
      "id": "[node-1][products][0]",
      "searches": [{
        "query": [{
          "type": "BooleanQuery",
          "description": "+description:noise +description:cancelling ...",
          "time_in_nanos": 24851200,
          "breakdown": {
            "score": 8412000,
            "build_scorer": 12340000,
            "next_doc": 3200000,
            "advance": 0,
            "match": 899200,
            "create_weight": 0
          },
          "children": [
            {
              "type": "TermQuery",
              "description": "description:noise",
              "time_in_nanos": 1230000
            },
            {
              "type": "ToParentBlockJoinQuery",
              "description": "nested reviews.rating:[4 TO *]",
              "time_in_nanos": 18500000
            }
          ]
        }]
      }]
    }]
  }
}
// → nested query takes 18.5ms out of 24.8ms total (75% of time)
// → Optimize the nested clause first, not the match clause
```

**What to look for in profile output:**

| Field | Meaning | Action if high |
|-------|---------|---------------|
| `build_scorer` | Index structure traversal | Check field mapping, consider filter cache |
| `score` | BM25 computation | Move to filter if scoring not needed |
| `next_doc` | Document iteration | High cardinality field, consider more selective filter |
| `match` | Pattern matching | Simplify regex/wildcard patterns |
| `ToParentBlockJoinQuery` | Nested query overhead | Consider denormalization to object type |

Profile API adds overhead, so use it only for diagnosis — never in production queries. For ongoing slow query monitoring, use slow logs (see `monitor-slow-log.md`).

Reference: [Profile API](https://www.elastic.co/guide/en/elasticsearch/reference/current/search-profile.html)
