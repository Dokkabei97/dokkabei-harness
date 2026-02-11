---
title: Configure Translog Async Flush for Write-Heavy Workloads
impact: MEDIUM
impactDescription: 30-50% indexing throughput improvement by reducing fsync frequency
tags: indexing, translog, flush, async, durability, throughput
---

## Configure Translog Async Flush for Write-Heavy Workloads

Each indexing operation is written to the translog (write-ahead log) and fsync'd to disk by default (`durability: request`). This ensures durability but creates I/O bottleneck on write-heavy workloads. Switching to `async` batches fsync operations, trading a small durability window for significantly higher throughput.

**Incorrect (default sync translog on high-throughput logging):**

```json
// Default: every indexing request triggers fsync
PUT /logs
{
  "settings": {
    "index.translog.durability": "request"
  }
}

// With 50,000 docs/sec ingestion rate:
// Each document → individual fsync → 50,000 fsyncs/sec
// SSD IOPS bottleneck → indexing throughput capped at disk speed
// Bulk API helps batch the request, but each bulk still triggers fsync
```

**Correct (async translog for write-heavy, loss-tolerant workloads):**

```json
PUT /logs
{
  "settings": {
    "index.translog.durability": "async",
    "index.translog.sync_interval": "5s",
    "index.translog.flush_threshold_size": "1gb"
  }
}

// async mode:
// - Translog is fsync'd every sync_interval (5s) instead of per-request
// - Up to 5 seconds of data could be lost on hard crash (node power loss)
// - Flush to Lucene segments when translog reaches 1GB
// - 30-50% higher indexing throughput
```

When to use each mode:

| Workload | Durability | Rationale |
|----------|-----------|-----------|
| Financial transactions | `request` (default) | Zero data loss required |
| Product catalog updates | `request` | Source of truth, updates must persist |
| Application logs | `async` | Logs can be re-ingested from source (Kafka, Filebeat) |
| Metrics/telemetry | `async` | Losing 5s of metrics is acceptable |
| Initial bulk load | `async` | Data exists in source system |
| CDC from database | `async` | Can replay from binlog/WAL |

Monitor translog health:

```json
GET /logs/_stats/translog?filter_path=indices.logs.primaries.translog

// Response:
{
  "indices": {
    "logs": {
      "primaries": {
        "translog": {
          "operations": 125000,
          "size_in_bytes": 268435456,
          "uncommitted_operations": 5000,
          "uncommitted_size_in_bytes": 10485760
        }
      }
    }
  }
}
// Large "uncommitted_operations" = data at risk in async mode
```

Important: Async translog only risks data loss on **unclean shutdown** (power loss, OOM kill). Normal node restarts flush the translog first. If your data can be re-ingested from an upstream source (Kafka, database), the risk is negligible.

Reference: [Translog](https://www.elastic.co/guide/en/elasticsearch/reference/current/index-modules-translog.html)
