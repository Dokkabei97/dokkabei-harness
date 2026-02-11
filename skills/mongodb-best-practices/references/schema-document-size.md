---
title: Keep Documents Under 16MB and Design for Bounded Growth
impact: CRITICAL
impactDescription: Prevents hard failures and ensures predictable performance
tags: document-size, 16mb-limit, bson, bounded-growth
---

## Keep Documents Under 16MB and Design for Bounded Growth

MongoDB has a hard 16MB BSON document size limit. Documents approaching this limit cause performance degradation long before hitting it. Design schemas for bounded document growth.

**Incorrect (unbounded array growth hits 16MB limit):**

```javascript
// Storing every event in a single user document
db.users.updateOne(
  { _id: userId },
  { $push: { activityLog: { action: "click", ts: new Date(), page: "/home" } } }
);
// After 1M events, document exceeds 16MB — hard error!
// Even at 100K events, document reads become extremely slow
```

**Correct (bounded design with separate collection):**

```javascript
// Store events in a separate collection with reference
db.activities.insertOne({
  userId: userId,
  action: "click",
  ts: new Date(),
  page: "/home"
});
// Create index for efficient queries
db.activities.createIndex({ userId: 1, ts: -1 });

// Query user's recent activity
db.activities.find({ userId: userId }).sort({ ts: -1 }).limit(50);
```

Use the Bucket Pattern for high-volume time-series data:

```javascript
// Group events into 1-hour buckets (bounded to ~100 events each)
db.activityBuckets.updateOne(
  { userId: userId, hour: new Date("2024-01-15T10:00:00Z") },
  {
    $push: { events: { action: "click", ts: new Date(), page: "/home" } },
    $inc: { count: 1 }
  },
  { upsert: true }
);
```

Reference: [BSON Document Size Limit](https://www.mongodb.com/docs/manual/reference/limits/#bson-document-size)
