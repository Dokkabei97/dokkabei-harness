---
title: Remove Redundant Indexes That Waste Write Performance
impact: HIGH
impactDescription: 10-30% write throughput improvement per redundant index removed
tags: redundant-index, index-maintenance, write-performance
---

## Remove Redundant Indexes That Waste Write Performance

Every index must be updated on every write operation. Redundant indexes (those whose function is already covered by another index) slow writes with zero benefit.

**Incorrect (redundant indexes):**

```javascript
// These three indexes have redundancy:
db.orders.createIndex({ userId: 1 });                    // redundant!
db.orders.createIndex({ userId: 1, status: 1 });         // redundant!
db.orders.createIndex({ userId: 1, status: 1, date: 1 });
// The compound index { userId: 1, status: 1, date: 1 } covers
// all queries that { userId: 1 } and { userId: 1, status: 1 } would serve
```

**Correct (minimal index set):**

```javascript
// Single compound index serves all three query patterns
db.orders.createIndex({ userId: 1, status: 1, date: 1 });

// Verify with: db.orders.getIndexes()
// Drop redundant: db.orders.dropIndex("userId_1")
// Drop redundant: db.orders.dropIndex("userId_1_status_1")
```

Use `hideIndex()` to test index removal safely before dropping:

```javascript
// Hide the index — queries stop using it but it's not deleted
db.orders.hideIndex("userId_1");
// Monitor for 24-48 hours
// If no performance degradation:
db.orders.dropIndex("userId_1");
```

Reference: [Remove Redundant Indexes](https://www.mongodb.com/docs/manual/tutorial/manage-indexes/#remove-redundant-indexes)
