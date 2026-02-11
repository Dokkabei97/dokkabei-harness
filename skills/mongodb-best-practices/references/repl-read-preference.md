---
title: Configure Read Preference to Balance Consistency and Availability
impact: MEDIUM
impactDescription: Distribute read load across replica set while understanding stale data risks
tags: read-preference, secondary-reads, consistency, availability, replica-set
---

## Configure Read Preference to Balance Consistency and Availability

Read preference controls which replica set member(s) serve read operations. Secondary reads can distribute load but may return stale data due to replication lag.

**Incorrect (secondary reads for consistency-sensitive operations):**

```javascript
// Reading from secondary after a write — may see stale data
await db.accounts.updateOne(
  { _id: userId },
  { $inc: { balance: -50000 } },
  { writeConcern: { w: "majority" } }
);

// Immediately reading from secondary — replication lag means balance may show old value
const account = await db.accounts.findOne(
  { _id: userId },
  { readPreference: "secondary" }
);
// account.balance shows pre-deduction value — user thinks withdrawal failed!
```

**Correct (read preference matched to use case):**

```javascript
// Consistency-critical reads: always read from primary
const account = await db.accounts.findOne(
  { _id: userId },
  { readPreference: "primary" }
);

// Analytics/reporting: secondary is fine (slight lag acceptable)
const stats = await db.orders.aggregate(
  [{ $group: { _id: "$status", count: { $sum: 1 } } }],
  { readPreference: "secondaryPreferred" }
).toArray();

// High availability reads: nearest for lowest latency
const product = await db.products.findOne(
  { _id: productId },
  { readPreference: "nearest" }
);
```

**Read preference options:**

| Preference | Reads From | Stale Data? | Use Case |
|---|---|---|---|
| `primary` | Primary only | No | Writes + immediate reads, financial |
| `primaryPreferred` | Primary, fallback secondary | Rare | Default for most apps |
| `secondary` | Secondary only | Yes | Analytics, reporting |
| `secondaryPreferred` | Secondary, fallback primary | Usually | Dashboards, search |
| `nearest` | Lowest latency member | Possible | Geo-distributed, latency-sensitive |

Set at connection level with per-operation override:

```javascript
const client = new MongoClient(uri, { readPreference: "primaryPreferred" });
```

Reference: [Read Preference](https://www.mongodb.com/docs/manual/core/read-preference/)
