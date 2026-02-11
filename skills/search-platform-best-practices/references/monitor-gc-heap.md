---
title: Monitor GC Logs and Heap Pressure to Prevent OOM
impact: LOW-MEDIUM
impactDescription: Early detection of memory pressure prevents node crashes and cluster instability
tags: monitoring, gc, heap, jvm, memory, oom, pressure
---

## Monitor GC Logs and Heap Pressure to Prevent OOM

Garbage collection (GC) pauses directly impact query latency and indexing throughput. When heap usage is consistently high, GC runs frequently and for longer durations, eventually leading to OOM.

**Key JVM metrics to monitor:**

```json
// Heap usage percentage — primary indicator
GET /_nodes/stats/jvm?filter_path=nodes.*.jvm.mem
// heap_used_percent > 75% sustained → add nodes or reduce shard count
// heap_used_percent > 85% → GC thrashing likely

// GC statistics
GET /_nodes/stats/jvm?filter_path=nodes.*.jvm.gc.collectors
// old generation collection_count increasing rapidly = heap pressure
// old generation collection_time_in_millis / collection_count = avg GC pause

// Field data cache (common heap consumer)
GET /_nodes/stats/indices/fielddata?filter_path=nodes.*.indices.fielddata
// High fielddata evictions = too many text field aggregations
```

Enable GC logging:

```bash
# jvm.options (ES 7+)
-Xlog:gc*,gc+age=trace,safepoint:file=logs/gc.log:utctime,pid,tags:filecount=32,filesize=64m
```

Heap pressure thresholds:

| Heap % | Status | Action |
|--------|--------|--------|
| < 65% | Healthy | Normal operations |
| 65-75% | Warning | Monitor trends |
| 75-85% | Danger | Reduce load, investigate causes |
| > 85% | Critical | Immediate action — circuit breakers should trip |
| > 95% | Emergency | Node likely unresponsive, risk of OOM |

Common heap consumers and fixes:
- **Field data**: Use keyword fields for aggregations instead of text
- **Node query cache**: Reduce if not using many filter queries
- **Shard overhead**: Reduce shard count
- **In-flight requests**: Add coordinating nodes to offload

Reference: [Advanced JVM configuration](https://www.elastic.co/guide/en/elasticsearch/reference/current/advanced-configuration.html)
