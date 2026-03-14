---
title: Handle Aggregation Memory Limits for Large Data Sets
impact: HIGH
impactDescription: Prevents "exceeded memory limit" errors on large aggregations
tags: aggregation, memory-limit, allowDiskUse, performance
---

## Handle Aggregation Memory Limits for Large Data Sets

Each aggregation pipeline stage has a 100MB RAM limit by default. Large datasets will fail without proper handling.

**Incorrect (exceeding memory limit):**

```javascript
// 10M documents x $group on high-cardinality field
db.events.aggregate([
  { $group: { _id: "$userId", totalEvents: { $sum: 1 } } }
]);
// Error: "Exceeded memory limit for $group"
```

**Correct (allowDiskUse and pipeline optimization):**

```javascript
// Option 1: Allow disk use for spill-to-disk
db.events.aggregate(
  [
    { $match: { createdAt: { $gte: new Date("2024-01-01") } } }, // reduce data first
    { $group: { _id: "$userId", totalEvents: { $sum: 1 } } },
    { $sort: { totalEvents: -1 } },
    { $limit: 100 }
  ],
  { allowDiskUse: true }
);

// Option 2: Use $bucketAuto for automatic grouping
db.events.aggregate([
  { $match: { createdAt: { $gte: new Date("2024-01-01") } } },
  { $bucketAuto: { groupBy: "$userId", buckets: 1000, output: { count: { $sum: 1 } } } }
]);
```

Best practices:
- Always `$match` early to reduce data volume
- Use `$project` to drop unneeded fields before heavy stages
- `allowDiskUse: true` is slower than in-memory but prevents failures
- Consider incremental aggregation with `$merge` or `$out` for recurring large jobs

Reference: [Aggregation Pipeline Limits](https://www.mongodb.com/docs/manual/core/aggregation-pipeline-limits/)
