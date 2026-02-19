---
title: "Set JVM Heap to Half RAM, Never Exceeding 31GB"
impact: CRITICAL
impactDescription: "Prevents GC thrashing and OOM, enables compressed oops"
tags: cluster, jvm, heap, memory, compressed-oops
---

## Set JVM Heap to Half RAM, Never Exceeding 31GB

The JVM's compressed ordinary object pointers (compressed oops) optimize memory usage by storing 64-bit pointers as 32-bit values. This optimization is lost when heap exceeds ~31GB, causing a paradox: a 32GB heap can effectively hold less data than a 31GB heap. Meanwhile, Elasticsearch relies heavily on the OS filesystem cache for Lucene segment reads, so the other half of RAM must remain free for the kernel.

**Incorrect (heap exceeds compressed oops threshold):**

```bash
# jvm.options - 128GB RAM machine
# BAD: 64GB heap loses compressed oops, wastes 40-50% more memory per object
# BAD: Only 64GB left for filesystem cache on a machine with terabytes of data
-Xms64g
-Xmx64g
```

```bash
# jvm.options - 64GB RAM machine
# BAD: 40GB heap loses compressed oops
# BAD: Only 24GB left for OS + filesystem cache
-Xms40g
-Xmx40g
```

With compressed oops disabled (heap > ~31GB), every object reference consumes 8 bytes instead of 4 bytes. This means a 32GB heap may hold fewer objects than a 30GB heap, while also stealing RAM from Lucene's filesystem cache.

**Correct (heap at 50% RAM, capped at 31GB):**

```bash
# jvm.options - 64GB RAM machine
# GOOD: 31GB enables compressed oops
# GOOD: 33GB available for filesystem cache + OS
-Xms31g
-Xmx31g
```

```bash
# jvm.options - 32GB RAM machine (common cloud instance)
# GOOD: 16GB heap, 16GB for filesystem cache
-Xms16g
-Xmx16g
```

```bash
# jvm.options - 128GB RAM machine
# GOOD: Still cap at 31GB for compressed oops
# GOOD: 97GB available for filesystem cache (excellent for large datasets)
# Use -Xms30g for safety margin on some JVM implementations
-Xms30g
-Xmx30g
```

**Memory breakdown for a 64GB data node:**

```
+------------------------------------------------------------------+
|                      64GB Total RAM                               |
+------------------------------------------------------------------+
| JVM Heap: 31GB                | OS + Filesystem Cache: 33GB      |
| - Field data                  | - Lucene segment reads           |
| - Node query cache            | - OS page cache                  |
| - Shard request cache         | - Kernel + system processes      |
| - Indexing buffer              | - Memory-mapped files            |
| - Cluster state               |                                  |
| - Circuit breaker reserves    |                                  |
+-------------------------------+----------------------------------+
```

**Verification commands:**

```json
// Check compressed oops status
GET /_nodes/jvm

// Key field in response:
// "using_compressed_ordinary_object_pointers": "true" → compressed oops active

// Monitor heap usage
GET /_nodes/stats/jvm

// Check for GC pressure (old_gc collection time increasing rapidly = trouble)
// "jvm.gc.collectors.old.collection_time_in_millis"
```

**Key rules:**

- Always set `-Xms` and `-Xmx` to the same value to prevent heap resizing pauses.
- Never exceed 31GB (use 30GB for safety margin on some JVM implementations).
- Allocate no more than 50% of physical RAM to heap; the rest is for filesystem cache.
- On machines with less than 8GB RAM, use 50% for heap. On machines with 64GB+, always cap at 31GB.
- Monitor `jvm.gc.collectors.old.collection_time_in_millis` — sustained increases indicate heap pressure.

Reference:
[Heap: Sizing and Swapping](https://www.elastic.co/guide/en/elasticsearch/reference/current/advanced-configuration.html#set-jvm-heap-size)
