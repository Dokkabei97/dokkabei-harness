---
title: Use Transforms for Pre-Computed Aggregations and Entity-Centric Views
impact: LOW
impactDescription: Pre-aggregates data for instant dashboard queries, eliminates runtime aggregation overhead
tags: advanced, transform, pre-aggregation, pivot, entity-centric, materialized-view
---

## Use Transforms for Pre-Computed Aggregations and Entity-Centric Views

Transforms pivot time-series or event data into pre-computed entity-centric indices. Instead of aggregating millions of raw events at query time, query a pre-aggregated index with one document per entity.

**Correct (transform for customer summary):**

```json
// Create a transform that aggregates orders into customer summaries
PUT /_transform/customer_summary
{
  "source": {
    "index": ["orders-*"]
  },
  "dest": {
    "index": "customer-summary"
  },
  "pivot": {
    "group_by": {
      "customer_id": { "terms": { "field": "customer_id" } }
    },
    "aggregations": {
      "total_orders": { "value_count": { "field": "order_id" } },
      "total_revenue": { "sum": { "field": "amount" } },
      "avg_order_value": { "avg": { "field": "amount" } },
      "last_order_date": { "max": { "field": "created_at" } },
      "top_categories": {
        "terms": { "field": "category", "size": 5 }
      }
    }
  },
  "frequency": "5m",
  "sync": {
    "time": {
      "field": "created_at",
      "delay": "60s"
    }
  }
}

// Start the transform (runs continuously)
POST /_transform/customer_summary/_start

// Now dashboard queries are instant — one doc per customer
GET /customer-summary/_search
{
  "query": {
    "range": { "total_revenue": { "gte": 1000000 } }
  },
  "sort": [{ "total_revenue": "desc" }]
}
// Instead of aggregating 10M order documents, query 100K pre-computed customer docs
```

Use cases:
- Customer 360 views from event data
- Real-time dashboards from high-volume logs
- Pre-computed metrics for API responses
- Materialized views equivalent

Reference: [Transforms](https://www.elastic.co/guide/en/elasticsearch/reference/current/transforms.html)
