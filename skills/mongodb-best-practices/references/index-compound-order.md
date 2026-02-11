---
title: Design Compound Index Field Order Based on Query Patterns
impact: CRITICAL
impactDescription: 5-20x performance difference with correct field ordering
tags: compound-index, field-order, leftmost-prefix, performance
---

## Design Compound Index Field Order Based on Query Patterns

MongoDB uses the leftmost prefix of compound indexes. Field order determines which queries can use the index. Design indexes based on actual query patterns.

**Incorrect (index not matching query pattern):**

```javascript
// Index: { country: 1, city: 1, zipCode: 1 }
db.addresses.find({ city: "Seoul" });
// Cannot use index! city is not the leftmost prefix
// explain: COLLSCAN
```

**Correct (leftmost prefix matches query):**

```javascript
// Index: { city: 1, country: 1, zipCode: 1 }
db.addresses.find({ city: "Seoul" });
// Uses leftmost prefix — IXSCAN on city

// Also works for:
db.addresses.find({ city: "Seoul", country: "KR" });
// Uses first two fields of the index

// Also works for:
db.addresses.find({ city: "Seoul", country: "KR", zipCode: "06164" });
// Uses all three fields

// Does NOT work for:
db.addresses.find({ zipCode: "06164" });
// zipCode alone is not a prefix — COLLSCAN
```

Design compound indexes to support the most common query patterns. A single well-designed compound index can serve multiple queries via prefix matching.

Reference: [Compound Indexes](https://www.mongodb.com/docs/manual/core/indexes/index-types/index-compound/)
