---
title: Use calendar_interval vs fixed_interval Correctly in Date Histograms
impact: MEDIUM
impactDescription: Prevents incorrect time bucketing that produces wrong analytics
tags: aggregation, date-histogram, calendar-interval, fixed-interval, time-series
---

## Use calendar_interval vs fixed_interval Correctly in Date Histograms

`calendar_interval` handles variable-length periods (months have 28-31 days). `fixed_interval` uses fixed durations. Using the wrong one produces incorrect time buckets.

**Incorrect (fixed_interval for months — wrong bucket boundaries):**

```json
GET /orders/_search
{
  "size": 0,
  "aggs": {
    "monthly_revenue": {
      "date_histogram": {
        "field": "created_at",
        "fixed_interval": "30d"
      }
    }
  }
}
// 30d ≠ 1 month: February is 28/29 days, some months 31
// Buckets drift over time — January 1 to January 31, then January 31 to March 1
```

**Correct (calendar_interval for calendar-based periods):**

```json
// Monthly buckets aligned to calendar months
GET /orders/_search
{
  "size": 0,
  "aggs": {
    "monthly_revenue": {
      "date_histogram": {
        "field": "created_at",
        "calendar_interval": "month"
      },
      "aggs": {
        "revenue": { "sum": { "field": "amount" } }
      }
    }
  }
}

// For fixed durations (1h, 5m, 30s), use fixed_interval
GET /metrics/_search
{
  "size": 0,
  "aggs": {
    "requests_per_5min": {
      "date_histogram": {
        "field": "timestamp",
        "fixed_interval": "5m"
      }
    }
  }
}
```

Quick reference:

| Period | Use | Type |
|--------|-----|------|
| minute, hour, day, week, month, quarter, year | `calendar_interval` | Variable length |
| 30s, 5m, 1h, 24h, 7d | `fixed_interval` | Fixed duration |

Reference: [Date histogram aggregation](https://www.elastic.co/guide/en/elasticsearch/reference/current/search-aggregations-bucket-datehistogram-aggregation.html)
