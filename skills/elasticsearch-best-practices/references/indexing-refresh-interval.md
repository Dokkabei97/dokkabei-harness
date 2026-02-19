---
title: Tune refresh_interval Based on Freshness Requirements
impact: MEDIUM-HIGH
impactDescription: 20-50% indexing throughput improvement with relaxed refresh
tags: indexing, refresh-interval, near-real-time, throughput
---

## Tune refresh_interval Based on Freshness Requirements

Every refresh creates a new Lucene segment, making recently indexed documents searchable. The default 1-second interval means Elasticsearch creates 3600 segments per hour per shard, which must later be merged — consuming CPU, I/O, and memory. Not every use case needs sub-second freshness. Log analytics tolerate 30-60 seconds of delay, yet most deployments leave the default untouched, wasting 20-50% of potential indexing throughput on unnecessary segment creation.

**Incorrect (default 1s refresh for log/analytics indices):**

```json
// Default: refresh_interval=1s applied to ALL indices
// Log indices receiving 50K docs/sec → 3600 segment opens per hour per shard
// Each segment consumes heap for in-memory structures (file handles, caches)
// 20 shards × 3600 segments/hour = 72,000 segments/hour to merge

PUT /application-logs-2024.01
{
  "settings": {
    "number_of_shards": 10,
    "number_of_replicas": 1
  }
}
// refresh_interval defaults to 1s → segment churn for data nobody searches in real-time
```

**Correct (refresh interval tuned per use case):**

```json
// Real-time search (e-commerce product catalog, inventory)
// Users expect instant updates when items are added/modified
PUT /products/_settings
{
  "index": {
    "refresh_interval": "1s"
  }
}

// Near-real-time logs (application logs, access logs)
// 30s delay is acceptable — dashboards auto-refresh every 30-60s anyway
PUT /application-logs-2024.01/_settings
{
  "index": {
    "refresh_interval": "30s"
  }
}

// Analytics/metrics (daily aggregations, weekly reports)
// Data is queried in batch, not real-time — 60s refresh is sufficient
PUT /order-analytics-2024.01/_settings
{
  "index": {
    "refresh_interval": "60s"
  }
}

// Batch-only indices (nightly ETL, historical imports)
// No one searches during ingestion → disable entirely, refresh manually
PUT /historical-orders/_settings
{
  "index": {
    "refresh_interval": "-1"
  }
}

// Manual refresh after batch job completes
POST /historical-orders/_refresh
```

**Setting refresh_interval in index templates for consistent policy:**

```json
// Apply 30s refresh to all log indices automatically via index template
PUT /_index_template/logs-template
{
  "index_patterns": ["*-logs-*"],
  "priority": 100,
  "template": {
    "settings": {
      "index": {
        "refresh_interval": "30s",
        "number_of_shards": 5,
        "number_of_replicas": 1
      }
    }
  }
}
```

**Recommended refresh intervals by use case:**

| Use Case | Refresh Interval | Rationale |
|----------|-----------------|-----------|
| Product search / inventory | `1s` (default) | Users expect instant visibility |
| Application logs | `30s` | Dashboards refresh every 30-60s |
| Metrics / time-series | `30s`-`60s` | Aggregated, not real-time |
| Analytics / reporting | `60s` | Batch queries, not live search |
| Batch import / ETL | `-1` (disabled) | Manual refresh after load |

On a 10-shard index ingesting 20K docs/sec, changing from `1s` to `30s` reduces segment creation from 36,000/hour to 1,200/hour — a 30x reduction in segment merge pressure. This translates directly to lower CPU usage on data nodes and higher sustainable indexing throughput.

Reference: [Near real-time search](https://www.elastic.co/guide/en/elasticsearch/reference/current/near-real-time.html)
