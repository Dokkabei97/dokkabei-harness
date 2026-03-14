---
title: Use explain() to Identify and Fix Slow Query Patterns
impact: LOW-MEDIUM
impactDescription: Pinpoints COLLSCAN, excess document examination, and missing indexes
tags: explain, execution-stats, collscan, query-plan, diagnostics
---

## Use explain() to Identify and Fix Slow Query Patterns

The `explain()` method reveals how MongoDB executes a query — which index it uses (or doesn't), how many documents it examines, and whether it performs in-memory sorts. Essential for query performance tuning.

**Incorrect (guessing at performance problems):**

```javascript
// "The query is slow" — but why?
db.orders.find({ status: "pending", total: { $gt: 10000 } }).sort({ createdAt: -1 });
// Is it a missing index? Bad index choice? In-memory sort? No way to know without explain
```

**Correct (use explain to diagnose and fix):**

```javascript
// Run explain with executionStats for detailed metrics
db.orders.find({ status: "pending", total: { $gt: 10000 } })
  .sort({ createdAt: -1 })
  .explain("executionStats");

// Key metrics to check:
// {
//   "executionStats": {
//     "executionTimeMillis": 2340,      // total execution time
//     "totalKeysExamined": 0,           // 0 = no index used!
//     "totalDocsExamined": 5000000,     // scanned 5M docs — BAD
//     "nReturned": 150,                 // only 150 results needed
//     "executionStages": {
//       "stage": "COLLSCAN",            // full collection scan — CRITICAL issue
//       "inputStage": {
//         "stage": "SORT",              // in-memory sort — secondary issue
//         "memLimit": 104857600
//       }
//     }
//   }
// }

// Red flags to look for:
// 1. stage: "COLLSCAN" — no index, add one
// 2. totalDocsExamined >> nReturned — index not selective enough
// 3. stage: "SORT" without "SORT_MERGE" — in-memory sort, fix index
// 4. totalKeysExamined >> totalDocsExamined — index scanning too many keys

// Fix: create compound index following ESR rule
db.orders.createIndex({ status: 1, createdAt: -1, total: 1 });

// Verify fix with explain again
db.orders.find({ status: "pending", total: { $gt: 10000 } })
  .sort({ createdAt: -1 })
  .explain("executionStats");
// Now: IXSCAN, totalDocsExamined ≈ nReturned, no SORT stage
```

Use `"allPlansExecution"` to see rejected query plans and understand why a specific index was chosen.

Reference: [Explain Results](https://www.mongodb.com/docs/manual/reference/explain-results/)
