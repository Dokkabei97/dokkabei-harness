---
title: Include Shard Key in Queries for Targeted Operations
impact: MEDIUM
impactDescription: 10-50x faster queries by targeting single shard instead of scatter-gather
tags: targeted-query, scatter-gather, shard-key, routing, performance
---

## Include Shard Key in Queries for Targeted Operations

Queries that include the shard key are routed to the specific shard(s) holding the data (targeted queries). Without the shard key, the query must be sent to ALL shards (scatter-gather), which is dramatically slower.

**Incorrect (scatter-gather query without shard key):**

```javascript
// Shard key: { customerId: 1 }
// Query without shard key — hits ALL shards
db.orders.find({ status: "pending", createdAt: { $gte: new Date("2024-01-01") } });
// mongos sends query to all 10 shards, merges results — 10x more work
// explain: "SHARD_MERGE" stage, all shards listed in "shards" field
```

**Correct (targeted query includes shard key):**

```javascript
// Shard key: { customerId: 1 }
// Query includes shard key — routed to single shard
db.orders.find({
  customerId: "cust_123",
  status: "pending",
  createdAt: { $gte: new Date("2024-01-01") }
});
// mongos routes to the ONE shard holding cust_123's data
// explain: only one shard listed, no SHARD_MERGE

// For updateOne/deleteOne, shard key is REQUIRED (or _id)
db.orders.updateOne(
  { customerId: "cust_123", _id: orderId },  // include shard key
  { $set: { status: "shipped" } }
);
```

Design your shard key around your most frequent query patterns:

```javascript
// If most queries filter by region + date:
sh.shardCollection("myApp.events", { region: 1, eventDate: 1 });

// These are targeted:
db.events.find({ region: "ap-northeast-2", eventDate: { $gte: startDate } });

// This is scatter-gather (no region):
db.events.find({ eventDate: { $gte: startDate } });
```

Use `explain()` to verify whether queries are targeted or scatter-gather.

Reference: [Targeted Operations](https://www.mongodb.com/docs/manual/core/sharded-cluster-query-router/#targeted-operations-vs.-broadcast-operations)
