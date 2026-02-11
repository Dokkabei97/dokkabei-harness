---
title: Always Use Projection to Return Only Needed Fields
impact: CRITICAL
impactDescription: 3-10x reduction in network bandwidth and memory usage
tags: projection, bandwidth, performance, memory
---

## Always Use Projection to Return Only Needed Fields

Returning entire documents when only a few fields are needed wastes network bandwidth, memory, and processing time. Always project only the fields you need.

**Incorrect (returning entire documents):**

```javascript
// Returns all fields including large nested arrays and text content
db.articles.find({ category: "tech" });
// Each document is 50KB — transferring 50,000 docs = 2.5GB network traffic
```

**Correct (project only needed fields):**

```javascript
// Return only required fields
db.articles.find(
  { category: "tech" },
  { title: 1, author: 1, publishedAt: 1, _id: 1 }
);
// Each result is ~200 bytes — 50,000 docs = 10MB network traffic (250x less)
```

For nested documents, use dot notation to project specific sub-fields:

```javascript
db.users.find(
  { status: "active" },
  { "name": 1, "address.city": 1, "address.country": 1 }
);
```

Reference: [Project Fields to Return](https://www.mongodb.com/docs/manual/tutorial/project-fields-from-query-results/)
