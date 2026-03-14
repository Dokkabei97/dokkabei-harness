---
title: Use filter Instead of must for Non-Scoring Clauses
impact: CRITICAL
impactDescription: 2-10x query speedup with filter cache utilization
tags: query, bool, filter, must, scoring, cache
---

## Use filter Instead of must for Non-Scoring Clauses

Every clause in `must` triggers BM25 score calculation — an expensive operation that also prevents caching. Clauses in `filter` skip scoring entirely and leverage the filter cache (bitset), resulting in 2-10x faster queries. The decision is simple: if a clause doesn't need to influence relevance ranking, it belongs in `filter`.

**Incorrect (all clauses in must, including non-scoring ones):**

```json
// term and range don't need relevance scoring, but must forces BM25 calculation
// Every query re-computes scores → no caching, wasted CPU cycles
GET /products/_search
{
  "query": {
    "bool": {
      "must": [
        { "match": { "name": "wireless headphones" } },
        { "term": { "status": "active" } },
        { "range": { "price": { "gte": 50, "lte": 200 } } },
        { "term": { "category": "electronics" } }
      ]
    }
  }
}
```

**Correct (only scoring clauses in must, the rest in filter):**

```json
// match needs scoring → must (relevance ranking)
// term, range are binary include/exclude → filter (cached bitset, no scoring)
GET /products/_search
{
  "query": {
    "bool": {
      "must": [
        { "match": { "name": "wireless headphones" } }
      ],
      "filter": [
        { "term": { "status": "active" } },
        { "range": { "price": { "gte": 50, "lte": 200 } } },
        { "term": { "category": "electronics" } }
      ]
    }
  }
}
```

**Performance comparison:**

| Aspect | must | filter |
|--------|------|--------|
| Scoring | BM25 calculation per document | No scoring (constant 0) |
| Caching | Not cacheable | Filter cache (bitset) |
| Use case | Full-text relevance search | Exact match, range, exists |
| Performance | Baseline | 2-10x faster |
| CPU cost | High (TF/IDF computation) | Low (bit operations) |

**Decision criteria — "Does this clause affect ranking?"**

```
match, multi_match, match_phrase     → must  (needs relevance scoring)
term, terms, range, exists, bool     → filter (binary yes/no decision)
geo_distance, geo_bounding_box       → filter (binary containment check)
```

**No-scoring query (pure filtering):**

```json
// When you don't need relevance at all, put everything in filter
// Common for dashboards, exports, and count queries
GET /orders/_search
{
  "query": {
    "bool": {
      "filter": [
        { "term": { "status": "shipped" } },
        { "range": { "created_at": { "gte": "2024-01-01" } } },
        { "terms": { "region": ["us-east", "us-west"] } }
      ]
    }
  },
  "sort": [{ "created_at": "desc" }]
}
```

The filter cache stores results as compressed bitsets. Repeated queries with the same filter clauses hit the cache and skip index scanning entirely. On high-QPS systems (1000+ queries/sec), this caching alone accounts for the majority of the performance gain.

Reference: [Bool query](https://www.elastic.co/guide/en/elasticsearch/reference/current/query-dsl-bool-query.html)
