---
title: Store Frequently Accessed Reference Fields with Extended Reference Pattern
impact: MEDIUM-HIGH
impactDescription: Eliminates $lookup for common read paths, 2-5x faster queries
tags: extended-reference, denormalization, lookup-avoidance, read-performance
---

## Store Frequently Accessed Reference Fields with Extended Reference Pattern

The Extended Reference Pattern copies a subset of frequently accessed fields from a referenced document into the referencing document. This avoids expensive `$lookup` operations for common read paths.

**Incorrect ($lookup on every read for display data):**

```javascript
// Order only stores customerId — needs $lookup to display customer name
// { _id: 1, customerId: ObjectId("..."), items: [...], total: 50000 }

db.orders.aggregate([
  { $match: { _id: orderId } },
  { $lookup: { from: "customers", localField: "customerId", foreignField: "_id", as: "customer" } },
  { $unwind: "$customer" }
]);
// Every order list page triggers N $lookups — slow and resource-intensive
```

**Correct (embed frequently needed reference fields):**

```javascript
// Store a subset of customer data directly in the order
db.orders.insertOne({
  _id: 1,
  customer: {
    _id: ObjectId("cust_123"),  // keep reference for full lookup if needed
    name: "Kim Minsu",
    email: "kim@example.com"
    // Only copy fields needed for common display — NOT the entire customer doc
  },
  items: [{ product: "Widget", qty: 2, price: 25000 }],
  total: 50000,
  createdAt: new Date()
});

// No $lookup needed for order list display
db.orders.find({ "customer._id": ObjectId("cust_123") })
  .projection({ "customer.name": 1, total: 1, createdAt: 1 });
```

Trade-offs:
- Duplicated data must be updated when the source changes
- Best for data that changes infrequently (name, email) vs data that changes often (balance, status)
- Use `updateMany` to propagate changes when source data is updated

```javascript
// When customer changes their name, update all their orders
await db.orders.updateMany(
  { "customer._id": customerId },
  { $set: { "customer.name": newName, "customer.email": newEmail } }
);
```

Reference: [Extended Reference Pattern](https://www.mongodb.com/blog/post/building-with-patterns-the-extended-reference-pattern)
