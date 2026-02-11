---
title: Avoid Unbounded Array Growth in Document Design
impact: CRITICAL
impactDescription: Prevents performance degradation and 16MB document limit failures
tags: unbounded-array, anti-pattern, array-growth, schema-design
---

## Avoid Unbounded Array Growth in Document Design

Arrays that grow without limit are the most common MongoDB anti-pattern. They cause document growth, increased replication overhead, and eventually hit the 16MB BSON limit.

**Incorrect (unbounded followers array):**

```javascript
// Every new follower appended to array — grows infinitely
db.users.updateOne(
  { _id: "popular_user" },
  { $push: { followers: { userId: "new_follower", followedAt: new Date() } } }
);
// Celebrity with 1M followers: document = 50MB+ — FAILS
// Even 10K followers: slow reads, write amplification on every update
```

**Correct (reverse reference pattern):**

```javascript
// Store the relationship on the "many" side
db.follows.insertOne({
  followerId: "new_follower",
  followeeId: "popular_user",
  followedAt: new Date()
});
db.follows.createIndex({ followeeId: 1, followedAt: -1 });

// Get follower count
db.follows.countDocuments({ followeeId: "popular_user" });

// Get recent followers with pagination
db.follows.find({ followeeId: "popular_user" })
  .sort({ followedAt: -1 })
  .limit(20);
```

**When arrays are acceptable:**
- Bounded to a known maximum (e.g., tags: max 20, addresses: max 5)
- Small element size (ObjectIds, short strings)
- Rarely updated after creation

Reference: [Avoid Unbounded Arrays](https://www.mongodb.com/developer/products/mongodb/schema-design-anti-pattern-massive-arrays/)
