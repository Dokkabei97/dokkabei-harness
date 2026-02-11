---
title: Always Use Bulk API for Indexing — Never Single-Document Indexing in Loops
impact: CRITICAL
impactDescription: 10-100x faster indexing throughput, dramatically lower cluster overhead
tags: indexing, bulk, performance, throughput, batch
---

## Always Use Bulk API for Indexing — Never Single-Document Indexing in Loops

Single-document indexing creates a separate HTTP request, transport-layer operation, and Lucene operation per document. The Bulk API batches hundreds or thousands of operations into a single request, amortizing network and coordination overhead.

**Incorrect (single-document indexing in a loop):**

```json
// Each request: TCP handshake + HTTP headers + JSON parse + shard routing + refresh
POST /products/_doc
{ "name": "노트북 A", "price": 1200000 }

POST /products/_doc
{ "name": "노트북 B", "price": 1500000 }

// ... 10,000 individual requests
// 10,000 round trips × ~5ms each = 50 seconds minimum
// Each request triggers independent translog sync
```

```python
# Application anti-pattern
for doc in documents:
    es.index(index="products", body=doc)
# 10,000 documents = 10,000 HTTP requests = extremely slow
```

**Correct (Bulk API with optimal batch size):**

```json
// All operations in a single HTTP request
POST /_bulk
{"index":{"_index":"products"}}
{"name":"노트북 A","price":1200000,"category":"laptop"}
{"index":{"_index":"products"}}
{"name":"노트북 B","price":1500000,"category":"laptop"}
{"index":{"_index":"products"}}
{"name":"마우스 C","price":35000,"category":"accessory"}
```

```python
# Application best practice — use bulk helper
from elasticsearch.helpers import bulk

actions = [
    {"_index": "products", "_source": doc}
    for doc in documents
]

success, errors = bulk(
    es,
    actions,
    chunk_size=1000,      # Documents per batch
    max_retries=3,        # Retry on 429 (Too Many Requests)
    raise_on_error=False  # Collect errors instead of raising
)
```

Optimal bulk request sizing:

```json
// Target 5-15MB per bulk request (not document count)
// Monitor with response timing

// Too small (1MB): overhead dominates
POST /_bulk
// 100 tiny documents → 1MB → most time spent on HTTP overhead

// Optimal (5-15MB): best throughput
POST /_bulk
// 1000-5000 documents → ~10MB → optimal batching

// Too large (50MB+): heap pressure, risk of timeout
POST /_bulk
// 50,000 documents → 50MB → risk of circuit breaker, HTTP timeout
```

Bulk response handling — always check for partial failures:

```json
// Bulk response contains per-item status
{
  "took": 30,
  "errors": true,
  "items": [
    { "index": { "_index": "products", "_id": "1", "status": 201 } },
    { "index": { "_index": "products", "_id": "2", "status": 429,
        "error": { "type": "es_rejected_execution_exception", "reason": "..." } } }
  ]
}
// errors: true means at least one item failed
// Status 429 = thread pool queue full — back off and retry only failed items
```

Tuning for maximum bulk throughput:
- Use multiple threads sending bulk requests in parallel (start with `number_of_data_nodes` threads)
- Monitor `thread_pool.write.queue` and `thread_pool.write.rejected` to find optimal concurrency
- If seeing 429 responses, reduce concurrency or increase queue size

Reference: [Bulk API](https://www.elastic.co/guide/en/elasticsearch/reference/current/docs-bulk.html)
