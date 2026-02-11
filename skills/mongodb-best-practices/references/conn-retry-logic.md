---
title: Implement Retry Logic for Transient Network Failures
impact: HIGH
impactDescription: 99.9% to 99.99% availability with proper retry handling
tags: retry-logic, retryWrites, retryReads, resilience, availability
---

## Implement Retry Logic for Transient Network Failures

Transient failures (network blips, primary elections, maintenance) are normal in distributed systems. Enable retryable operations and implement application-level retry logic.

**Incorrect (no retry — transient failure causes user error):**

```javascript
const client = new MongoClient(uri);
// Primary election takes ~10 seconds
// All writes during this window fail permanently
try {
  await db.orders.insertOne(order);
} catch (err) {
  // "not primary" or "node is recovering" — user sees error
  throw err;
}
```

**Correct (retryable writes + application retry):**

```javascript
// Enable retryable writes and reads in connection string
const client = new MongoClient(uri, {
  retryWrites: true,     // automatic retry for write operations
  retryReads: true,      // automatic retry for read operations
  w: "majority",         // durable writes
  readPreference: "primaryPreferred"  // fallback to secondary for reads
});

// Application-level retry for complex operations
async function withRetry(operation, maxRetries = 3) {
  for (let attempt = 1; attempt <= maxRetries; attempt++) {
    try {
      return await operation();
    } catch (err) {
      if (attempt === maxRetries || !isTransientError(err)) throw err;
      await new Promise(r => setTimeout(r, Math.pow(2, attempt) * 100));
    }
  }
}

function isTransientError(err) {
  return err.hasErrorLabel?.("TransientTransactionError") ||
         err.hasErrorLabel?.("RetryableWriteError") ||
         [11600, 11602, 10107, 13435, 13436].includes(err.code);
}
```

Reference: [Retryable Writes](https://www.mongodb.com/docs/manual/core/retryable-writes/)
