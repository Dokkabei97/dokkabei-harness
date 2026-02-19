---
title: Always Use Bulk API, Never Single-Document Loops
impact: CRITICAL
impactDescription: 10-100x indexing throughput improvement
tags: indexing, bulk, performance, throughput
---

## Always Use Bulk API, Never Single-Document Loops

Single-document indexing requires one HTTP round-trip per document. At 2-5ms network latency per request, indexing 1M documents takes 30-80 minutes of pure network overhead. The Bulk API batches 500-5000 documents per request, amortizing connection overhead and enabling Elasticsearch to optimize internal segment writes. On a 10+ node cluster ingesting 100M+ documents, this is the difference between hours and minutes.

**Incorrect (single-document loop via REST):**

```json
// 1 HTTP round-trip per document → network latency dominates
// 1M docs × 3ms avg latency = 50 minutes of just waiting
POST /products/_doc
{ "product_id": "P-1001", "name": "Wireless Headphones", "price": 79.99 }

POST /products/_doc
{ "product_id": "P-1002", "name": "USB-C Cable", "price": 12.99 }

// ... repeated 1,000,000 times
```

**Incorrect (single-document loop in Java):**

```java
// Each index() call triggers a separate HTTP request
// Thread blocks on each response before sending the next
for (Product product : products) {
    client.index(i -> i
        .index("products")
        .id(product.getProductId())
        .document(product)
    );
}
```

**Correct (Bulk API via REST with optimal batch size):**

```json
// Batch 1000-5000 docs per request → 1 HTTP round-trip per batch
// Target 5-15MB per bulk request, not a fixed document count
POST /_bulk
{ "index": { "_index": "products", "_id": "P-1001" } }
{ "product_id": "P-1001", "name": "Wireless Headphones", "price": 79.99, "category": "electronics" }
{ "index": { "_index": "products", "_id": "P-1002" } }
{ "product_id": "P-1002", "name": "USB-C Cable", "price": 12.99, "category": "accessories" }
{ "index": { "_index": "products", "_id": "P-1003" } }
{ "product_id": "P-1003", "name": "Laptop Stand", "price": 49.99, "category": "accessories" }
```

**Correct (Bulk API in Java with BulkRequest.Builder):**

```java
// Accumulate operations, send as single HTTP request
BulkRequest.Builder bulkBuilder = new BulkRequest.Builder();

for (Product product : products) {
    bulkBuilder.operations(op -> op
        .index(i -> i
            .index("products")
            .id(product.getProductId())
            .document(product)
        )
    );
}

BulkResponse response = client.bulk(bulkBuilder.build());

// Always check for per-item errors — bulk request itself may succeed
// while individual operations fail (e.g., mapping conflict)
if (response.errors()) {
    for (BulkResponseItem item : response.items()) {
        if (item.error() != null) {
            log.error("Failed to index doc {}: {}", item.id(), item.error().reason());
        }
    }
}
```

**Optimal bulk size guidelines:**

| Document Size | Recommended Batch Count | Resulting Payload |
|---------------|------------------------|-------------------|
| ~100 bytes | 5000 | ~500KB |
| ~1KB | 5000 | ~5MB |
| ~5KB | 2000 | ~10MB |
| ~50KB | 200 | ~10MB |

The optimal bulk size is **5-15MB per request**, not a fixed document count. Oversized payloads (50MB+) cause memory pressure on coordinating nodes and risk HTTP timeouts. Undersized payloads (< 1MB) don't amortize enough overhead. Benchmark with your cluster to find the sweet spot.

Reference: [Bulk API](https://www.elastic.co/guide/en/elasticsearch/reference/current/docs-bulk.html)
