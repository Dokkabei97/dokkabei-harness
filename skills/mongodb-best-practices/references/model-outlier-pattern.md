---
title: Handle Outlier Documents with Overflow Strategy
impact: MEDIUM-HIGH
impactDescription: Prevents performance degradation from abnormal documents while keeping normal path fast
tags: outlier-pattern, overflow, celebrity-problem, bounded-arrays, schema-design
---

## Handle Outlier Documents with Overflow Strategy

The Outlier Pattern handles documents that deviate significantly from the norm (e.g., a celebrity with millions of followers vs. average users with hundreds). Optimize for the common case while accommodating outliers with an overflow mechanism.

**Incorrect (designing for outliers penalizes all documents):**

```javascript
// Designing for the worst case — separate collection for ALL users' followers
// Even users with 5 followers now require a $lookup
db.follows.find({ followeeId: userId }).sort({ createdAt: -1 }).limit(20);
// This works but is slower than embedding for the 99% of users with < 100 followers
```

**Correct (embed for normal case, overflow for outliers):**

```javascript
// Normal users: embed followers directly (fast single-document read)
db.users.insertOne({
  _id: "normal_user",
  name: "Park Jisu",
  followers: [
    { userId: "u1", followedAt: new Date() },
    { userId: "u2", followedAt: new Date() }
  ],
  followerCount: 2,
  hasOverflow: false  // no overflow document needed
});

// Celebrity users: embed first batch, overflow the rest
db.users.insertOne({
  _id: "celebrity",
  name: "Top Star",
  followers: [/* first 500 followers */],
  followerCount: 2500000,
  hasOverflow: true  // flag indicating overflow exists
});

// Overflow documents in a separate collection
db.userFollowersOverflow.insertOne({
  userId: "celebrity",
  page: 1,
  followers: [/* next 10,000 followers */]
});

// Application logic checks the flag
async function getFollowers(userId) {
  const user = await db.users.findOne({ _id: userId });

  if (!user.hasOverflow) {
    return user.followers;  // fast path — 99% of users
  }

  // Slow path for outliers — query overflow collection
  return db.userFollowersOverflow
    .find({ userId })
    .sort({ page: 1 })
    .toArray();
}
```

This pattern keeps the common read path fast (single document read for 99% of users) while gracefully handling extreme cases. The `hasOverflow` flag avoids unnecessary queries on the overflow collection.

Reference: [Outlier Pattern](https://www.mongodb.com/blog/post/building-with-patterns-the-outlier-pattern)
