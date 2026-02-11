---
title: Optimize $lookup with Pipeline and Limit Joined Data
impact: HIGH
impactDescription: 5-20x faster joins by limiting lookup scope
tags: lookup, join, pipeline, aggregation, performance
---

## Optimize $lookup with Pipeline and Limit Joined Data

The default `$lookup` performs an equality join on the entire foreign collection. Use the pipeline form with `$match` and `$limit` to restrict the joined data.

**Incorrect (basic $lookup loads entire matching set):**

```javascript
db.orders.aggregate([
  { $lookup: {
    from: "reviews",
    localField: "productId",
    foreignField: "productId",
    as: "reviews"
  }}
]);
// If a product has 10,000 reviews, ALL 10K are loaded into each order document
```

**Correct (pipeline $lookup with filtering and limiting):**

```javascript
db.orders.aggregate([
  { $lookup: {
    from: "reviews",
    let: { pid: "$productId" },
    pipeline: [
      { $match: { $expr: { $eq: ["$productId", "$$pid"] }, rating: { $gte: 4 } } },
      { $sort: { createdAt: -1 } },
      { $limit: 3 },
      { $project: { rating: 1, comment: 1 } }
    ],
    as: "topReviews"
  }}
]);
// Only loads top 3 high-rated reviews per product — 3,000x less data
```

For better performance, ensure the foreign collection has appropriate indexes:

```javascript
// Index on the foreign collection for the $lookup
db.reviews.createIndex({ productId: 1, rating: -1, createdAt: -1 });
```

Reference: [$lookup with Pipeline](https://www.mongodb.com/docs/manual/reference/operator/aggregation/lookup/#join-conditions-and-subqueries-on-a-joined-collection)
