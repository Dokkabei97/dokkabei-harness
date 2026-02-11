---
title: Follow the ESR Rule for Compound Index Field Order
impact: CRITICAL
impactDescription: 10-100x query performance improvement with optimal field ordering
tags: esr-rule, compound-index, equality, sort, range, performance
---

## Follow the ESR Rule for Compound Index Field Order

The ESR (Equality, Sort, Range) rule determines optimal field order in compound indexes. Equality fields first, then Sort fields, then Range fields. This ordering maximizes index efficiency.

**Incorrect (Range before Sort):**

```javascript
// Index: { createdAt: 1, status: 1, category: 1 }
// createdAt is Range, status is Equality — wrong order
db.products.find({
  status: "active",
  createdAt: { $gte: new Date("2024-01-01") }
}).sort({ category: 1 });
// Cannot use index for sort — triggers in-memory SORT stage
```

**Correct (ESR ordering):**

```javascript
// Index follows ESR: Equality(status) → Sort(category) → Range(createdAt)
db.products.createIndex({ status: 1, category: 1, createdAt: 1 });

db.products.find({
  status: "active",
  createdAt: { $gte: new Date("2024-01-01") }
}).sort({ category: 1 });
// explain: IXSCAN with no SORT stage
// Equality: exact match on status narrows scan
// Sort: index provides sort order for category
// Range: createdAt range within each category group
```

**ESR Rule Summary:**
1. **Equality** fields (`$eq`, `$in`) — placed first, narrows the scan range
2. **Sort** fields — placed next, eliminates in-memory sort
3. **Range** fields (`$gt`, `$lt`, `$gte`, `$lte`, `$ne`) — placed last

Reference: [ESR Rule](https://www.mongodb.com/docs/manual/tutorial/equality-sort-range-rule/)
