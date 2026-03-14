---
title: Use TTL Indexes to Automatically Expire Stale Data
impact: MEDIUM
impactDescription: Automatic data cleanup, no cron jobs, reduced storage costs
tags: ttl-index, data-expiration, automatic-cleanup, storage
---

## Use TTL Indexes to Automatically Expire Stale Data

TTL (Time-To-Live) indexes automatically delete documents after a specified time period. This eliminates the need for manual cleanup scripts or cron jobs.

**Incorrect (manual deletion with scheduled script):**

```javascript
// Cron job that runs every hour to delete expired sessions
// Causes load spikes, may miss documents, requires maintenance
db.sessions.deleteMany({
  createdAt: { $lt: new Date(Date.now() - 24 * 60 * 60 * 1000) }
});
```

**Correct (TTL index handles expiration automatically):**

```javascript
// Create TTL index — MongoDB automatically deletes documents
// 24 hours after the createdAt timestamp
db.sessions.createIndex(
  { createdAt: 1 },
  { expireAfterSeconds: 86400 }  // 24 hours
);

// Documents are automatically removed by the TTL background thread
// Runs every 60 seconds, removing expired documents in small batches
```

TTL considerations:
- The TTL field must be a Date type (not a number/timestamp)
- TTL background thread runs every 60 seconds — not real-time deletion
- On replica sets, TTL deletions only happen on the primary
- Cannot create TTL index on a capped collection or _id field

Reference: [TTL Indexes](https://www.mongodb.com/docs/manual/core/index-ttl/)
