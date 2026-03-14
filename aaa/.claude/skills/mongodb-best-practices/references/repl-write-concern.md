---
title: Choose Write Concern Based on Durability vs Performance Requirements
impact: MEDIUM
impactDescription: w:majority ensures data survives primary failure, w:1 is 2-5x faster but risks data loss
tags: write-concern, w-majority, durability, replication, data-safety
---

## Choose Write Concern Based on Durability vs Performance Requirements

Write concern controls how many replica set members must acknowledge a write before it's considered successful. `w:1` (default) acknowledges after the primary writes; `w:"majority"` waits for a majority of members.

**Incorrect (w:1 for critical financial data):**

```javascript
// w:1 only waits for primary acknowledgment
// If primary crashes before replicating, the write is LOST
await db.payments.insertOne(
  { userId: "u1", amount: 500000, type: "withdrawal" },
  { writeConcern: { w: 1 } }
);
// Primary crashes 100ms later — payment record vanishes
// But user's bank account was already debited
```

**Correct (w:"majority" for critical data, w:1 for non-critical):**

```javascript
// Critical data: w:"majority" ensures durability across failures
await db.payments.insertOne(
  { userId: "u1", amount: 500000, type: "withdrawal" },
  { writeConcern: { w: "majority", j: true, wtimeout: 5000 } }
);
// Write survives even if primary crashes — replicated to majority of nodes
// j:true ensures write is committed to journal on disk

// Non-critical data: w:1 for better performance
await db.logs.insertOne(
  { level: "info", message: "User logged in", ts: new Date() },
  { writeConcern: { w: 1 } }
);
// Losing a log entry is acceptable — prioritize throughput
```

**Write concern comparison:**

| Write Concern | Latency | Durability | Use Case |
|---|---|---|---|
| `w: 0` | Lowest | None (fire-and-forget) | Metrics, non-critical logs |
| `w: 1` | Low | Primary only | Session data, caches |
| `w: "majority"` | Medium | Survives primary failure | Financial, user data |
| `w: "majority", j: true` | Highest | Survives primary + journal | Regulatory compliance |

Set default write concern at the connection level and override per-operation:

```javascript
const client = new MongoClient(uri, { w: "majority", journal: true });
```

Reference: [Write Concern](https://www.mongodb.com/docs/manual/reference/write-concern/)
