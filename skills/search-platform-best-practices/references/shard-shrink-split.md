---
title: Use Shrink and Split APIs for Post-Hoc Shard Count Adjustment
impact: MEDIUM
impactDescription: Fixes over-sharding or under-sharding without full reindex
tags: shard, shrink, split, adjustment, post-hoc, optimization
---

## Use Shrink and Split APIs for Post-Hoc Shard Count Adjustment

If an index was created with too many or too few primary shards, the Shrink and Split APIs can adjust the shard count without a full reindex. Shrink reduces shards (must be a factor), Split increases them (must be a multiple).

**Incorrect (reindexing just to change shard count):**

```json
// Index has 12 shards but data is only 15GB → over-sharded
// Full reindex is slow and resource-intensive for large indices
POST /_reindex
{
  "source": { "index": "products-v1" },
  "dest": { "index": "products-v2" }
}
// Copies every document — unnecessary when only shard count needs to change
```

**Correct (Shrink API to reduce shards):**

```json
// Step 1: Block writes and relocate all shards to a single node
PUT /products-v1/_settings
{
  "settings": {
    "index.routing.allocation.require._name": "data-hot-1",
    "index.blocks.write": true
  }
}

// Step 2: Shrink from 12 shards to 3 (12 is divisible by 3)
POST /products-v1/_shrink/products-v1-shrunk
{
  "settings": {
    "index.number_of_shards": 3,
    "index.number_of_replicas": 1,
    "index.routing.allocation.require._name": null,
    "index.blocks.write": null
  }
}

// Step 3: Switch alias to the shrunk index
POST /_aliases
{
  "actions": [
    { "remove": { "index": "products-v1", "alias": "products" } },
    { "add": { "index": "products-v1-shrunk", "alias": "products" } }
  ]
}
```

**Correct (Split API to increase shards):**

```json
// Index has 2 shards but data grew to 300GB → under-sharded
// Split requires the target to be a multiple of the source

// Step 1: Block writes
PUT /logs-v1/_settings
{
  "index.blocks.write": true
}

// Step 2: Split from 2 to 6 shards (2 × 3 = 6)
POST /logs-v1/_split/logs-v1-split
{
  "settings": {
    "index.number_of_shards": 6,
    "index.number_of_replicas": 1,
    "index.blocks.write": null
  }
}

// Step 3: Switch alias
POST /_aliases
{
  "actions": [
    { "remove": { "index": "logs-v1", "alias": "logs" } },
    { "add": { "index": "logs-v1-split", "alias": "logs" } }
  ]
}
```

Constraints:

| API | Requirement | Example |
|-----|-------------|---------|
| Shrink | Target must be a factor of source | 12 → 6, 4, 3, 2, 1 |
| Split | Target must be a multiple of source | 2 → 4, 6, 8, 10 |
| Split | `index.number_of_routing_shards` must be set at creation | Set in advance |

Both APIs create hard links (no data copying), so they are much faster than reindex. However, they require the index to be read-only during the operation.

Reference: [Shrink API](https://www.elastic.co/guide/en/elasticsearch/reference/current/indices-shrink-index.html), [Split API](https://www.elastic.co/guide/en/elasticsearch/reference/current/indices-split-index.html)
