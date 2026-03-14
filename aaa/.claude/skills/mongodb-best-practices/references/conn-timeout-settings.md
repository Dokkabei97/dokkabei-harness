---
title: Configure Appropriate Timeout Settings for Production
impact: MEDIUM-HIGH
impactDescription: Prevents hanging connections and cascading failures
tags: timeout, connection-timeout, socket-timeout, production-config
---

## Configure Appropriate Timeout Settings for Production

Default timeout settings are often too generous for production. Long timeouts cause thread/connection pool exhaustion during partial failures. Configure timeouts based on your SLA requirements.

**Incorrect (default timeouts cause hanging):**

```javascript
const client = new MongoClient(uri);
// Default serverSelectionTimeoutMS: 30000 (30 seconds!)
// If cluster is unreachable, every request hangs for 30 seconds
// 100 requests/second x 30 second timeout = 3,000 hanging connections
```

**Correct (aggressive timeouts for fail-fast behavior):**

```javascript
const client = new MongoClient(uri, {
  // Server selection: how long to find an available server
  serverSelectionTimeoutMS: 5000,    // 5s (default: 30s)

  // Connection: how long to establish a new connection
  connectTimeoutMS: 10000,            // 10s (default: 30s)

  // Socket: max time for a single operation
  socketTimeoutMS: 45000,             // 45s (default: 0/infinite)

  // Wait queue: max time waiting for an available connection
  waitQueueTimeoutMS: 5000,           // 5s (default: 0/infinite)

  // Heartbeat: how often to check server health
  heartbeatFrequencyMS: 10000,        // 10s (default: 10s)

  // Max staleness for secondary reads
  maxStalenessSeconds: 90             // 90s (minimum: 90s)
});
```

For serverless environments (Lambda, Cloud Functions):

```javascript
const client = new MongoClient(uri, {
  serverSelectionTimeoutMS: 3000,  // fail fast in Lambda
  connectTimeoutMS: 5000,
  socketTimeoutMS: 10000,          // Lambda timeout - 5s buffer
  maxPoolSize: 1,                  // single connection per function instance
  minPoolSize: 0
});
```

Reference: [Connection Options](https://www.mongodb.com/docs/drivers/node/current/fundamentals/connection/connection-options/)
