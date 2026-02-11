---
title: Plan Reindex Strategy with Zero-Downtime Alias Switching
impact: CRITICAL
impactDescription: Enables mapping changes, analyzer updates, and shard adjustments without service interruption
tags: mapping, reindex, alias, zero-downtime, migration, schema-evolution
---

## Plan Reindex Strategy with Zero-Downtime Alias Switching

Elasticsearch mappings are mostly immutable after creation. Changing field types, updating analyzers, or adjusting shard counts requires creating a new index and reindexing data. Without an alias-based strategy, this causes downtime.

**Incorrect (direct index name usage — any change requires downtime):**

```json
// Application code references the index name directly
GET /products/_search
{ "query": { "match": { "name": "노트북" } } }

// Need to change a field type: must delete and recreate (data loss!) or reindex with downtime
// Application must be updated to point to new index name
```

**Correct (alias-based workflow — zero-downtime reindexing):**

```json
// Step 1: Create index with version suffix and assign alias
PUT /products-v1
{
  "settings": { "number_of_shards": 3, "number_of_replicas": 1 },
  "mappings": {
    "dynamic": "strict",
    "properties": {
      "name": { "type": "text", "analyzer": "standard" },
      "category": { "type": "keyword" }
    }
  }
}

// Assign read and write aliases
POST /_aliases
{
  "actions": [
    { "add": { "index": "products-v1", "alias": "products" } },
    { "add": { "index": "products-v1", "alias": "products-write" } }
  ]
}

// Application always uses alias — never the actual index name
GET /products/_search
{ "query": { "match": { "name": "노트북" } } }

POST /products-write/_doc
{ "name": "맥북 프로", "category": "laptop" }
```

```json
// Step 2: When mapping change is needed, create new index version
PUT /products-v2
{
  "settings": { "number_of_shards": 5, "number_of_replicas": 1 },
  "mappings": {
    "dynamic": "strict",
    "properties": {
      "name": {
        "type": "text",
        "analyzer": "nori",
        "fields": { "keyword": { "type": "keyword" } }
      },
      "category": { "type": "keyword" },
      "price": { "type": "long" }
    }
  }
}

// Step 3: Reindex data from old to new
POST /_reindex?wait_for_completion=false
{
  "source": { "index": "products-v1" },
  "dest": { "index": "products-v2" }
}

// Monitor reindex progress via task API
GET /_tasks?actions=*reindex&detailed=true
```

```json
// Step 4: Atomic alias switch — zero downtime
POST /_aliases
{
  "actions": [
    { "remove": { "index": "products-v1", "alias": "products" } },
    { "remove": { "index": "products-v1", "alias": "products-write" } },
    { "add": { "index": "products-v2", "alias": "products" } },
    { "add": { "index": "products-v2", "alias": "products-write" } }
  ]
}
// Alias switch is atomic — no request is lost

// Step 5: After verification, delete old index
DELETE /products-v1
```

For large indices, optimize reindex performance:

```json
// Increase scroll size and use sliced scroll for parallelism
POST /_reindex?wait_for_completion=false
{
  "source": {
    "index": "products-v1",
    "size": 5000
  },
  "dest": {
    "index": "products-v2"
  }
}

// Before reindex: disable replicas and increase refresh interval on target
PUT /products-v2/_settings
{
  "index": {
    "number_of_replicas": 0,
    "refresh_interval": "-1"
  }
}

// After reindex: restore settings
PUT /products-v2/_settings
{
  "index": {
    "number_of_replicas": 1,
    "refresh_interval": "1s"
  }
}
```

Reference: [Reindex API](https://www.elastic.co/guide/en/elasticsearch/reference/current/docs-reindex.html), [Index Aliases](https://www.elastic.co/guide/en/elasticsearch/reference/current/indices-aliases.html)
