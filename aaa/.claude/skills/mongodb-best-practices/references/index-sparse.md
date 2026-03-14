---
title: Use Sparse Indexes for Optional Fields
impact: MEDIUM-HIGH
impactDescription: 50-80% smaller index when most documents lack the field
tags: sparse-index, optional-fields, null-values, index-size
---

## Use Sparse Indexes for Optional Fields

Sparse indexes only contain entries for documents that have the indexed field. For fields that exist on a small percentage of documents, sparse indexes are significantly smaller.

**Incorrect (regular index includes null entries):**

```javascript
// Only 5% of users have a linkedInProfile field
// Regular index stores null entry for the other 95%
db.users.createIndex({ linkedInProfile: 1 });
// Index size: 200MB (95% null entries are wasted space)
```

**Correct (sparse index skips documents without the field):**

```javascript
// Sparse index only includes documents where linkedInProfile exists
db.users.createIndex({ linkedInProfile: 1 }, { sparse: true });
// Index size: 10MB (95% reduction)
```

Important caveats:
- Sparse indexes will NOT be used for queries that can match documents where the field doesn't exist
- `sort()` operations may skip documents without the field when using a sparse index
- Consider partial indexes for more control over which documents are indexed

```javascript
// Partial index alternative (more explicit)
db.users.createIndex(
  { linkedInProfile: 1 },
  { partialFilterExpression: { linkedInProfile: { $exists: true } } }
);
```

Reference: [Sparse Indexes](https://www.mongodb.com/docs/manual/core/index-sparse/)
