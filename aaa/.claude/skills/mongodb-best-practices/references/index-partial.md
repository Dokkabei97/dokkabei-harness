---
title: Use Partial Indexes to Reduce Index Size and Write Overhead
impact: CRITICAL
impactDescription: 50-90% smaller indexes, faster writes, same query performance
tags: partial-index, filter-expression, index-size, performance
---

## Use Partial Indexes to Reduce Index Size and Write Overhead

Partial indexes only index documents matching a filter expression. For queries that always include the same filter, partial indexes are dramatically smaller and faster to maintain.

**Incorrect (full index on all documents):**

```javascript
// Index includes all 10M documents including 8M soft-deleted ones
db.users.createIndex({ email: 1 });
// Index size: 400MB, includes inactive/deleted users
```

**Correct (partial index on active documents only):**

```javascript
// Only index active users — 2M out of 10M documents
db.users.createIndex(
  { email: 1 },
  { partialFilterExpression: { deletedAt: null, isActive: true } }
);
// Index size: 80MB (80% smaller), faster writes for deleted/inactive users
```

Important: queries must include the partial filter expression to use the index:

```javascript
// ✓ Uses partial index (filter matches partialFilterExpression)
db.users.find({ email: "user@example.com", deletedAt: null, isActive: true });

// ✗ Cannot use partial index (missing isActive filter)
db.users.find({ email: "user@example.com" });
```

Reference: [Partial Indexes](https://www.mongodb.com/docs/manual/core/index-partial/)
