---
title: "Implement Backpressure Between MQ and Elasticsearch"
impact: MEDIUM
impactDescription: "Prevents ES thread pool rejection and consumer crash loops under load spikes"
tags: streaming, backpressure, kafka, bulk, resilience
---

## Implement Backpressure Between MQ and Elasticsearch

When Elasticsearch is under heavy load (merges, GC, node recovery), its write thread pool fills up and starts rejecting bulk requests with `EsRejectedExecutionException`. Without backpressure, the consumer keeps pulling from the message queue and hammering ES with requests that will be rejected, wasting network bandwidth and risking data loss if rejected batches are not retried. Proper backpressure pauses the consumer when ES response times degrade or rejections occur, then resumes when ES recovers.

**Incorrect (no backpressure — consumer hammers ES during overload):**

```java
// BAD: Consumer never pauses, even when ES is rejecting writes
// BAD: Rejected batches are logged but not retried — data loss
// BAD: Kafka poll continues, filling memory with unprocessable records
@KafkaListener(topics = "events", batch = "true")
public void consume(List<ConsumerRecord<String, Event>> records, Acknowledgment ack) {
    BulkRequest.Builder br = new BulkRequest.Builder();
    for (var record : records) {
        br.operations(op -> op.index(i -> i
            .index("events").id(record.key()).document(record.value())
        ));
    }

    try {
        BulkResponse response = client.bulk(br.build());
        if (response.errors()) {
            // Logs error but commits offset anyway — data loss for rejected items
            log.error("Bulk had errors: {}", response.items().stream()
                .filter(i -> i.error() != null).count());
        }
        ack.acknowledge();  // Commits even on partial failure
    } catch (Exception e) {
        log.error("Bulk failed", e);
        ack.acknowledge();  // Commits even on total failure — data lost
    }
}
```

**Correct (backpressure with pause/resume and retry):**

```java
@Component
public class BackpressureKafkaConsumer {

    private final ElasticsearchClient client;
    private final KafkaListenerEndpointRegistry registry;
    private final AtomicBoolean paused = new AtomicBoolean(false);

    // Tracks consecutive rejections to trigger pause
    private final AtomicInteger consecutiveFailures = new AtomicInteger(0);
    private static final int PAUSE_THRESHOLD = 3;
    private static final int MAX_RETRIES = 3;
    private static final long BACKOFF_BASE_MS = 1000;

    @KafkaListener(
        id = "events-consumer",
        topics = "events",
        batch = "true",
        properties = {
            "max.poll.records=500",
            "max.poll.interval.ms=600000"  // 10min — allows time for backoff + retry
        }
    )
    public void consume(List<ConsumerRecord<String, Event>> records, Acknowledgment ack) {
        BulkRequest.Builder br = new BulkRequest.Builder();
        for (var record : records) {
            br.operations(op -> op.index(i -> i
                .index("events").id(record.key()).document(record.value())
            ));
        }

        boolean success = executeBulkWithRetry(br.build(), MAX_RETRIES);
        if (success) {
            consecutiveFailures.set(0);
            ack.acknowledge();
            resumeIfPaused();
        } else {
            int failures = consecutiveFailures.incrementAndGet();
            if (failures >= PAUSE_THRESHOLD) {
                pauseConsumer();
            }
            // Do NOT acknowledge — Kafka will re-deliver on next poll
        }
    }

    private boolean executeBulkWithRetry(BulkRequest request, int maxRetries) {
        for (int attempt = 0; attempt <= maxRetries; attempt++) {
            try {
                BulkResponse response = client.bulk(request);
                if (!response.errors()) {
                    return true;
                }

                // Separate retryable (429, 503) from permanent failures (400)
                List<BulkOperation> retryable = new ArrayList<>();
                for (int i = 0; i < response.items().size(); i++) {
                    BulkResponseItem item = response.items().get(i);
                    if (item.error() != null && isRetryableStatus(item.status())) {
                        retryable.add(request.operations().get(i));
                    }
                }

                if (retryable.isEmpty()) return true;  // Only permanent failures
                request = new BulkRequest.Builder().operations(retryable).build();

                long backoff = BACKOFF_BASE_MS * (1L << attempt);
                Thread.sleep(backoff);

            } catch (ElasticsearchException e) {
                if (attempt == maxRetries) return false;
                try {
                    Thread.sleep(BACKOFF_BASE_MS * (1L << attempt));
                } catch (InterruptedException ie) {
                    Thread.currentThread().interrupt();
                    return false;
                }
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                return false;
            }
        }
        return false;
    }

    private boolean isRetryableStatus(int status) {
        return status == 429 || status == 503 || status == 409;
    }

    private void pauseConsumer() {
        if (paused.compareAndSet(false, true)) {
            registry.getListenerContainer("events-consumer").pause();
            log.warn("Paused Kafka consumer due to ES backpressure");
        }
    }

    private void resumeIfPaused() {
        if (paused.compareAndSet(true, false)) {
            registry.getListenerContainer("events-consumer").resume();
            log.info("Resumed Kafka consumer — ES recovered");
        }
    }

    // Periodic health check while paused
    @Scheduled(fixedDelay = 30_000)
    public void healthCheck() {
        if (!paused.get()) return;
        try {
            client.cluster().health(h -> h.timeout(t -> t.time("5s")));
            log.info("ES health check passed — resuming consumer");
            resumeIfPaused();
        } catch (Exception e) {
            log.warn("ES health check failed — staying paused: {}", e.getMessage());
        }
    }
}
```

**Backpressure signals to monitor:**

```json
// Check thread pool rejections (primary backpressure signal)
GET /_nodes/stats/thread_pool/write

// Key field: "rejected" count increasing = ES under write pressure
// "write": { "threads": 32, "queue": 200, "active": 32, "rejected": 1523 }

// Monitor bulk response times (early warning)
GET /_nodes/stats/indices/indexing

// Check circuit breaker trips
GET /_nodes/stats/breaker
```

**Backpressure flow:**

```
                  +-----------+
                  |   Kafka   |
                  | Consumer  |
                  +-----+-----+
                        |
                   poll batch
                        |
                  +-----v-----+
                  | Bulk to ES|----> Success: ack offset, reset counter
                  +-----+-----+
                        |
                   Rejected/Timeout
                        |
                  +-----v-----+
                  |  Retry    |----> Retry with exponential backoff
                  | (max 3x)  |      (1s, 2s, 4s)
                  +-----+-----+
                        |
                   Still failing
                        |
                  +-----v---------+
                  | Pause Consumer|----> Stop polling from Kafka
                  | (3 consecutive|      Health check every 30s
                  |  failures)    |      Resume when ES recovers
                  +---------------+
```

**Key rules:**

- Never `ack.acknowledge()` on failure — let Kafka re-deliver the batch on the next poll.
- Use exponential backoff between retries: 1s, 2s, 4s to avoid thundering herd on ES recovery.
- Pause the Kafka consumer (not just sleep) so that Kafka's `max.poll.interval.ms` is not violated.
- Set `max.poll.interval.ms` high enough (600s) to accommodate retry + backoff cycles.
- Monitor `thread_pool.write.rejected` as the primary signal for ES write pressure.
- Separate retryable errors (429 Too Many Requests, 503 Service Unavailable) from permanent errors (400 Bad Request).

Reference:
[Bulk API Error Handling](https://www.elastic.co/guide/en/elasticsearch/reference/current/docs-bulk.html) |
[Thread Pool Stats](https://www.elastic.co/guide/en/elasticsearch/reference/current/cluster-nodes-stats.html#cluster-nodes-stats-api-response-body-thread-pool)
