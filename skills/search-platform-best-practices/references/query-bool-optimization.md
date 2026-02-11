---
title: Place filter and must_not Before must and should in Bool Queries
impact: HIGH
impactDescription: 2-5x faster bool queries by reducing candidate set before scoring
tags: query, bool, filter, must_not, optimization, clause-order
---

## Place filter and must_not Before must and should in Bool Queries

In a bool query, Elasticsearch evaluates clauses in an optimized order. `filter` and `must_not` narrow the candidate set without scoring, so expensive `must` and `should` scoring clauses run on fewer documents. Structuring queries with cheap filters first maximizes this optimization.

**Incorrect (scoring clauses dominate, filtering is an afterthought):**

```json
GET /products/_search
{
  "query": {
    "bool": {
      "must": [
        { "match": { "description": "가벼운 노트북 고성능" } },
        { "match": { "title": "울트라북" } },
        { "term": { "brand": "samsung" } },
        { "term": { "in_stock": true } },
        { "range": { "price": { "lte": 2000000 } } }
      ]
    }
  }
}
// brand, in_stock, and price are exact filters but placed in "must" — they calculate scores unnecessarily
// Full-text match runs on all documents instead of a filtered subset
```

**Correct (filter first, then score):**

```json
GET /products/_search
{
  "query": {
    "bool": {
      "filter": [
        { "term": { "brand": "samsung" } },
        { "term": { "in_stock": true } },
        { "range": { "price": { "lte": 2000000 } } }
      ],
      "must": [
        { "match": { "description": "가벼운 노트북 고성능" } }
      ],
      "should": [
        { "match": { "title": { "query": "울트라북", "boost": 2.0 } } }
      ]
    }
  }
}
// 1. filter narrows candidates (cached, no scoring)
// 2. must scores only the filtered subset
// 3. should boosts matching docs but doesn't exclude non-matches
```

Bool clause execution model:

| Clause | Scoring | Cacheable | Purpose |
|--------|---------|-----------|---------|
| `filter` | No | Yes | Hard requirement, no relevance |
| `must_not` | No | Yes | Exclusion |
| `must` | Yes | No | Hard requirement + relevance |
| `should` | Yes | No | Soft boost (optional unless no must/filter) |

Optimization tips:
- Move term/range/exists from `must` to `filter` when score is irrelevant
- Use `must_not` for exclusions instead of negating with scripts
- When all clauses are filters, the query returns `_score: 0.0` (use explicit `sort`)
- `minimum_should_match` controls how many `should` clauses must match

Reference: [Boolean query](https://www.elastic.co/guide/en/elasticsearch/reference/current/query-dsl-bool-query.html)
