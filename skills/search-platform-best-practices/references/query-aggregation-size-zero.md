---
title: Set size to 0 for Aggregation-Only Queries to Skip Hit Retrieval
impact: MEDIUM-HIGH
impactDescription: 2-5x faster aggregation queries by eliminating unnecessary hit fetching and scoring
tags: query, aggregation, size, performance, hits
---

## Set size to 0 for Aggregation-Only Queries to Skip Hit Retrieval

When running aggregation queries where you don't need the actual documents (dashboards, analytics, faceted counts), Elasticsearch still fetches the top 10 hits by default. Setting `size: 0` skips hit retrieval entirely, avoiding score calculation, source fetching, and sorting.

**Incorrect (aggregation query returns unnecessary hits):**

```json
GET /orders/_search
{
  "query": {
    "range": { "created_at": { "gte": "2024-01-01" } }
  },
  "aggs": {
    "orders_per_status": {
      "terms": { "field": "status", "size": 10 }
    },
    "revenue_per_month": {
      "date_histogram": {
        "field": "created_at",
        "calendar_interval": "month"
      },
      "aggs": {
        "total_revenue": { "sum": { "field": "amount" } }
      }
    }
  }
}
// Returns 10 hits (with _source, scoring) PLUS aggregations
// The hits are never used — wasted work
```

**Correct (size: 0 for aggregation-only):**

```json
GET /orders/_search
{
  "size": 0,
  "query": {
    "range": { "created_at": { "gte": "2024-01-01" } }
  },
  "aggs": {
    "orders_per_status": {
      "terms": { "field": "status", "size": 10 }
    },
    "revenue_per_month": {
      "date_histogram": {
        "field": "created_at",
        "calendar_interval": "month"
      },
      "aggs": {
        "total_revenue": { "sum": { "field": "amount" } }
      }
    }
  }
}
// "hits.hits" is an empty array — no documents fetched
// Only aggregation results are returned
// Significantly faster for large result sets
```

Additional optimization — combine with filter context:

```json
GET /orders/_search
{
  "size": 0,
  "query": {
    "bool": {
      "filter": [
        { "range": { "created_at": { "gte": "2024-01-01" } } },
        { "term": { "region": "kr" } }
      ]
    }
  },
  "aggs": {
    "orders_per_status": {
      "terms": { "field": "status", "size": 10 }
    }
  }
}
// filter context (no scoring) + size: 0 (no hits) = maximum aggregation performance
```

This pattern is essential for:
- Dashboard facets and filters
- Analytics and BI queries
- Cardinality estimation
- Statistical computations (avg, percentiles, min/max)

Reference: [Aggregations](https://www.elastic.co/guide/en/elasticsearch/reference/current/search-aggregations.html)
