---
title: Use currentOp to Identify and Kill Slow or Blocking Operations
impact: LOW-MEDIUM
impactDescription: Real-time visibility into active operations for immediate troubleshooting
tags: currentOp, slow-queries, blocking-operations, diagnostics, kill-operation
---

## Use currentOp to Identify and Kill Slow or Blocking Operations

`db.currentOp()` shows all currently running operations on the MongoDB server. Use it to identify long-running queries, blocking operations, and resource-intensive aggregations in real-time.

**Incorrect (restarting server to fix a stuck query):**

```javascript
// "Database is slow and unresponsive"
// Restarting mongod kills ALL operations and disconnects ALL clients — overkill
```

**Correct (identify and surgically kill problematic operations):**

```javascript
// 1. Find all operations running longer than 10 seconds
db.currentOp({
  "active": true,
  "secs_running": { $gt: 10 },
  "op": { $ne: "none" }
});

// 2. Filter for specific patterns — find slow queries on a collection
db.currentOp({
  "active": true,
  "secs_running": { $gt: 30 },
  "ns": "myApp.orders",         // specific namespace
  "op": { $in: ["query", "update", "command"] }
});

// 3. Identify the problematic operation from the output
// {
//   "opid": 12345,
//   "active": true,
//   "secs_running": 120,
//   "op": "query",
//   "ns": "myApp.orders",
//   "command": { "find": "orders", "filter": { "status": "pending" } },
//   "planSummary": "COLLSCAN",    // missing index!
//   "numYields": 50000,
//   "waitingForLock": false
// }

// 4. Kill the specific operation
db.killOp(12345);

// 5. Find waiting/blocked operations
db.currentOp({ "waitingForLock": true });

// 6. Use $currentOp aggregation for more flexibility
db.adminCommand({
  aggregate: 1,
  pipeline: [
    { $currentOp: { allUsers: true, idleSessions: false } },
    { $match: { active: true, secs_running: { $gt: 5 } } },
    { $sort: { secs_running: -1 } },
    { $project: { opid: 1, secs_running: 1, op: 1, ns: 1, planSummary: 1 } }
  ],
  cursor: {}
});
```

Set `maxTimeMS` on queries to prevent runaway operations:

```javascript
db.orders.find({ status: "pending" }).maxTimeMS(30000);  // auto-kill after 30s
```

Reference: [currentOp](https://www.mongodb.com/docs/manual/reference/method/db.currentOp/)
