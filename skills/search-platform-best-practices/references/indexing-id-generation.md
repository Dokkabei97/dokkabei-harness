---
title: Prefer Auto-Generated _id Over Custom IDs for Pure Append Workloads
impact: MEDIUM
impactDescription: 10-30% faster indexing by skipping version conflict checks
tags: indexing, id, auto-generated, performance, versioning
---

## Prefer Auto-Generated _id Over Custom IDs for Pure Append Workloads

When you provide a custom `_id`, Elasticsearch must check if a document with that ID already exists (to handle updates/versioning). This requires a lookup in the version map. Auto-generated IDs skip this check because they are guaranteed unique, resulting in faster indexing.

**Incorrect (custom _id for append-only data like logs):**

```json
// Logs are append-only — never updated — but using custom IDs
POST /logs/_doc/log-2024-01-15-000001
{ "timestamp": "2024-01-15T10:00:00Z", "message": "App started" }

POST /logs/_doc/log-2024-01-15-000002
{ "timestamp": "2024-01-15T10:01:00Z", "message": "Request received" }

// Each indexing operation:
// 1. Hash the custom _id
// 2. Look up in version map (RAM-intensive)
// 3. Check if document exists
// 4. Index the document
// The lookup step is wasted since logs are never updated
```

**Correct (auto-generated _id for append-only workloads):**

```json
// Omit _id — Elasticsearch generates a unique ULID/Base64 ID
POST /logs/_doc
{ "timestamp": "2024-01-15T10:00:00Z", "message": "App started" }

POST /logs/_doc
{ "timestamp": "2024-01-15T10:01:00Z", "message": "Request received" }

// Auto-generated IDs:
// 1. Guaranteed unique — no version map lookup needed
// 2. Skip conflict detection entirely
// 3. ~10-30% faster indexing throughput at scale

// Also efficient via Bulk API
POST /_bulk
{"index":{"_index":"logs"}}
{"timestamp":"2024-01-15T10:00:00Z","message":"App started"}
{"index":{"_index":"logs"}}
{"timestamp":"2024-01-15T10:01:00Z","message":"Request received"}
```

When to use custom _id (update/upsert workloads):

```json
// Products, users, config — data that gets updated — NEED custom _id
POST /products/_doc/SKU-12345
{ "name": "노트북", "price": 1200000, "stock": 50 }

// Update the same document using its known ID
POST /products/_update/SKU-12345
{
  "doc": { "stock": 49 }
}

// Upsert pattern — insert or update based on _id
POST /products/_update/SKU-12345
{
  "doc": { "stock": 49 },
  "doc_as_upsert": true
}
```

Decision guide:

| Workload | _id Strategy | Reason |
|----------|-------------|--------|
| Logs, events, metrics | Auto-generated | Append-only, never updated |
| Products, users | Custom (business key) | Need update/upsert by key |
| Time-series (Data Stream) | Auto-generated | Append-only by design |
| CDC / change events | Custom (source PK) | Deduplication needed |

Reference: [Index API](https://www.elastic.co/guide/en/elasticsearch/reference/current/docs-index_.html)
