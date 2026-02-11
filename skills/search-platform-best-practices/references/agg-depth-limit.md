---
title: Limit Sub-Aggregation Depth to 3 Levels to Prevent Memory Explosion
impact: MEDIUM-HIGH
impactDescription: Deep nesting causes exponential bucket growth, leading to OOM and slow responses
tags: aggregation, depth, nesting, memory, performance, circuit-breaker
---

## Limit Sub-Aggregation Depth to 3 Levels to Prevent Memory Explosion

Each level of sub-aggregation multiplies the number of buckets. A 3-level aggregation with 100 buckets each = 100 x 100 x 100 = 1,000,000 buckets. Deep nesting causes exponential memory growth and slow responses.

**Incorrect (4+ levels of nesting — bucket explosion):**

```json
GET /orders/_search
{
  "size": 0,
  "aggs": {
    "by_region": {          // 50 buckets
      "terms": { "field": "region", "size": 50 },
      "aggs": {
        "by_category": {     // x 100 = 5,000 buckets
          "terms": { "field": "category", "size": 100 },
          "aggs": {
            "by_brand": {    // x 200 = 1,000,000 buckets
              "terms": { "field": "brand", "size": 200 },
              "aggs": {
                "by_month": {  // x 12 = 12,000,000 buckets!
                  "date_histogram": { "field": "created_at", "calendar_interval": "month" },
                  "aggs": {
                    "revenue": { "sum": { "field": "amount" } }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
// 12 MILLION buckets — circuit breaker will trip, or response is 100MB+
```

**Correct (flatten or limit depth):**

```json
// Option 1: Use composite aggregation with multiple sources (flat, paginated)
GET /orders/_search
{
  "size": 0,
  "aggs": {
    "multi_dim": {
      "composite": {
        "size": 1000,
        "sources": [
          { "region": { "terms": { "field": "region" } } },
          { "category": { "terms": { "field": "category" } } },
          { "brand": { "terms": { "field": "brand" } } },
          { "month": { "date_histogram": { "field": "created_at", "calendar_interval": "month" } } }
        ]
      },
      "aggs": {
        "revenue": { "sum": { "field": "amount" } }
      }
    }
  }
}
// Flat structure, paginated — no bucket explosion

// Option 2: Limit nesting to 2-3 levels with reduced bucket counts
GET /orders/_search
{
  "size": 0,
  "aggs": {
    "by_region": {
      "terms": { "field": "region", "size": 10 },
      "aggs": {
        "by_category": {
          "terms": { "field": "category", "size": 10 },
          "aggs": {
            "revenue": { "sum": { "field": "amount" } }
          }
        }
      }
    }
  }
}
// 10 x 10 = 100 buckets — manageable
```

Bucket count estimation: multiply `size` at each nesting level. Keep the product under 10,000 for reliable performance.

Reference: [Aggregations](https://www.elastic.co/guide/en/elasticsearch/reference/current/search-aggregations.html)
