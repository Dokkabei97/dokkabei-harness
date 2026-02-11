---
title: Use Composite Aggregation for High-Cardinality Paginated Aggregations
impact: MEDIUM-HIGH
impactDescription: Handles millions of unique values without OOM, supports pagination through all buckets
tags: aggregation, composite, high-cardinality, pagination, memory
---

## Use Composite Aggregation for High-Cardinality Paginated Aggregations

Standard `terms` aggregation loads all bucket data into memory, causing OOM with high-cardinality fields. `composite` aggregation paginates through buckets using `after_key`, processing them in manageable chunks.

**Incorrect (terms aggregation on high-cardinality field — OOM risk):**

```json
GET /logs/_search
{
  "size": 0,
  "aggs": {
    "unique_users": {
      "terms": {
        "field": "user_id",
        "size": 1000000
      }
    }
  }
}
// 1M buckets loaded into memory on coordinating node
// High risk of circuit breaker tripping or OOM
```

**Correct (composite aggregation with pagination):**

```json
// First page
GET /logs/_search
{
  "size": 0,
  "aggs": {
    "user_activity": {
      "composite": {
        "size": 1000,
        "sources": [
          { "user": { "terms": { "field": "user_id" } } },
          { "date": { "date_histogram": { "field": "timestamp", "calendar_interval": "day" } } }
        ]
      },
      "aggs": {
        "total_requests": { "value_count": { "field": "_id" } }
      }
    }
  }
}

// Response includes after_key for next page
// { "after_key": { "user": "user_5000", "date": 1704067200000 } }

// Next page — pass the after_key
GET /logs/_search
{
  "size": 0,
  "aggs": {
    "user_activity": {
      "composite": {
        "size": 1000,
        "after": { "user": "user_5000", "date": 1704067200000 },
        "sources": [
          { "user": { "terms": { "field": "user_id" } } },
          { "date": { "date_histogram": { "field": "timestamp", "calendar_interval": "day" } } }
        ]
      },
      "aggs": {
        "total_requests": { "value_count": { "field": "_id" } }
      }
    }
  }
}
// Repeat until response returns no after_key (all buckets processed)
```

Composite sources support multiple types:

| Source Type | Use Case |
|------------|----------|
| `terms` | Group by keyword/numeric field |
| `date_histogram` | Group by time interval |
| `histogram` | Group by numeric range |

Reference: [Composite aggregation](https://www.elastic.co/guide/en/elasticsearch/reference/current/search-aggregations-bucket-composite-aggregation.html)
