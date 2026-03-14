---
title: Use nested Only When Cross-Field Correlation Required
impact: HIGH
impactDescription: nested is 3-5x slower than object; use only when field correlation matters
tags: mapping, nested, object, denormalization
---

## Use nested Only When Cross-Field Correlation Required

`object` type flattens array elements, losing correlation between fields within the same array entry. `nested` preserves correlation by storing each entry as a separate hidden document, but at significant cost: 3-5x slower queries, higher memory usage, and a default limit of 50 nested documents per parent.

**Incorrect (nested for simple key-value pairs that don't need correlation):**

```json
// Unnecessary nested type → hidden documents created for each tag
// 100M products x 5 tags = 500M hidden docs → massive overhead
PUT /products
{
  "mappings": {
    "properties": {
      "tags": {
        "type": "nested",
        "properties": {
          "key": { "type": "keyword" },
          "value": { "type": "keyword" }
        }
      }
    }
  }
}
```

**Correct (object by default, nested only for cross-field correlation):**

```json
// tags: no correlation needed → object type (default)
// variants: must correlate size WITH color → nested type
PUT /products
{
  "mappings": {
    "properties": {
      "name": { "type": "text" },
      "tags": {
        "type": "object",
        "properties": {
          "key": { "type": "keyword" },
          "value": { "type": "keyword" }
        }
      },
      "variants": {
        "type": "nested",
        "properties": {
          "size": { "type": "keyword" },
          "color": { "type": "keyword" },
          "stock": { "type": "integer" }
        }
      }
    }
  }
}
```

**Why correlation matters — the cross-match problem:**

```json
// Document: { "variants": [{"size":"L","color":"red"}, {"size":"S","color":"blue"}] }

// With object type (flattened): variants.size=["L","S"], variants.color=["red","blue"]
// Query "size=L AND color=blue" → MATCHES (wrong! no L+blue variant exists)

// With nested type: each variant is a separate hidden doc
// Query "size=L AND color=blue" → NO MATCH (correct)
GET /products/_search
{
  "query": {
    "nested": {
      "path": "variants",
      "query": {
        "bool": {
          "must": [
            { "term": { "variants.size": "L" } },
            { "term": { "variants.color": "blue" } }
          ]
        }
      }
    }
  }
}
```

**Decision guide:** If you only filter on individual fields within the array (e.g., "any variant with size=L"), `object` type is sufficient and far more efficient. Use `nested` only when you must match combinations across fields within the same array element.

Reference: [Nested field type](https://www.elastic.co/guide/en/elasticsearch/reference/current/nested.html)
