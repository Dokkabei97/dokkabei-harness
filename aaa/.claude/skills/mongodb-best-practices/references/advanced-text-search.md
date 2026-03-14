---
title: Choose Text Indexes vs Atlas Search for Full-Text Search
impact: LOW
impactDescription: Correct search technology selection based on complexity requirements
tags: text-index, atlas-search, full-text-search, lucene, search
---

## Choose Text Indexes vs Atlas Search for Full-Text Search

MongoDB offers two approaches to full-text search: built-in text indexes (simple, limited) and Atlas Search (Lucene-powered, feature-rich). Choose based on your search requirements.

**Incorrect (using $regex for full-text search):**

```javascript
// $regex for word search — cannot use index, no relevance scoring
db.articles.find({ content: { $regex: "mongodb.*performance", $options: "i" } });
// COLLSCAN on every query, no word boundary matching, no ranking
// Searching 1M articles takes 30+ seconds
```

**Correct (text index for simple search):**

```javascript
// Built-in text index — good for basic keyword search
db.articles.createIndex({ title: "text", content: "text", tags: "text" }, {
  weights: { title: 10, tags: 5, content: 1 },  // title matches rank higher
  default_language: "english"
});

db.articles.find(
  { $text: { $search: "mongodb performance tuning" } },
  { score: { $meta: "textScore" } }
).sort({ score: { $meta: "textScore" } }).limit(20);
// Uses text index, returns results ranked by relevance
```

**Correct (Atlas Search for advanced requirements):**

```javascript
// Atlas Search — Lucene-powered, supports fuzzy matching, autocomplete, facets
// Define search index in Atlas UI or via API:
// {
//   "mappings": {
//     "dynamic": false,
//     "fields": {
//       "title": { "type": "string", "analyzer": "lucene.korean" },
//       "content": { "type": "string", "analyzer": "lucene.korean" },
//       "category": { "type": "stringFacet" }
//     }
//   }
// }

db.articles.aggregate([
  { $search: {
    index: "articles_search",
    compound: {
      must: [{ text: { query: "MongoDB 성능", path: ["title", "content"] } }],
      should: [{ text: { query: "인덱스 최적화", path: "content", score: { boost: { value: 2 } } } }]
    },
    highlight: { path: ["title", "content"] }
  }},
  { $project: {
    title: 1,
    score: { $meta: "searchScore" },
    highlights: { $meta: "searchHighlights" }
  }},
  { $limit: 20 }
]);
```

**When to use which:**

| Feature | Text Index | Atlas Search |
|---|---|---|
| Setup | Self-managed | Atlas only |
| Fuzzy matching | No | Yes |
| Autocomplete | No | Yes |
| Faceted search | No | Yes |
| Custom analyzers | Limited | Full Lucene |
| Korean language | Basic | Full support |
| Cost | Free | Atlas tier pricing |

Reference: [Text Indexes](https://www.mongodb.com/docs/manual/core/index-text/) | [Atlas Search](https://www.mongodb.com/docs/atlas/atlas-search/)
