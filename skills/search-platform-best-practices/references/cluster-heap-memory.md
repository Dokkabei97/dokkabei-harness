---
title: Set Heap to 50% of RAM, Never Exceed 32GB for Compressed OOPs
impact: CRITICAL
impactDescription: Exceeding 32GB wastes ~40% memory by disabling pointer compression, wrong ratio causes OOM or cache starvation
tags: cluster, heap, memory, jvm, compressed-oops, gc, performance
---

## Set Heap to 50% of RAM, Never Exceed 32GB for Compressed OOPs

Elasticsearch heap memory controls data structures (field data, node query cache, indexing buffers, cluster state). The other half of RAM is used by the OS filesystem cache (Lucene segments). Getting this ratio wrong either causes OutOfMemory errors (too small) or starves Lucene's file cache (too large).

**Incorrect (heap too large — exceeds 32GB boundary):**

```bash
# 64GB RAM machine — setting heap to 40GB
# jvm.options
-Xms40g
-Xmx40g

# JVM disables Compressed Ordinary Object Pointers (OOPs) above ~32GB
# Every object reference grows from 4 bytes to 8 bytes
# Effective usable heap is LESS than a 31GB heap — you waste memory!
# Also: only 24GB left for filesystem cache — Lucene segments thrash disk
```

**Incorrect (heap too small — OOM on large aggregations):**

```bash
# 64GB RAM machine — heap only 4GB
-Xms4g
-Xmx4g

# Field data for aggregations, node query cache, and indexing buffers compete
# Large terms aggregation → OutOfMemoryError → node crashes
# 60GB for filesystem cache is overkill — diminishing returns
```

**Correct (50% of RAM, capped at ~31GB):**

```bash
# 64GB RAM machine — 31GB heap, 33GB for filesystem cache
# jvm.options
-Xms31g
-Xmx31g
# Always set Xms = Xmx (avoid heap resizing overhead)

# Verify Compressed OOPs is active
# In Elasticsearch logs at startup:
# "heap size [31gb], compressed ordinary object pointers [true]"
```

```json
// Verify heap settings via API
GET /_nodes/stats/jvm?filter_path=nodes.*.jvm.mem

// Check if compressed OOPs is enabled
GET /_nodes?filter_path=nodes.*.jvm.using_compressed_ordinary_object_pointers
// Should show: "using_compressed_ordinary_object_pointers": "true"
```

Heap sizing guidelines by machine RAM:

| Total RAM | Heap (Xms/Xmx) | Filesystem Cache | Compressed OOPs |
|-----------|----------------|-----------------|-----------------|
| 16GB | 8GB | 8GB | Yes |
| 32GB | 16GB | 16GB | Yes |
| 64GB | 31GB | 33GB | Yes |
| 128GB | 31GB | 97GB | Yes |
| 256GB | 31GB | 225GB | Yes |

For machines with >64GB RAM, the extra memory goes to filesystem cache (beneficial for large indices) or consider running multiple ES instances per machine.

Heap breakdown (typical allocation):

```
31GB Heap
├── Field Data Cache: up to 40% (default unbounded — set indices.fielddata.cache.size)
├── Node Query Cache: 10% (filter cache bitsets)
├── Indexing Buffer: 10% (indices.memory.index_buffer_size)
├── Shard Request Cache: 1-2%
├── Cluster State: varies (grows with shard count)
└── Remaining: JVM overhead, in-flight requests, aggregation buckets
```

Monitor heap pressure:

```json
GET /_nodes/stats/jvm?filter_path=nodes.*.jvm.mem.heap_used_percent
// Sustained >75% → consider adding nodes or reducing shard count
// >85% → GC thrashing likely, immediate action needed
// >95% → circuit breakers should trip; if not, node may OOM
```

Reference: [Heap size settings](https://www.elastic.co/guide/en/elasticsearch/reference/current/advanced-configuration.html#set-jvm-heap-size)
