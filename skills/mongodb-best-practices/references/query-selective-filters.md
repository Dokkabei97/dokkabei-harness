---
title: Place Selective Filters First in Compound Queries
impact: CRITICAL
impactDescription: 5-50x fewer documents examined with selective filters
tags: selectivity, compound-query, filter-order, performance
---

## Place Selective Filters First in Compound Queries

Query efficiency depends on selectivity — how quickly a filter narrows down results. Place the most selective field first in compound indexes and queries.

**Incorrect (low selectivity field first):**

```javascript
// Index: { isActive: 1, email: 1 }
// isActive has only 2 values (true/false) — low selectivity
db.users.find({ isActive: true, email: "user@example.com" });
// Scans 5M active users to find 1 matching email
```

**Correct (high selectivity field first):**

```javascript
// Index: { email: 1, isActive: 1 }
// email is nearly unique — high selectivity
db.users.find({ isActive: true, email: "user@example.com" });
// Immediately finds the 1 matching email, then checks isActive
```

Use `explain("executionStats")` to compare `totalKeysExamined` and `totalDocsExamined` between different index strategies.

Reference: [Query Selectivity](https://www.mongodb.com/docs/manual/core/query-optimization/#query-selectivity)
