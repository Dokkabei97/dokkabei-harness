---
title: Always Define Explicit Mappings Instead of Dynamic
impact: CRITICAL
impactDescription: Prevents mapping explosion and wrong type inference on production indices
tags: mapping, dynamic-mapping, schema-design
---

## Always Define Explicit Mappings Instead of Dynamic

Dynamic mapping guesses field types from the first document indexed. Strings become both `text` and `keyword` (doubling storage), numbers may be `long` when `integer` suffices, and unknown fields silently create new mappings that can lead to mapping explosion (1000+ fields crashing the cluster).

**Incorrect (relying on dynamic mapping):**

```json
// No predefined mapping → ES guesses types from first document
// "price": "29.99" (string) → mapped as text+keyword instead of double
// Every new field in future documents creates a new mapping entry
POST /products/_doc
{
  "name": "Wireless Headphones",
  "price": "29.99",
  "status": "active",
  "metadata": {
    "color": "black",
    "weight_g": 250
  }
}
```

**Correct (explicit mapping with dynamic: strict):**

```json
// Define all fields upfront → correct types, no surprises
// dynamic: strict → rejects documents with unmapped fields
PUT /products
{
  "mappings": {
    "dynamic": "strict",
    "properties": {
      "name": { "type": "text" },
      "price": { "type": "double" },
      "status": { "type": "keyword" },
      "category": { "type": "keyword" },
      "description": { "type": "text" },
      "created_at": { "type": "date", "format": "yyyy-MM-dd'T'HH:mm:ss.SSSZ||epoch_millis" },
      "metadata": {
        "type": "object",
        "properties": {
          "color": { "type": "keyword" },
          "weight_g": { "type": "integer" }
        }
      }
    }
  }
}
```

**Dynamic mapping options for production:**

| Setting | Behavior | Use Case |
|---------|----------|----------|
| `"strict"` | Reject unknown fields (400 error) | Production indices — safest |
| `false` | Accept but don't index unknown fields | Logging with passthrough fields |
| `true` (default) | Auto-create mappings | Development/exploration only |
| `"runtime"` | Create runtime fields for unknowns | Flexible schema with no index cost |

For indices that receive data from multiple sources, always set `dynamic: "strict"` to catch schema mismatches early rather than silently creating wrong mappings.

Reference: [Dynamic mapping](https://www.elastic.co/guide/en/elasticsearch/reference/current/dynamic-mapping.html)
