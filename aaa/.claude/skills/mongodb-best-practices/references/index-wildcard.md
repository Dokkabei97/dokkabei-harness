---
title: Use Wildcard Indexes for Dynamic or Unpredictable Query Patterns
impact: MEDIUM
impactDescription: Index coverage for dynamic schemas without pre-defining every field
tags: wildcard-index, dynamic-schema, flexible-queries
---

## Use Wildcard Indexes for Dynamic or Unpredictable Query Patterns

Wildcard indexes automatically index all fields (or a subset) in a document. Useful for collections with dynamic or polymorphic schemas where query patterns are unpredictable.

**Incorrect (no index on dynamic metadata fields):**

```javascript
// Products have varying metadata fields per category
// { category: "electronics", metadata: { brand: "Samsung", watts: 100, voltage: 220 } }
// { category: "clothing", metadata: { brand: "Nike", size: "L", color: "blue" } }
// Cannot pre-define indexes for every possible metadata field
db.products.find({ "metadata.brand": "Samsung" });
// COLLSCAN — no index
```

**Correct (wildcard index on metadata):**

```javascript
// Wildcard index covers all sub-fields in metadata
db.products.createIndex({ "metadata.$**": 1 });

db.products.find({ "metadata.brand": "Samsung" });  // IXSCAN ✓
db.products.find({ "metadata.color": "blue" });      // IXSCAN ✓
db.products.find({ "metadata.watts": { $gt: 50 } }); // IXSCAN ✓
```

Limitations:
- Wildcard indexes cannot support compound index patterns
- Cannot be used as a shard key
- Not suitable for known, stable query patterns (use regular compound indexes)
- Cannot support sort operations efficiently

```javascript
// Full collection wildcard (use with caution on large collections)
db.products.createIndex({ "$**": 1 });
```

Reference: [Wildcard Indexes](https://www.mongodb.com/docs/manual/core/index-wildcard/)
