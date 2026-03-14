---
title: Structure Bool Queries with filter-First Approach
impact: HIGH
impactDescription: 5-20x faster by reducing candidate set before expensive scoring
tags: query, bool, optimization, filter-first
---

## Structure Bool Queries with filter-First Approach

Elasticsearch evaluates `filter` clauses before `must` clauses. Cheap filter operations (cached bitsets) narrow the candidate set first, so expensive BM25 scoring runs on fewer documents. Placing the most selective clauses in `filter` maximizes this effect.

**Incorrect (all clauses in must, no selectivity ordering):**

```json
// BM25 scoring on every clause → expensive match runs against all 100M docs
// No filter cache utilization → repeated queries pay full cost
GET /products/_search
{
  "query": {
    "bool": {
      "must": [
        { "match": { "description": "noise cancelling bluetooth headphones" } },
        { "term": { "status": "active" } },
        { "range": { "price": { "gte": 100, "lte": 300 } } },
        { "term": { "brand": "Sony" } }
      ]
    }
  }
}
```

**Correct (filter-first, selective filters narrow candidate set before scoring):**

```json
// Execution order: filter → must → should
// 1. filter: term brand="Sony" → 2M docs (from 100M)
// 2. filter: range price → 500K docs
// 3. filter: term status → 400K docs
// 4. must: match description → BM25 only on 400K (not 100M)
GET /products/_search
{
  "query": {
    "bool": {
      "must": [
        { "match": { "description": "noise cancelling bluetooth headphones" } }
      ],
      "filter": [
        { "term": { "brand": "Sony" } },
        { "range": { "price": { "gte": 100, "lte": 300 } } },
        { "term": { "status": "active" } }
      ],
      "should": [
        { "term": { "featured": { "value": true, "boost": 2.0 } } }
      ]
    }
  }
}
```

**Bool clause execution order:**

| Order | Clause | Purpose | Caching |
|-------|--------|---------|---------|
| 1st | `filter` | Narrow candidates (no scoring) | Cached bitset |
| 2nd | `must_not` | Exclude documents (no scoring) | Cached bitset |
| 3rd | `must` | Score remaining docs (BM25) | Not cached |
| 4th | `should` | Boost matching docs (optional scoring) | Not cached |

**Selectivity principle:** Put the most restrictive filter first. A filter that reduces 100M docs to 1M is more valuable early than one that reduces 100M to 50M.

```json
// Complex query with proper structure
GET /orders/_search
{
  "query": {
    "bool": {
      "must": [
        { "multi_match": {
            "query": "laptop charger",
            "fields": ["name^3", "description"]
          }
        }
      ],
      "filter": [
        { "term": { "status": "active" } },
        { "range": { "created_at": { "gte": "now-30d" } } },
        { "terms": { "warehouse": ["us-east-1", "us-west-2"] } }
      ],
      "must_not": [
        { "term": { "is_deleted": true } }
      ],
      "should": [
        { "term": { "is_promoted": { "value": true, "boost": 1.5 } } }
      ],
      "minimum_should_match": 0
    }
  }
}
```

Reference: [Bool query](https://www.elastic.co/guide/en/elasticsearch/reference/current/query-dsl-bool-query.html)
