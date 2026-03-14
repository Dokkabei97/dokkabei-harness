---
title: Use Covered Queries to Avoid Document Fetches
impact: CRITICAL
impactDescription: 2-5x faster queries by serving results entirely from index
tags: covered-query, projection, index, performance
---

## Use Covered Queries to Avoid Document Fetches

A covered query is satisfied entirely by the index without needing to examine any documents. This eliminates the document fetch stage, dramatically reducing I/O.

**Incorrect (fetching all fields forces document access):**

```javascript
// Index: { status: 1, email: 1 }
// Query returns all fields — must read documents from disk
db.users.find({ status: "active" });
// explain: totalDocsExamined = 50000, FETCH stage present
```

**Correct (projection limits to indexed fields only):**

```javascript
// Index: { status: 1, email: 1 }
// Only return fields in the index + exclude _id
db.users.find(
  { status: "active" },
  { status: 1, email: 1, _id: 0 }
);
// explain: totalDocsExamined = 0, no FETCH stage — covered query!
```

Note: `_id` is included by default. Exclude it with `_id: 0` unless it's part of the index. Covered queries work best with compound indexes designed for specific query patterns.

Reference: [Covered Query](https://www.mongodb.com/docs/manual/core/query-optimization/#covered-query)
