---
title: Pre-Compute Frequently Accessed Derived Data with Computed Pattern
impact: MEDIUM-HIGH
impactDescription: Eliminates runtime aggregation, sub-millisecond reads for derived values
tags: computed-pattern, pre-computation, derived-data, denormalization, performance
---

## Pre-Compute Frequently Accessed Derived Data with Computed Pattern

Pre-compute frequently accessed derived data (totals, averages, counts) at write time instead of calculating them at read time. This trades slightly more expensive writes for dramatically faster reads.

**Incorrect (computing derived values at read time):**

```javascript
// Every time the product page loads, aggregate all reviews to get average rating
const result = await db.reviews.aggregate([
  { $match: { productId: "prod_123" } },
  { $group: {
    _id: null,
    avgRating: { $avg: "$rating" },
    totalReviews: { $sum: 1 }
  }}
]).toArray();
// 50,000 reviews scanned on every page view — O(n) per read
// With 1000 requests/second = 50M document scans/second
```

**Correct (pre-compute and store derived values):**

```javascript
// Update computed fields when a new review is added
async function addReview(productId, rating, comment) {
  // 1. Insert the review
  await db.reviews.insertOne({ productId, rating, comment, createdAt: new Date() });

  // 2. Update pre-computed values on the product
  await db.products.updateOne(
    { _id: productId },
    {
      $inc: { "stats.totalReviews": 1, "stats.ratingSum": rating },
      $set: { "stats.lastReviewAt": new Date() }
    }
  );

  // 3. Recompute average (or use $inc approach above and compute on read)
  await db.products.updateOne(
    { _id: productId },
    [{ $set: {
      "stats.avgRating": { $divide: ["$stats.ratingSum", "$stats.totalReviews"] }
    }}]
  );
}

// Reading is now O(1) — no aggregation needed
const product = await db.products.findOne(
  { _id: "prod_123" },
  { projection: { name: 1, price: 1, "stats.avgRating": 1, "stats.totalReviews": 1 } }
);
```

Use this pattern when reads vastly outnumber writes (common for e-commerce, social media, dashboards). For critical accuracy, periodically reconcile computed values with a batch recalculation job.

Reference: [Computed Pattern](https://www.mongodb.com/blog/post/building-with-patterns-the-computed-pattern)
