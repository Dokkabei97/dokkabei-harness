---
title: Configure Slow Logs to Identify Problematic Queries and Indexing Operations
impact: LOW-MEDIUM
impactDescription: Captures slow queries and indexing operations for targeted optimization
tags: monitoring, slow-log, query, indexing, performance, debugging
---

## Configure Slow Logs to Identify Problematic Queries and Indexing Operations

Slow logs capture queries and indexing operations that exceed configurable time thresholds. This is the primary tool for finding optimization targets in production.

**Correct (configure slow logs per index):**

```json
PUT /products/_settings
{
  "index.search.slowlog.threshold.query.warn": "10s",
  "index.search.slowlog.threshold.query.info": "5s",
  "index.search.slowlog.threshold.query.debug": "2s",
  "index.search.slowlog.threshold.query.trace": "500ms",

  "index.search.slowlog.threshold.fetch.warn": "1s",
  "index.search.slowlog.threshold.fetch.info": "800ms",

  "index.indexing.slowlog.threshold.index.warn": "10s",
  "index.indexing.slowlog.threshold.index.info": "5s",

  "index.search.slowlog.level": "info"
}

// Set via index template for all new indices
PUT /_index_template/slowlog-defaults
{
  "index_patterns": ["*"],
  "priority": 1,
  "template": {
    "settings": {
      "index.search.slowlog.threshold.query.warn": "10s",
      "index.search.slowlog.threshold.query.info": "5s",
      "index.indexing.slowlog.threshold.index.warn": "10s"
    }
  }
}
```

Slow log output (in `<cluster>_index_search_slowlog.json`):

```json
{
  "@timestamp": "2024-01-15T10:30:00Z",
  "level": "WARN",
  "message": "[products][0] took[12.5s], took_millis[12500], total_hits[1500000], source[{\"query\":{\"wildcard\":{\"name\":\"*노트북*\"}}}]"
}
// Shows: which index, which shard, how long, hit count, and the full query
// This immediately identifies the leading wildcard as the problem
```

Start with generous thresholds and tighten as you optimize:
- **Warn**: 10s (clear problems)
- **Info**: 5s (optimization targets)
- **Debug**: 2s (fine-tuning)

Reference: [Slow Log](https://www.elastic.co/guide/en/elasticsearch/reference/current/index-modules-slowlog.html)
