---
title: "Choose BulkIngester vs Direct Bulk Based on Consuming Strategy"
impact: MEDIUM-HIGH
impactDescription: "Eliminates double-buffering overhead, simplifies architecture"
tags: streaming, kafka, bulk-ingester, consumer, integration
---

## Choose BulkIngester vs Direct Bulk Based on Consuming Strategy

Kafka consumers operate in two fundamentally different modes: single-message consumption (`@KafkaListener` per record) and batch consumption (`poll()` with `max.poll.records`). Each mode has a natural pairing with Elasticsearch's bulk ingestion mechanisms. Mismatching these produces double-buffering: Kafka batches records, then BulkIngester re-batches them, doubling memory usage and creating complex offset management with no throughput benefit. Matching the right strategy eliminates an entire buffering layer and simplifies exactly-once offset semantics.

**Decision flowchart:**

```
Is your consumer batch-based (poll/max.poll.records)?
|-- YES --> Use direct client.bulk() per poll batch
|           (Kafka handles batching, no need for BulkIngester)
+-- NO (single message @KafkaListener)
    +-- Use BulkIngester with size-based flush
        (Need buffering layer to batch individual messages)
```

**Incorrect (double buffering — BulkIngester on batch consumer):**

```java
// BAD: Kafka already delivers ~500 records per poll (max.poll.records=500)
// BAD: BulkIngester adds a second buffering layer on top of Kafka's batch
// BAD: Offset commit is decoupled from ES write — risk of data loss or duplicates
@KafkaListener(topics = "products", batch = "true")
public void consume(List<ConsumerRecord<String, Product>> records) {
    // records is already a batch of ~500 from Kafka
    for (var record : records) {
        ingester.add(op -> op.index(i -> i
            .index("products").id(record.key()).document(record.value())
        ));
    }
    // BulkIngester may hold these across multiple poll cycles
    // Kafka can't commit offsets until BulkIngester flushes
    // If BulkIngester hasn't flushed when next poll() runs:
    //   - Memory holds 2x batches (Kafka's + BulkIngester's internal buffer)
    //   - Offset commit is timing-dependent, not completion-dependent
    //   - On crash: data either lost (committed but not flushed) or duplicated
}
```

The core issue: `BulkIngester` flushes on its own schedule (size/time thresholds), but Kafka expects offset commits tied to processing completion. When these two schedules are decoupled, you get either data loss (offset committed before ES write) or duplicates (ES write succeeded but offset not committed before crash).

**Correct A (single-message consumer + BulkIngester):**

```java
// GOOD: Messages arrive one at a time — BulkIngester provides necessary batching
// GOOD: BulkIngester accumulates until threshold → flushes as a single bulk request
@KafkaListener(topics = "products")
public void consume(ConsumerRecord<String, Product> record) {
    ingester.add(op -> op.index(i -> i
        .index("products").id(record.key()).document(record.value())
    ));
    // BulkIngester buffers internally and flushes at:
    //   - 500 operations, OR
    //   - 15MB accumulated size, OR
    //   - 5 seconds since last flush
    // With enable.auto.commit=true, offsets advance as messages are consumed
    // Acceptable trade-off: at-least-once delivery (idempotent via document ID)
}
```

```java
// BulkIngester configuration for single-message consumers
BulkIngester<Void> ingester = BulkIngester.of(b -> b
    .client(client)
    .maxOperations(500)                       // Flush every 500 ops
    .maxSize(15 * 1024 * 1024)                // Flush at 15MB
    .flushInterval(5, TimeUnit.SECONDS)       // Flush every 5s (max latency)
    .listener(new BulkListener<>() {
        @Override
        public void beforeBulk(long executionId, BulkRequest request, List<Void> contexts) {}

        @Override
        public void afterBulk(long executionId, BulkRequest request,
                              List<Void> contexts, BulkResponse response) {
            if (response.errors()) {
                log.error("Bulk had errors: {}", response.items().stream()
                    .filter(i -> i.error() != null)
                    .map(i -> i.error().reason())
                    .toList());
            }
        }

        @Override
        public void afterBulk(long executionId, BulkRequest request,
                              List<Void> contexts, Throwable failure) {
            log.error("Bulk failed entirely", failure);
        }
    })
);
```

**Correct B (batch consumer + direct bulk — recommended for high throughput):**

```java
// GOOD: Kafka batch → ES bulk in a single hop, no intermediate buffer
// GOOD: Offset commit is tied directly to ES bulk response
// GOOD: Simple mental model: one poll() = one bulk() = one commit
@KafkaListener(
    topics = "products",
    batch = "true",
    properties = {
        "max.poll.records=500",
        "fetch.min.bytes=1048576"    // 1MB — wait for substantial batch
    }
)
public void consume(List<ConsumerRecord<String, Product>> records, Acknowledgment ack) {
    BulkRequest.Builder br = new BulkRequest.Builder();
    for (var record : records) {
        br.operations(op -> op.index(i -> i
            .index("products")
            .id(record.key())
            .document(record.value())
        ));
    }

    BulkResponse response = client.bulk(br.build());
    if (!response.errors()) {
        ack.acknowledge();  // Commit offset only after ES confirms all writes
    } else {
        // Handle partial failures — retry failed items or send to DLQ
        List<BulkResponseItem> failed = response.items().stream()
            .filter(item -> item.error() != null)
            .toList();
        log.error("Bulk partial failure: {} of {} items failed",
            failed.size(), records.size());
        // Option: re-send failed items, then acknowledge
        // Option: nack to re-consume entire batch
    }
}
```

**Comparison of approaches:**

```
Aspect                | Single + BulkIngester | Batch + Direct Bulk
----------------------|-----------------------|---------------------
Buffering layers      | 1 (BulkIngester)      | 0 (Kafka batches)
Memory overhead       | Higher (dual buffer)  | Lower (single batch)
Offset semantics      | At-least-once (loose) | At-least-once (tight)
Failure handling      | Async (listener)      | Sync (immediate)
Throughput ceiling    | ~5,000 docs/s         | ~20,000+ docs/s
Complexity            | Low (fire-and-forget) | Medium (error handling)
Best for              | Low-volume streams    | High-volume pipelines
```

**Key rules:**

- If you use `max.poll.records` for batch consuming, use `client.bulk()` directly — never wrap with `BulkIngester`.
- If you use `@KafkaListener` on individual records, use `BulkIngester` to avoid one-doc-per-bulk overhead.
- Always use `ack_mode=MANUAL` with batch consumer + direct bulk to tie offset commit to ES write confirmation.
- Set Kafka `max.poll.interval.ms` high enough to accommodate the slowest expected ES bulk response (default 300s is usually fine).
- Use document `id` (Kafka record key) for idempotent writes — this makes at-least-once safe for re-processing.

Reference:
[BulkIngester Documentation](https://www.elastic.co/guide/en/elasticsearch/client/java-api-client/current/indexing-bulk.html) |
[Kafka Consumer Configuration](https://kafka.apache.org/documentation/#consumerconfigs)
