---
title: Configure Connection Pool Size Based on Application Needs
impact: HIGH
impactDescription: Handle 10-100x more concurrent requests without connection exhaustion
tags: connection-pool, maxPoolSize, driver-config, scalability
---

## Configure Connection Pool Size Based on Application Needs

MongoDB connections are expensive resources. Too few connections cause request queuing; too many exhaust server resources. Configure pool size based on your workload.

**Incorrect (default settings cause connection exhaustion):**

```javascript
// Default maxPoolSize is 100 — may not be enough or may be too many
const client = new MongoClient(uri);
// 200 concurrent requests -> 100 queue, 100 execute -> high latency
// Or: 50 app instances x 100 pool = 5,000 connections -> server overload
```

**Correct (tuned pool settings):**

```javascript
const client = new MongoClient(uri, {
  maxPoolSize: 50,       // max connections in pool
  minPoolSize: 10,       // keep warm connections ready
  maxIdleTimeMS: 30000,  // close idle connections after 30s
  waitQueueTimeoutMS: 5000,  // fail fast if pool is exhausted
  serverSelectionTimeoutMS: 5000,
  connectTimeoutMS: 10000,
  socketTimeoutMS: 45000
});
```

**Pool sizing formula:**
```
maxPoolSize = (concurrent_requests / app_instances) x 1.5
```

For Atlas, check the connection limits of your tier:
- M10: 350 connections
- M30: 1500 connections
- M50: 3000 connections

Total pool across all instances should stay under 80% of the limit.

Reference: [Connection Pool](https://www.mongodb.com/docs/drivers/node/current/fundamentals/connection/connection-options/)
