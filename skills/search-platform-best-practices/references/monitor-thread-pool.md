---
title: Monitor Thread Pool Queues and Rejections for Capacity Bottlenecks
impact: LOW-MEDIUM
impactDescription: Thread pool rejections indicate cluster capacity limits — the first sign of overload
tags: monitoring, thread-pool, rejection, queue, capacity, overload
---

## Monitor Thread Pool Queues and Rejections for Capacity Bottlenecks

Each operation type (search, write, get, management) has a dedicated thread pool with a fixed queue. When the queue is full, operations are rejected with HTTP 429. Rejections are the first sign that the cluster cannot handle the current load.

**Monitor thread pools:**

```json
GET /_cat/thread_pool?v&h=node_name,name,active,queue,rejected,completed&s=rejected:desc
// Focus on: write, search, get, management thread pools
// rejected > 0 = operations have been dropped

// Detailed per-node
GET /_nodes/stats/thread_pool?filter_path=nodes.*.thread_pool.write,nodes.*.thread_pool.search
```

Key thread pools:

| Pool | Operations | Queue Size | Action on Rejection |
|------|-----------|------------|-------------------|
| `write` | Index, delete, bulk | 200 | Client retries with backoff |
| `search` | Search, count | 1000 | Simplify queries, add nodes |
| `get` | Get by ID | 1000 | Add coordinating nodes |
| `management` | Cluster state | 200 | Scale master nodes |

When rejections occur:

```json
// Step 1: Check which pool is rejecting
GET /_cat/thread_pool/write,search?v&h=node_name,name,active,queue,rejected

// Step 2: Increase queue size temporarily (not a permanent fix)
PUT /_cluster/settings
{
  "transient": {
    "thread_pool.write.queue_size": 500
  }
}

// Step 3: Address root cause
// Write rejections: reduce bulk request rate, add data nodes
// Search rejections: optimize queries, add coordinating/data nodes
// Management rejections: reduce shard count, upgrade master nodes
```

Reference: [Thread pools](https://www.elastic.co/guide/en/elasticsearch/reference/current/modules-threadpool.html)
