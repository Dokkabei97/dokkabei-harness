---
title: Use Nested Type to Prevent Cross-Object Matching on Array of Objects
impact: CRITICAL
impactDescription: Eliminates false-positive matches that return incorrect results
tags: mapping, nested, object, array, cross-object, correctness
---

## Use Nested Type to Prevent Cross-Object Matching on Array of Objects

When an array of objects is mapped as the default `object` type, Elasticsearch flattens the inner objects, losing the association between fields within each object. This causes cross-object matching where a query matches field values from different objects in the array.

**Incorrect (object type loses field associations):**

```json
PUT /products
{
  "mappings": {
    "properties": {
      "name": { "type": "text" },
      "options": {
        "type": "object",
        "properties": {
          "color": { "type": "keyword" },
          "size": { "type": "keyword" }
        }
      }
    }
  }
}

POST /products/_doc/1
{
  "name": "티셔츠",
  "options": [
    { "color": "red", "size": "S" },
    { "color": "blue", "size": "XL" }
  ]
}
// Internally flattened to: options.color: ["red", "blue"], options.size: ["S", "XL"]

// This query INCORRECTLY matches — there is no red/XL combination
GET /products/_search
{
  "query": {
    "bool": {
      "must": [
        { "term": { "options.color": "red" } },
        { "term": { "options.size": "XL" } }
      ]
    }
  }
}
// Returns the document even though red+XL does not exist as a pair!
```

**Correct (nested type preserves object boundaries):**

```json
PUT /products
{
  "mappings": {
    "properties": {
      "name": { "type": "text" },
      "options": {
        "type": "nested",
        "properties": {
          "color": { "type": "keyword" },
          "size": { "type": "keyword" }
        }
      }
    }
  }
}

// Each inner object is indexed as a separate hidden document
GET /products/_search
{
  "query": {
    "nested": {
      "path": "options",
      "query": {
        "bool": {
          "must": [
            { "term": { "options.color": "red" } },
            { "term": { "options.size": "XL" } }
          ]
        }
      }
    }
  }
}
// Correctly returns NO results — red+XL pair does not exist
```

When to use each type:

| Scenario | Type | Reason |
|----------|------|--------|
| Simple key-value metadata | `object` | No cross-field correlation needed |
| Single nested object (not array) | `object` | No cross-matching risk |
| Array of objects with correlated fields | `nested` | Preserves field associations |
| Very high cardinality arrays (100+ items) | Consider `flattened` or denormalization | Nested creates a hidden doc per item, impacting performance |

Performance considerations:
- Each nested object creates a hidden Lucene document (index.mapping.nested_objects.limit defaults to 10,000)
- Nested queries are slower than object queries due to join logic
- Use `include_in_parent: true` or `include_in_root: true` to enable both nested and non-nested queries on the same field (at the cost of increased index size)

Reference: [Nested field type](https://www.elastic.co/guide/en/elasticsearch/reference/current/nested.html)
