---
title: Place $match and $project Early in Aggregation Pipeline
impact: HIGH
impactDescription: 10-100x fewer documents processed in subsequent stages
tags: aggregation, match-first, pipeline-optimization, performance
---

## Place $match and $project Early in Aggregation Pipeline

Placing `$match` at the beginning of the pipeline allows MongoDB to use indexes and reduces the number of documents flowing through subsequent stages. Similarly, early `$project` reduces document size.

**Incorrect ($match after expensive stages):**

```javascript
db.orders.aggregate([
  { $lookup: { from: "products", localField: "productId", foreignField: "_id", as: "product" } },
  { $unwind: "$product" },
  { $group: { _id: "$product.category", total: { $sum: "$amount" } } },
  { $match: { _id: "electronics" } }  // filtering at the end!
]);
// Processes ALL orders through $lookup and $group before filtering
```

**Correct ($match first, then $project to reduce size):**

```javascript
db.orders.aggregate([
  { $match: { category: "electronics", createdAt: { $gte: new Date("2024-01-01") } } },
  { $project: { productId: 1, amount: 1 } },  // reduce document size early
  { $lookup: { from: "products", localField: "productId", foreignField: "_id", as: "product" } },
  { $unwind: "$product" },
  { $group: { _id: "$product.subcategory", total: { $sum: "$amount" } } }
]);
// $match uses index, reduces documents 100x before $lookup
```

MongoDB's query optimizer can automatically move some `$match` stages earlier, but explicit ordering is more reliable and clearer.

Reference: [Aggregation Pipeline Optimization](https://www.mongodb.com/docs/manual/core/aggregation-pipeline-optimization/)
