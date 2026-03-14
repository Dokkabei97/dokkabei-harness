---
title: Choose Embedding vs Referencing Based on Relationship Cardinality
impact: CRITICAL
impactDescription: 10-100x read performance difference with correct modeling choice
tags: embedding, referencing, data-model, cardinality, schema-design
---

## Choose Embedding vs Referencing Based on Relationship Cardinality

The most critical MongoDB schema decision. Embedding stores related data within a single document (fast reads, atomic updates). Referencing stores data in separate collections (flexible, avoids duplication). Choose based on cardinality and access patterns.

**Incorrect (referencing for 1:Few that's always fetched together):**

```javascript
// User and their address stored separately — requires $lookup for every read
// user: { _id: 1, name: "Kim", addressId: ObjectId("...") }
// address: { _id: ObjectId("..."), street: "Gangnam-daero", city: "Seoul" }

db.users.aggregate([
  { $match: { _id: 1 } },
  { $lookup: { from: "addresses", localField: "addressId", foreignField: "_id", as: "address" } }
]);
// 2 collection reads, $lookup overhead, cannot be a covered query
```

**Correct (embedding for 1:Few with co-located access):**

```javascript
// Embed address directly in the user document
db.users.insertOne({
  _id: 1,
  name: "Kim",
  address: { street: "Gangnam-daero", city: "Seoul", country: "KR" }
});

db.users.find({ _id: 1 });
// Single document read, no $lookup — 10x faster
```

**Decision guide:**

| Relationship | Pattern | Example |
|---|---|---|
| 1:1 | Embed | User <-> Profile |
| 1:Few (< 100) | Embed | Blog <-> Comments (few) |
| 1:Many (100-1000s) | Reference (child->parent) | Author <-> Books |
| 1:Millions | Reference (parent->child IDs forbidden) | City <-> People |
| Many:Many | Reference | Students <-> Courses |

Reference: [Data Model Design](https://www.mongodb.com/docs/manual/core/data-model-design/)
