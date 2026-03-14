---
title: "Configure Slow Logs for Production Diagnosis"
impact: LOW-MEDIUM
impactDescription: "Identifies slow queries and indexing bottlenecks without impacting cluster performance"
tags: monitor, slow-log, diagnosis, query-performance, indexing
---

## Configure Slow Logs for Production Diagnosis

Without slow logs, diagnosing production performance issues requires invasive tools like the hot threads API or attaching profilers — both risky on live clusters. Slow logs passively record queries and indexing operations that exceed configurable thresholds, providing a continuous stream of performance data with negligible overhead. They capture the actual query body, execution time, and shard-level detail needed to identify and fix bottlenecks.

**Incorrect (no slow log configuration — blind to production issues):**

```json
// Default: all slow log thresholds are -1 (disabled)
// No visibility into which queries are slow
// Problems only discovered when users report latency or dashboards timeout
// By then, the slow query may have stopped, leaving no trace

GET /orders/_settings?flat_settings=true&filter_path=**.slowlog
// Response: {} (empty — nothing configured)
```

```json
// Also incorrect: overly aggressive thresholds in production
PUT /orders/_settings
{
  "index.search.slowlog.threshold.query.trace": "0ms",
  "index.search.slowlog.threshold.fetch.trace": "0ms"
}
// Logs EVERY query at trace level -> log volume explosion
// 10,000 QPS x detailed query body = disk fill in hours
// Log I/O itself becomes a performance bottleneck
```

**Correct (tiered slow log thresholds for search):**

```json
// Configure per-index search slow log with graduated thresholds
PUT /orders/_settings
{
  "index.search.slowlog.threshold.query.warn": "10s",
  "index.search.slowlog.threshold.query.info": "5s",
  "index.search.slowlog.threshold.query.debug": "2s",
  "index.search.slowlog.threshold.query.trace": "500ms",
  "index.search.slowlog.threshold.fetch.warn": "5s",
  "index.search.slowlog.threshold.fetch.info": "2s",
  "index.search.slowlog.threshold.fetch.debug": "1s",
  "index.search.slowlog.threshold.fetch.trace": "500ms",
  "index.search.slowlog.level": "trace",
  "index.search.slowlog.include.user": true
}
```

**Correct (indexing slow log for write bottlenecks):**

```json
// Configure per-index indexing slow log
PUT /orders/_settings
{
  "index.indexing.slowlog.threshold.index.warn": "10s",
  "index.indexing.slowlog.threshold.index.info": "5s",
  "index.indexing.slowlog.threshold.index.debug": "2s",
  "index.indexing.slowlog.threshold.index.trace": "1s",
  "index.indexing.slowlog.level": "trace",
  "index.indexing.slowlog.source": "1000"
}
// index.indexing.slowlog.source: max characters of _source to log
// "1000" logs first 1000 chars (enough to identify doc type)
// "false" disables source logging (for PII-sensitive indices)
// "true" logs full source (careful with large documents)
```

**Apply to all indices via index template:**

```json
// Composable template applies slow log to all new indices matching pattern
PUT _index_template/slowlog-defaults
{
  "index_patterns": ["*"],
  "priority": 0,
  "template": {
    "settings": {
      "index.search.slowlog.threshold.query.warn": "10s",
      "index.search.slowlog.threshold.query.info": "5s",
      "index.search.slowlog.threshold.query.debug": "2s",
      "index.search.slowlog.threshold.query.trace": "500ms",
      "index.search.slowlog.threshold.fetch.warn": "5s",
      "index.search.slowlog.threshold.fetch.info": "2s",
      "index.search.slowlog.threshold.fetch.debug": "1s",
      "index.search.slowlog.threshold.fetch.trace": "500ms",
      "index.indexing.slowlog.threshold.index.warn": "10s",
      "index.indexing.slowlog.threshold.index.info": "5s",
      "index.indexing.slowlog.threshold.index.debug": "2s",
      "index.indexing.slowlog.threshold.index.trace": "1s"
    }
  }
}
```

**Log output location and format:**

```
# Slow log files are separate from main ES logs
# Search slow log: <cluster_name>_index_search_slowlog.json
# Indexing slow log: <cluster_name>_index_indexing_slowlog.json

# Example slow log entry (JSON format):
# {
#   "type": "index_search_slowlog",
#   "timestamp": "2025-06-15T10:30:00.000Z",
#   "level": "WARN",
#   "node.name": "data-hot-1",
#   "index": "orders",
#   "shard": 3,
#   "took": "12.4s",
#   "took_millis": 12400,
#   "total_hits": "1543892",
#   "search_type": "QUERY_THEN_FETCH",
#   "total_shards": 15,
#   "source": "{\"query\":{\"bool\":{\"must\":[{\"wildcard\":{\"customer_name\":{\"value\":\"*john*\"}}}]}}}"
# }
```

**Recommended threshold guidelines:**

| Environment | Query Warn | Query Info | Query Debug | Query Trace |
|-------------|-----------|-----------|------------|------------|
| Low-latency search (< 100ms SLA) | 2s | 1s | 500ms | 200ms |
| Standard search (< 1s SLA) | 10s | 5s | 2s | 500ms |
| Analytics/reporting (< 30s SLA) | 60s | 30s | 10s | 5s |
| Batch/export (no SLA) | 300s | 60s | 30s | 10s |

**Key rules:**

- Set thresholds at WARN and INFO levels in production — these log at manageable volumes while catching real problems.
- Enable TRACE and DEBUG thresholds only if your log infrastructure can handle the volume (centralized logging recommended).
- Use `index.search.slowlog.include.user: true` (ES 8.x) to identify which application or user generates slow queries.
- Set `index.indexing.slowlog.source: "false"` on indices containing PII or sensitive data.
- Slow log settings are dynamic — change them without restarting the cluster or reindexing.
- Pipe slow logs to centralized logging (ELK, Datadog, Splunk) for alerting and trend analysis.
- Combine slow log findings with the Profile API (`"profile": true`) to diagnose root causes of slow queries.

Reference:
[Slow Log](https://www.elastic.co/guide/en/elasticsearch/reference/current/index-modules-slowlog.html)
