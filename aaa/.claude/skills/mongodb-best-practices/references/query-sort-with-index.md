---
title: Ensure Sort Operations Use Index to Avoid In-Memory Sort
impact: CRITICAL
impactDescription: Eliminates 100MB in-memory sort limit and 10-100x faster sorted results
tags: sort, index, in-memory-sort, performance
---

## Ensure Sort Operations Use Index to Avoid In-Memory Sort

Sort operations without a supporting index must load all matching documents into memory (limited to 100MB by default). With proper indexes, MongoDB returns results in sorted order directly from the index.

**Incorrect (in-memory sort on large result set):**

```javascript
// No index on createdAt
db.orders.find({ status: "pending" }).sort({ createdAt: -1 });
// With 1M matching documents: "Sort exceeded memory limit of 100MB"
// Or uses disk-based sort — extremely slow
```

**Correct (index-backed sort):**

```javascript
// Compound index supports both filter and sort
db.orders.createIndex({ status: 1, createdAt: -1 });

db.orders.find({ status: "pending" }).sort({ createdAt: -1 });
// explain: stage = IXSCAN, no SORT stage — results pre-sorted by index
```

Index sort direction matters — `{ createdAt: 1 }` supports ascending sort but requires a reverse index scan for descending. For multi-field sorts, directions must match:

```javascript
// Sort: { status: 1, createdAt: -1 }
// Index must match: { status: 1, createdAt: -1 } ✓
// NOT: { status: 1, createdAt: 1 } ✗
```

Reference: [Use Indexes to Sort Query Results](https://www.mongodb.com/docs/manual/tutorial/sort-results-with-indexes/)
