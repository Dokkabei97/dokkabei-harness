---
title: Configure Circuit Breakers to Prevent OutOfMemory Crashes
impact: MEDIUM
impactDescription: Rejects expensive operations gracefully instead of crashing the node with OOM
tags: resilience, circuit-breaker, memory, oom, protection
---

## Configure Circuit Breakers to Prevent OutOfMemory Crashes

Circuit breakers estimate memory usage before executing operations. When an operation would exceed the limit, it's rejected with a clear error instead of crashing the node. Properly configured breakers prevent the most common cause of production outages.

**Incorrect (default breakers too permissive for workload):**

```json
// A massive aggregation or fielddata load exceeds heap
// Without proper breakers: java.lang.OutOfMemoryError → node crashes → shard rebalancing
// With default breakers: may still allow 70%+ heap usage per request
```

**Correct (tuned circuit breakers):**

```json
// View current breaker settings
GET /_nodes/stats/breaker

// Tune breakers for production
PUT /_cluster/settings
{
  "persistent": {
    "indices.breaker.total.limit": "70%",
    "indices.breaker.fielddata.limit": "40%",
    "indices.breaker.request.limit": "40%",
    "network.breaker.inflight_requests.limit": "100%"
  }
}
// total.limit: combined limit for all breakers (percentage of heap)
// fielddata.limit: max heap for fielddata (text field aggregations)
// request.limit: max heap per request (aggregation results, sort buffers)
```

When a circuit breaker trips:

```json
// Error response when breaker trips
{
  "error": {
    "type": "circuit_breaking_exception",
    "reason": "[parent] Data too large, data for [<agg>] would be [15728640/15mb], which is larger than the limit of [10485760/10mb]"
  },
  "status": 429
}
// 429 status — client should back off, simplify query, or reduce data scope
```

Monitor breaker activity:

```json
GET /_nodes/stats/breaker?filter_path=nodes.*.breakers
// Check "tripped" counts — frequent trips indicate need for query optimization or more heap
// "estimated_size" shows current memory usage per breaker
```

Reference: [Circuit breaker settings](https://www.elastic.co/guide/en/elasticsearch/reference/current/circuit-breaker.html)
