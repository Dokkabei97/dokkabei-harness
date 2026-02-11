---
title: Monitor _nodes/stats and hot_threads for Node-Level Performance Issues
impact: LOW-MEDIUM
impactDescription: Identifies JVM pressure, indexing bottlenecks, and CPU hotspots per node
tags: monitoring, node-stats, hot-threads, jvm, performance, diagnostics
---

## Monitor _nodes/stats and hot_threads for Node-Level Performance Issues

`_nodes/stats` provides detailed per-node metrics for JVM, indexing, search, and OS. `_nodes/hot_threads` shows what threads are consuming CPU, essential for diagnosing slow operations.

**Key metrics to monitor:**

```json
// JVM heap usage — sustained >75% is concerning
GET /_nodes/stats/jvm?filter_path=nodes.*.jvm.mem.heap_used_percent

// Indexing throughput and latency
GET /_nodes/stats/indices/indexing?filter_path=nodes.*.indices.indexing

// Search performance
GET /_nodes/stats/indices/search?filter_path=nodes.*.indices.search
// Watch: query_time_in_millis / query_total = avg query latency

// Thread pool rejections (write, search, get)
GET /_nodes/stats/thread_pool?filter_path=nodes.*.thread_pool.write.rejected,nodes.*.thread_pool.search.rejected

// OS-level metrics
GET /_nodes/stats/os?filter_path=nodes.*.os.cpu.percent,nodes.*.os.mem

// File system usage
GET /_nodes/stats/fs?filter_path=nodes.*.fs.total
```

**Hot threads analysis:**

```json
// Show top 3 CPU-consuming threads per node
GET /_nodes/hot_threads?threads=3&type=cpu&interval=500ms

// Output shows thread stack traces:
// ::: {data-1}{...}
//    3.2% CPU usage by thread 'elasticsearch[data-1][search][T#7]'
//      10/10 snapshots sharing following elements:
//        org.apache.lucene.search.BooleanScorer.score
//        ...
// This tells you which operation (search, indexing, merge) is consuming CPU
```

Reference: [Nodes stats](https://www.elastic.co/guide/en/elasticsearch/reference/current/cluster-nodes-stats.html)
