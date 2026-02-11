---
title: Configure Watcher/Alerting Rules for Proactive Issue Detection
impact: LOW
impactDescription: Automated alerts for cluster issues, anomalous query patterns, and business thresholds
tags: advanced, alerting, watcher, rules, notification, proactive
---

## Configure Watcher/Alerting Rules for Proactive Issue Detection

Watcher (Elasticsearch) and Alerting (OpenSearch) run queries on schedule and trigger notifications when conditions are met. This enables proactive issue detection instead of reactive firefighting.

**Correct (Watcher alert for error spike):**

```json
PUT /_watcher/watch/error_spike
{
  "trigger": {
    "schedule": { "interval": "5m" }
  },
  "input": {
    "search": {
      "request": {
        "indices": ["logs-*"],
        "body": {
          "size": 0,
          "query": {
            "bool": {
              "filter": [
                { "term": { "level": "ERROR" } },
                { "range": { "@timestamp": { "gte": "now-5m" } } }
              ]
            }
          },
          "aggs": {
            "error_count": { "value_count": { "field": "_id" } }
          }
        }
      }
    }
  },
  "condition": {
    "compare": {
      "ctx.payload.aggregations.error_count.value": { "gt": 100 }
    }
  },
  "actions": {
    "notify_slack": {
      "webhook": {
        "scheme": "https",
        "host": "hooks.slack.com",
        "port": 443,
        "method": "post",
        "path": "/services/T00/B00/XXXX",
        "body": "{\"text\": \"Error spike detected: {{ctx.payload.aggregations.error_count.value}} errors in last 5 minutes\"}"
      }
    }
  }
}

// Cluster health alert
PUT /_watcher/watch/cluster_health
{
  "trigger": { "schedule": { "interval": "1m" } },
  "input": {
    "http": {
      "request": {
        "host": "localhost",
        "port": 9200,
        "path": "/_cluster/health",
        "scheme": "https"
      }
    }
  },
  "condition": {
    "compare": { "ctx.payload.status": { "not_eq": "green" } }
  },
  "actions": {
    "notify": {
      "logging": {
        "text": "Cluster health is {{ctx.payload.status}}!"
      }
    }
  }
}
```

Common alerting patterns:
- Error rate spike (above N errors per time window)
- Cluster health degradation (yellow/red)
- Disk usage threshold (>80%)
- Search latency anomaly (p99 > threshold)
- Indexing throughput drop (below baseline)

Reference: [Watcher](https://www.elastic.co/guide/en/elasticsearch/reference/current/xpack-alerting.html)
