---
title: Store Recent Subset in Main Document with Full Data Separately
impact: MEDIUM-HIGH
impactDescription: 80% smaller working set, faster reads for common access patterns
tags: subset-pattern, working-set, cache, recent-data, schema-design
---

## Store Recent Subset in Main Document with Full Data Separately

The Subset Pattern stores the most recent or relevant subset of an array in the main document, keeping the full dataset in a separate collection. This reduces the working set size and keeps frequently accessed data fast.

**Incorrect (all reviews embedded in product document):**

```javascript
// Product document grows with every review — 5,000 reviews = huge document
db.products.findOne({ _id: "prod_123" });
// Returns 500KB document when you only need the latest 5 reviews for display
// Wastes RAM in working set — 10,000 products x 500KB = 5GB just for products
```

**Correct (subset of recent reviews in product, full reviews separate):**

```javascript
// Product document has only the 10 most recent reviews
db.products.insertOne({
  _id: "prod_123",
  name: "Wireless Headphones",
  price: 89000,
  recentReviews: [
    { userId: "u1", rating: 5, comment: "Great sound!", createdAt: new Date("2024-06-15") },
    { userId: "u2", rating: 4, comment: "Good value", createdAt: new Date("2024-06-14") }
    // ... max 10 reviews
  ],
  stats: { avgRating: 4.5, totalReviews: 5000 }
});

// Full review history in a separate collection
db.reviews.insertOne({
  productId: "prod_123",
  userId: "u1",
  rating: 5,
  comment: "Great sound!",
  createdAt: new Date("2024-06-15")
});
db.reviews.createIndex({ productId: 1, createdAt: -1 });

// When adding a new review, update the subset
async function addReview(productId, review) {
  // 1. Insert into full reviews collection
  await db.reviews.insertOne({ productId, ...review, createdAt: new Date() });

  // 2. Update subset: push new review, keep only 10 most recent
  await db.products.updateOne(
    { _id: productId },
    {
      $push: {
        recentReviews: {
          $each: [{ ...review, createdAt: new Date() }],
          $sort: { createdAt: -1 },
          $slice: 10  // keep only the 10 most recent
        }
      },
      $inc: { "stats.totalReviews": 1 }
    }
  );
}
```

Product page loads only need the main document (fast, small). "See all reviews" page queries the reviews collection with pagination. Working set drops from 5GB to ~500MB.

Reference: [Subset Pattern](https://www.mongodb.com/blog/post/building-with-patterns-the-subset-pattern)
