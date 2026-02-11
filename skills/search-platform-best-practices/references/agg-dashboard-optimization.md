---
title: Use global and filter Aggregations for Dashboard Multi-Panel Optimization
impact: MEDIUM
impactDescription: Single query serves all dashboard panels instead of N separate queries
tags: aggregation, global, filter, dashboard, optimization, multi-panel
---

## Use global and filter Aggregations for Dashboard Multi-Panel Optimization

Dashboards often have multiple panels (total count, filtered charts, unfiltered summaries) that share the same base query. Instead of sending separate requests per panel, use `global` and `filter` aggregations in a single request.

**Incorrect (separate query per dashboard panel):**

```json
// Panel 1: Total orders for selected region
GET /orders/_search
{ "size": 0, "query": { "term": { "region": "kr" } },
  "aggs": { "total": { "value_count": { "field": "_id" } } } }

// Panel 2: Orders by status (same filter)
GET /orders/_search
{ "size": 0, "query": { "term": { "region": "kr" } },
  "aggs": { "by_status": { "terms": { "field": "status" } } } }

// Panel 3: Global average order value (no filter)
GET /orders/_search
{ "size": 0, "aggs": { "global_avg": { "avg": { "field": "amount" } } } }

// 3 separate requests = 3x cluster load
```

**Correct (single request with global and filter aggregations):**

```json
GET /orders/_search
{
  "size": 0,
  "query": {
    "term": { "region": "kr" }
  },
  "aggs": {
    "filtered_total": {
      "value_count": { "field": "_id" }
    },
    "filtered_by_status": {
      "terms": { "field": "status", "size": 10 }
    },
    "global_stats": {
      "global": {},
      "aggs": {
        "global_avg_amount": {
          "avg": { "field": "amount" }
        },
        "global_total": {
          "value_count": { "field": "_id" }
        }
      }
    }
  }
}
// Single request serves all 3 panels
// "global" agg ignores the top-level query filter
// Other aggs respect the region=kr filter
```

Using `filters` aggregation for multi-category comparison:

```json
GET /orders/_search
{
  "size": 0,
  "aggs": {
    "regions": {
      "filters": {
        "filters": {
          "korea": { "term": { "region": "kr" } },
          "japan": { "term": { "region": "jp" } },
          "usa": { "term": { "region": "us" } }
        }
      },
      "aggs": {
        "avg_amount": { "avg": { "field": "amount" } },
        "order_count": { "value_count": { "field": "_id" } }
      }
    }
  }
}
// Single query computes stats for 3 regions at once
```

Reference: [Global aggregation](https://www.elastic.co/guide/en/elasticsearch/reference/current/search-aggregations-bucket-global-aggregation.html), [Filters aggregation](https://www.elastic.co/guide/en/elasticsearch/reference/current/search-aggregations-bucket-filters-aggregation.html)
