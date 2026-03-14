---
title: Optimize Aggregation Pipeline Stage Ordering
impact: HIGH
impactDescription: 2-10x faster aggregations with optimal stage placement
tags: aggregation, pipeline-ordering, optimization, performance
---

## Optimize Aggregation Pipeline Stage Ordering

The order of stages in an aggregation pipeline significantly impacts performance. Follow the principle of reducing data volume as early as possible.

**Incorrect (expensive operations before filtering):**

```javascript
db.orders.aggregate([
  { $addFields: { totalWithTax: { $multiply: ["$total", 1.1] } } },
  { $lookup: { from: "customers", localField: "customerId", foreignField: "_id", as: "customer" } },
  { $unwind: "$customer" },
  { $sort: { totalWithTax: -1 } },
  { $match: { status: "completed", "customer.tier": "premium" } },
  { $limit: 10 }
]);
// All documents go through $addFields -> $lookup -> $unwind -> $sort before filtering
```

**Correct (filter early, compute late):**

```javascript
db.orders.aggregate([
  { $match: { status: "completed" } },          // 1. Filter with index
  { $lookup: { from: "customers", localField: "customerId", foreignField: "_id", as: "customer" } },
  { $unwind: "$customer" },
  { $match: { "customer.tier": "premium" } },    // 2. Filter after join
  { $addFields: { totalWithTax: { $multiply: ["$total", 1.1] } } },
  { $sort: { totalWithTax: -1 } },               // 3. Sort reduced set
  { $limit: 10 }                                  // 4. Final limit
]);
```

**Optimal stage ordering:**
1. `$match` — use indexes, reduce documents
2. `$project` / `$addFields` — reduce document size
3. `$lookup` — join (on reduced set)
4. `$unwind` — flatten arrays
5. `$group` — aggregate
6. `$sort` — order results
7. `$limit` / `$skip` — paginate

Reference: [Pipeline Optimization](https://www.mongodb.com/docs/manual/core/aggregation-pipeline-optimization/)
