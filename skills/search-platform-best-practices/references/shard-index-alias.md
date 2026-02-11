---
title: Always Use Index Aliases — Never Reference Index Names Directly
impact: HIGH
impactDescription: Enables zero-downtime reindexing, rollover, and index swapping without application changes
tags: shard, alias, index, zero-downtime, abstraction, routing
---

## Always Use Index Aliases — Never Reference Index Names Directly

Hardcoding index names in application code prevents zero-downtime reindexing, rollover, and migration. Aliases provide a layer of indirection that decouples applications from physical index names.

**Incorrect (application uses physical index names):**

```json
// Application code references physical index name
GET /products-v1/_search
{ "query": { "match": { "name": "노트북" } } }

POST /products-v1/_doc
{ "name": "맥북", "price": 2000000 }

// When reindexing to products-v2:
// 1. Must update every application that references "products-v1"
// 2. Deploy application changes
// 3. Brief period where some apps point to v1, others to v2
```

**Correct (application uses aliases):**

```json
// Create index with alias
PUT /products-v1
{
  "aliases": {
    "products-read": {},
    "products-write": { "is_write_index": true }
  }
}

// Application always uses aliases
GET /products-read/_search
{ "query": { "match": { "name": "노트북" } } }

POST /products-write/_doc
{ "name": "맥북", "price": 2000000 }

// Reindex to v2 and atomic switch — application code unchanged
POST /_aliases
{
  "actions": [
    { "remove": { "index": "products-v1", "alias": "products-read" } },
    { "remove": { "index": "products-v1", "alias": "products-write" } },
    { "add": { "index": "products-v2", "alias": "products-read" } },
    { "add": { "index": "products-v2", "alias": "products-write", "is_write_index": true } }
  ]
}
// Atomic operation — no request is lost, no application deployment needed
```

Advanced alias features:

```json
// Filtered alias — pre-filter results for specific tenants
POST /_aliases
{
  "actions": [
    {
      "add": {
        "index": "orders",
        "alias": "orders-kr",
        "filter": { "term": { "region": "kr" } }
      }
    }
  ]
}
// GET /orders-kr/_search only returns Korean region orders

// Routing alias — direct writes/reads to specific shard
POST /_aliases
{
  "actions": [
    {
      "add": {
        "index": "users",
        "alias": "users-tenant-a",
        "filter": { "term": { "tenant_id": "a" } },
        "routing": "tenant-a"
      }
    }
  ]
}

// Multi-index alias for searching across index versions
POST /_aliases
{
  "actions": [
    { "add": { "index": "logs-2024-01", "alias": "logs-recent" } },
    { "add": { "index": "logs-2024-02", "alias": "logs-recent" } },
    { "add": { "index": "logs-2024-03", "alias": "logs-recent" } }
  ]
}
```

Alias naming convention:

| Purpose | Alias Name | Example |
|---------|-----------|---------|
| Read access | `{resource}-read` | `products-read` |
| Write access | `{resource}-write` | `products-write` |
| Unified access | `{resource}` | `products` |
| Tenant-filtered | `{resource}-{tenant}` | `orders-kr` |
| Time-windowed | `{resource}-recent` | `logs-recent` |

Reference: [Index aliases](https://www.elastic.co/guide/en/elasticsearch/reference/current/indices-aliases.html)
