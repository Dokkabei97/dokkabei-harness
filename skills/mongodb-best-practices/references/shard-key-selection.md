---
title: Choose Shard Keys Based on Cardinality, Frequency, and Monotonicity
impact: MEDIUM
impactDescription: Wrong shard key causes hot spots, unbalanced chunks, and performance bottlenecks
tags: shard-key, cardinality, hashed-sharding, ranged-sharding, distribution
---

## Choose Shard Keys Based on Cardinality, Frequency, and Monotonicity

The shard key determines how data is distributed across shards. A poor choice leads to unbalanced data distribution (hot spots), jumbo chunks, and queries that scatter across all shards.

**Incorrect (monotonically increasing shard key creates hot spot):**

```javascript
// Shard key: { _id: 1 } with ObjectId — monotonically increasing
sh.shardCollection("myApp.orders", { _id: 1 });
// All new inserts go to the SAME shard (the one owning the max range)
// One shard handles 100% of writes while others sit idle
```

**Correct (choose shard key based on three criteria):**

```javascript
// Option 1: Hashed shard key for even write distribution
sh.shardCollection("myApp.orders", { _id: "hashed" });
// Hashed _id distributes writes evenly across all shards
// Trade-off: range queries on _id become scatter-gather

// Option 2: Compound shard key for targeted queries + distribution
sh.shardCollection("myApp.orders", { customerId: 1, orderDate: 1 });
// customerId: high cardinality (millions of values) — good distribution
// orderDate: supports range queries within a customer
// Queries with customerId are targeted to specific shard

// Option 3: Hashed prefix for write distribution + range suffix
sh.shardCollection("myApp.events", { userId: "hashed", timestamp: 1 });
```

**Shard key selection criteria:**

| Criteria | Good | Bad |
|---|---|---|
| **Cardinality** | userId (millions) | status (3 values) |
| **Frequency** | Evenly distributed | 80% same value |
| **Monotonicity** | Random/hashed | Auto-increment, ObjectId, timestamp |

Shard keys are immutable after MongoDB 5.0 allows `reshardCollection`, but it's an expensive operation. Choose carefully upfront.

Reference: [Shard Key Selection](https://www.mongodb.com/docs/manual/core/sharding-choose-a-shard-key/)
