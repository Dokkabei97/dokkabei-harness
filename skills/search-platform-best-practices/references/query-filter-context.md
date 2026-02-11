---
title: Use filter Context Instead of query Context for Non-Scoring Clauses
impact: CRITICAL
impactDescription: 2-10x faster queries by skipping scoring and leveraging filter cache
tags: query, filter, context, scoring, cache, bool, performance
---

## Use filter Context Instead of query Context for Non-Scoring Clauses

Elasticsearch has two query contexts: `query` (calculates relevance score) and `filter` (yes/no match, no scoring). Using `query` context for clauses that don't need scoring wastes CPU on score calculation and misses the filter cache, which can cache frequently used filters in a bitset.

**Incorrect (scoring clauses for non-relevance filters):**

```json
// Every clause calculates a relevance score — unnecessary for status and date filters
GET /orders/_search
{
  "query": {
    "bool": {
      "must": [
        { "match": { "product_name": "노트북" } },
        { "term": { "status": "delivered" } },
        { "range": { "created_at": { "gte": "2024-01-01" } } }
      ]
    }
  }
}
// status and date range don't contribute to relevance — they're binary filters
// Yet ES calculates scores for them and cannot cache them efficiently
```

**Correct (filter context for non-scoring clauses):**

```json
GET /orders/_search
{
  "query": {
    "bool": {
      "must": [
        { "match": { "product_name": "노트북" } }
      ],
      "filter": [
        { "term": { "status": "delivered" } },
        { "range": { "created_at": { "gte": "2024-01-01" } } }
      ]
    }
  }
}
// "must" only contains the clause that needs relevance scoring
// "filter" contains exact-match/range clauses — no scoring, cached as bitset
```

Filter context benefits:
1. **No score calculation** — skips TF/IDF/BM25 computation
2. **Filter cache** — frequently used filters are cached as bitsets, making subsequent queries nearly instant
3. **Clause reordering** — ES can optimize execution order based on estimated cost

Common patterns where `filter` should be used:

```json
// Pure filtering — no relevance needed at all
GET /products/_search
{
  "query": {
    "bool": {
      "filter": [
        { "term": { "category": "electronics" } },
        { "range": { "price": { "gte": 10000, "lte": 50000 } } },
        { "term": { "in_stock": true } }
      ]
    }
  },
  "sort": [{ "price": "asc" }]
}
// All documents have _score: 0.0 — sorted by explicit criteria, not relevance

// constant_score wraps filter context with a fixed score
GET /products/_search
{
  "query": {
    "constant_score": {
      "filter": { "term": { "status": "active" } },
      "boost": 1.0
    }
  }
}
```

Rule of thumb: If a clause answers "is this relevant?" use `must`/`should`. If it answers "should this be included?" use `filter`/`must_not`.

Reference: [Query and filter context](https://www.elastic.co/guide/en/elasticsearch/reference/current/query-filter-context.html)
