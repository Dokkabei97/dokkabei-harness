---
title: Anchor Regex Patterns with ^ for Index Utilization
impact: CRITICAL
impactDescription: 100x+ faster regex queries with anchored patterns
tags: regex, index, collscan, performance
---

## Anchor Regex Patterns with ^ for Index Utilization

Unanchored regex patterns (without `^`) cannot use indexes and force a full collection scan (COLLSCAN). Always anchor regex patterns at the start when possible.

**Incorrect (unanchored regex forces COLLSCAN):**

```javascript
// Index: { email: 1 }
// Regex without ^ anchor — cannot use index
db.users.find({ email: { $regex: "gmail.com" } });
// explain: stage = COLLSCAN, scans ALL 10M documents
```

**Correct (anchored regex uses IXSCAN):**

```javascript
// Index: { email: 1 }
// Regex with ^ anchor — uses index for prefix matching
db.users.find({ email: { $regex: "^admin@" } });
// explain: stage = IXSCAN, scans only matching prefix range
```

If you need case-insensitive prefix search, combine with collation:

```javascript
db.users.createIndex({ email: 1 }, { collation: { locale: "en", strength: 2 } });
db.users.find({ email: { $regex: "^admin@" } }).collation({ locale: "en", strength: 2 });
```

For arbitrary substring search, consider Atlas Search or a text index instead of $regex.

Reference: [Regex and Index Use](https://www.mongodb.com/docs/manual/reference/operator/query/regex/#index-use)
