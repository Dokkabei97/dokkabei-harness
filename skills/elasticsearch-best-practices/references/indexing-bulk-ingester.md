---
title: Migrate BulkProcessor(v8) to BulkIngester(v9) with Size-Based Flush
impact: HIGH
impactDescription: Consistent memory usage and optimal bulk sizing across document types
tags: indexing, bulk-ingester, bulk-processor, migration, v8-to-v9
---

## Migrate BulkProcessor(v8) to BulkIngester(v9) with Size-Based Flush

The legacy `BulkProcessor` (deprecated in ES Java client 8.x) uses count-based flushing as its primary trigger. This is fundamentally unreliable: 1000 small docs (100 bytes each) produces a 100KB flush that underutilizes the bulk endpoint, while 1000 large docs (50KB each) creates a 50MB flush that causes memory pressure and potential timeouts. The new `BulkIngester` in the ES Java client for 9.x makes size-based flushing the primary trigger, ensuring consistent 5-15MB payloads regardless of document size.

**Incorrect (BulkProcessor with count-based flush — ES Java client 8.x, deprecated):**

```java
// Count-based flush: unreliable payload sizes across document types
// 1000 small logs (100B each) → 100KB flush (too small, wasted round-trips)
// 1000 product catalogs (50KB each) → 50MB flush (too large, memory pressure)
BulkProcessor bulkProcessor = BulkProcessor.builder(
        (request, listener) -> client.bulkAsync(request, RequestOptions.DEFAULT, listener),
        new BulkProcessor.Listener() {
            @Override
            public void beforeBulk(long executionId, BulkRequest request) {
                log.info("Executing bulk #{} with {} actions", executionId, request.numberOfActions());
            }

            @Override
            public void afterBulk(long executionId, BulkRequest request, BulkResponse response) {
                if (response.hasFailures()) {
                    log.error("Bulk #{} failures: {}", executionId, response.buildFailureMessage());
                }
            }

            @Override
            public void afterBulk(long executionId, BulkRequest request, Throwable failure) {
                log.error("Bulk #{} failed entirely", executionId, failure);
            }
        })
    .setBulkActions(1000)                              // primary trigger: document count
    .setBulkSize(new ByteSizeValue(5, ByteSizeUnit.MB)) // secondary trigger: payload size
    .setFlushInterval(TimeValue.timeValueSeconds(5))    // safety net: time-based flush
    .setConcurrentRequests(2)
    .build();

// Adding documents
for (Product product : products) {
    bulkProcessor.add(new IndexRequest("products")
        .id(product.getProductId())
        .source(objectMapper.writeValueAsString(product), XContentType.JSON));
}

bulkProcessor.awaitClose(30, TimeUnit.SECONDS);
```

**Correct (BulkIngester with size-based flush — ES Java client for 9.x):**

```java
// Size-based flush: consistent 15MB payloads regardless of document size
// Small docs: accumulates more documents to reach 15MB → efficient batching
// Large docs: flushes with fewer documents to stay under 15MB → safe memory
BulkListener<Void> listener = new BulkListener<Void>() {
    @Override
    public void beforeBulk(long executionId, BulkRequest request, List<Void> contexts) {
        log.info("Executing bulk #{} with {} operations", executionId, request.operations().size());
    }

    @Override
    public void afterBulk(long executionId, BulkRequest request, List<Void> contexts,
                           BulkResponse response) {
        long failed = response.items().stream().filter(i -> i.error() != null).count();
        if (failed > 0) {
            log.error("Bulk #{}: {} of {} operations failed", executionId, failed,
                       response.items().size());
            response.items().stream()
                .filter(i -> i.error() != null)
                .forEach(i -> log.error("  {} [{}]: {}", i.id(), i.index(),
                                         i.error().reason()));
        }
    }

    @Override
    public void afterBulk(long executionId, BulkRequest request, List<Void> contexts,
                           Throwable failure) {
        log.error("Bulk #{} failed entirely: {}", executionId, failure.getMessage(), failure);
    }
};

BulkIngester<Void> ingester = BulkIngester.of(b -> b
    .client(client)
    .maxOperations(5000)                   // safety cap: max documents per batch
    .maxSize(15 * 1024 * 1024)             // PRIMARY trigger: 15MB per bulk request
    .flushInterval(5, TimeUnit.SECONDS)    // safety net: flush stale buffers
    .maxConcurrentRequests(3)
    .listener(listener)
);

// Adding documents — same simple API
for (Product product : products) {
    ingester.add(op -> op
        .index(i -> i
            .index("products")
            .id(product.getProductId())
            .document(product)
        )
    );
}

ingester.close();  // flushes remaining documents and waits for completion
```

**Why size-based flush matters — real-world comparison:**

| Scenario | BulkProcessor (count=1000) | BulkIngester (size=15MB) |
|----------|---------------------------|--------------------------|
| 1000 small logs (~100B each) | 100KB flush — underutilized | Accumulates ~150K docs → 15MB flush |
| 1000 product docs (~5KB each) | 5MB flush — acceptable | Accumulates ~3000 docs → 15MB flush |
| 1000 catalog pages (~50KB each) | 50MB flush — memory pressure | Flushes at ~300 docs → 15MB flush |
| Mixed sizes in same pipeline | Unpredictable 100KB-50MB | Consistent 15MB ± variance |

**Migration checklist:**

| BulkProcessor (v8) | BulkIngester (v9) | Notes |
|---------------------|---------------------|-------|
| `setBulkActions(n)` | `maxOperations(n)` | Demote to safety cap, not primary trigger |
| `setBulkSize(size)` | `maxSize(bytes)` | Promote to primary flush trigger (15MB) |
| `setFlushInterval(t)` | `flushInterval(t, unit)` | Keep as safety net for low-throughput periods |
| `setConcurrentRequests(n)` | `maxConcurrentRequests(n)` | Same semantics |
| `BulkProcessor.Listener` | `BulkListener<Context>` | Generic context type for per-doc metadata |
| `bulkProcessor.add(IndexRequest)` | `ingester.add(BulkOperation)` | Typed builder API instead of raw requests |
| `awaitClose(timeout)` | `close()` | Blocks until all flushed and completed |

Set `maxSize` to **15MB** as your primary flush trigger. Use `maxOperations` only as an upper safety cap (5000-10000) to prevent extreme edge cases where many tiny documents accumulate. The `flushInterval` (5-10 seconds) ensures stale buffers get flushed during low-throughput periods.

Reference: [BulkIngester](https://www.elastic.co/guide/en/elasticsearch/client/java-api-client/current/indexing-bulk.html)
