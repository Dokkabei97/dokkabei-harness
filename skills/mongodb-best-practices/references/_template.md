---
title: Clear, Action-Oriented Title (e.g., "Follow the ESR Rule for Compound Index Field Order")
impact: MEDIUM
impactDescription: 5-20x query speedup for filtered queries
tags: indexes, query-optimization, performance
---

## [Rule Title]

[1-2 sentence explanation of the problem and why it matters. Focus on performance impact.]

**Incorrect (describe the problem):**

```javascript
// Comment explaining what makes this slow/problematic
db.orders.find({ status: "pending", createdAt: { $gt: new Date("2024-01-01") } });
// No index - performs a full collection scan (COLLSCAN)
```

**Correct (describe the solution):**

```javascript
// Comment explaining why this is better
db.orders.createIndex({ status: 1, createdAt: 1 });

db.orders.find({ status: "pending", createdAt: { $gt: new Date("2024-01-01") } });
// Uses IXSCAN - 10x faster on large collections
```

[Optional: Additional context, edge cases, or trade-offs]

Reference: [MongoDB Docs](https://www.mongodb.com/docs/manual/)
