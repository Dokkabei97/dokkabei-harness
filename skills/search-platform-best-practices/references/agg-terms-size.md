---
title: Set Explicit size on Terms Aggregations — Default 10 Misses Data
impact: MEDIUM-HIGH
impactDescription: Default size=10 silently drops buckets, producing incomplete analytics
tags: aggregation, terms, size, accuracy, cardinality
---

## Set Explicit size on Terms Aggregations — Default 10 Misses Data

The `terms` aggregation defaults to returning only 10 buckets. If your field has more than 10 unique values, the remaining are silently dropped. This produces misleading dashboards and incomplete analytics.

**Incorrect (default size — missing buckets):**

```json
GET /orders/_search
{
  "size": 0,
  "aggs": {
    "orders_by_region": {
      "terms": { "field": "region" }
    }
  }
}
// Only returns top 10 regions — if you have 50 regions, 40 are invisible
// "sum_other_doc_count" shows how many documents are in missing buckets
// Dashboards show incomplete data without warning
```

**Correct (explicit size based on expected cardinality):**

```json
GET /orders/_search
{
  "size": 0,
  "aggs": {
    "orders_by_region": {
      "terms": {
        "field": "region",
        "size": 50
      }
    }
  }
}
// Returns all 50 regions

// For exact counts with shard_size tuning
GET /orders/_search
{
  "size": 0,
  "aggs": {
    "orders_by_region": {
      "terms": {
        "field": "region",
        "size": 50,
        "shard_size": 100
      }
    }
  }
}
// shard_size > size improves accuracy by collecting more candidates per shard
// Default shard_size = size * 1.5 + 10
```

For high-cardinality fields (10,000+ unique values), use `composite` aggregation instead — see `agg-composite.md`.

Reference: [Terms aggregation](https://www.elastic.co/guide/en/elasticsearch/reference/current/search-aggregations-bucket-terms-aggregation.html)
