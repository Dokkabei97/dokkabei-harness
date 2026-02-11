---
title: Configure Database Profiler to Capture Slow Queries
impact: LOW-MEDIUM
impactDescription: Systematic slow query logging for performance analysis and optimization
tags: profiler, slow-query, profiling-level, system-profile, diagnostics
---

## Configure Database Profiler to Capture Slow Queries

The database profiler records detailed information about slow operations in the `system.profile` collection. Use it to systematically identify queries that need optimization.

**Incorrect (profiler on level 2 in production):**

```javascript
// Level 2 profiles ALL operations — massive overhead in production
db.setProfilingLevel(2);
// Writes a document to system.profile for EVERY operation
// 10,000 ops/second = 10,000 profile documents/second — degrades performance
```

**Correct (level 1 with appropriate threshold):**

```javascript
// Level 1: only profile operations slower than the threshold
db.setProfilingLevel(1, { slowms: 100 });  // capture ops > 100ms

// Check current profiling status
db.getProfilingStatus();
// { "was": 1, "slowms": 100, "sampleRate": 1.0 }

// In high-traffic production, use sampling to reduce overhead
db.setProfilingLevel(1, { slowms: 100, sampleRate: 0.1 });  // profile 10% of slow ops

// Query the profiler output for analysis
db.system.profile.find({
  ts: { $gte: new Date(Date.now() - 3600000) },  // last hour
  millis: { $gt: 500 }                             // > 500ms
}).sort({ millis: -1 }).limit(20);

// Find the most common slow query patterns
db.system.profile.aggregate([
  { $match: { ts: { $gte: new Date(Date.now() - 86400000) } } },
  { $group: {
    _id: {
      ns: "$ns",
      op: "$op",
      planSummary: "$planSummary"
    },
    count: { $sum: 1 },
    avgMillis: { $avg: "$millis" },
    maxMillis: { $max: "$millis" }
  }},
  { $sort: { count: -1 } },
  { $limit: 10 }
]);
```

**Profiling levels:**

| Level | Behavior | Use Case |
|---|---|---|
| 0 | Off | Production (use log-based analysis) |
| 1 | Slow operations only | Production debugging, optimization |
| 2 | All operations | Development, short-term troubleshooting |

Disable profiling when done troubleshooting:

```javascript
db.setProfilingLevel(0);
db.system.profile.drop();  // clean up profile data
```

Reference: [Database Profiler](https://www.mongodb.com/docs/manual/tutorial/manage-the-database-profiler/)
