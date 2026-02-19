---
title: "Configure HTTP Connection Pooling and Timeouts"
impact: MEDIUM-HIGH
impactDescription: "Prevents connection exhaustion under high concurrency"
tags: client, connection-pool, timeout, HTTP, RestClient
---

## Configure HTTP Connection Pooling and Timeouts

The default `RestClient` ships with Apache HttpAsyncClient defaults: 25 total connections and 5 connections per route. At 1000+ QPS with 10+ ES nodes, this pool exhausts in seconds, causing threads to block on connection acquisition and cascading timeouts across your application. The default 30-second socket timeout is also too aggressive for bulk operations but too lenient for search queries. Tuning the pool to match your throughput profile prevents connection starvation and gives you granular control over failure detection.

**Incorrect (default RestClient with no pool or timeout configuration):**

```java
// BAD: Default pool = 25 total, 5 per route → connection starvation at high QPS
// BAD: Default socket timeout = 30s → slow failure detection for search
// BAD: No connection eviction → stale connections cause sporadic failures
RestClient restClient = RestClient.builder(
    new HttpHost("es-node-1", 9200, "https"),
    new HttpHost("es-node-2", 9200, "https"),
    new HttpHost("es-node-3", 9200, "https")
).build();

ElasticsearchClient client = new ElasticsearchClient(
    new RestClientTransport(restClient, new JacksonJsonpMapper())
);
// Under 500+ concurrent requests, threads block waiting for a connection from the pool
// Symptom: "Connection pool shut down" or "Timeout waiting for connection from pool"
```

**Correct (tuned connection pool and differentiated timeouts):**

```java
RestClient restClient = RestClient.builder(
        new HttpHost("es-node-1", 9200, "https"),
        new HttpHost("es-node-2", 9200, "https"),
        new HttpHost("es-node-3", 9200, "https")
    )
    .setHttpClientConfigCallback(httpClientBuilder -> httpClientBuilder
        // Connection pool sizing
        .setMaxConnTotal(150)          // Total connections across all nodes
        .setMaxConnPerRoute(50)        // Per-node connections (150 / 3 nodes = 50)
        // Keep-alive strategy
        .setKeepAliveStrategy((response, context) -> 60_000)  // 60s keep-alive
        // Connection eviction for stale connections
        .evictExpiredConnections()
        .evictIdleConnections(30, TimeUnit.SECONDS)
    )
    .setRequestConfigCallback(requestConfigBuilder -> requestConfigBuilder
        .setConnectTimeout(5_000)          // TCP connection timeout: 5s
        .setSocketTimeout(30_000)          // Socket read timeout: 30s (for bulk/scroll)
        .setConnectionRequestTimeout(5_000) // Pool acquisition timeout: 5s
    )
    .build();
```

**Recommended values by throughput tier:**

```
Setting                 | Low (<100 QPS) | Medium (100-1000 QPS) | High (1000+ QPS)
------------------------|----------------|-----------------------|-----------------
maxConnTotal            |       30       |          100          |       200+
maxConnPerRoute         |       10       |           30          |        50+
connectTimeout (ms)     |     5,000      |        3,000          |      2,000
socketTimeout (ms)      |    30,000      |       30,000          |     60,000*
connectionRequestTimeout|    10,000      |        5,000          |      3,000
keepAlive (ms)          |    60,000      |       60,000          |     30,000
idleEviction (s)        |       60       |           30          |        15

* High-QPS tiers need longer socket timeout to accommodate bulk operations
  Use separate clients for search (10s) vs bulk (60s) at this tier
```

**Split client strategy for mixed workloads (recommended at high QPS):**

```java
// Separate client for fast search queries — short timeouts, fail fast
RestClient searchRestClient = RestClient.builder(esHosts)
    .setHttpClientConfigCallback(b -> b.setMaxConnTotal(100).setMaxConnPerRoute(30))
    .setRequestConfigCallback(b -> b
        .setSocketTimeout(10_000)            // 10s — search should be fast
        .setConnectionRequestTimeout(2_000)  // 2s — fail fast if pool exhausted
    )
    .build();

// Separate client for bulk/scroll — longer timeouts, higher tolerance
RestClient bulkRestClient = RestClient.builder(esHosts)
    .setHttpClientConfigCallback(b -> b.setMaxConnTotal(50).setMaxConnPerRoute(15))
    .setRequestConfigCallback(b -> b
        .setSocketTimeout(120_000)           // 120s — bulk can take time
        .setConnectionRequestTimeout(10_000) // 10s — queue is acceptable for bulk
    )
    .build();
```

**Diagnosing connection pool issues:**

```bash
# Monitor ES thread pool queues — if search/write queues grow, clients are waiting
GET /_cat/thread_pool/search,write?v&h=node_name,name,active,queue,rejected

# Check for rejected executions — signals client is overwhelming the cluster
GET /_nodes/stats/thread_pool/search,write
# Look for: "rejected" count > 0
```

**Key rules:**

- Set `maxConnPerRoute` to at least `maxConnTotal / number_of_nodes` to distribute connections evenly.
- Always configure `connectionRequestTimeout` — the default blocks indefinitely on a full pool.
- Enable `evictExpiredConnections()` and `evictIdleConnections()` to prevent stale connection failures.
- Use separate `RestClient` instances for search (short timeout) and bulk (long timeout) at 1000+ QPS.
- Monitor ES thread pool rejected counts — connection pool tuning is meaningless if the cluster itself is saturated.
- Set `-Xms` and `-Xmx` equal in the client JVM to prevent GC pauses that hold connections open during GC.

Reference:
[RestClient Configuration](https://www.elastic.co/guide/en/elasticsearch/client/java-api-client/current/java-rest-low-usage-initialization.html) |
[Apache HttpAsyncClient Configuration](https://hc.apache.org/httpcomponents-asyncclient-4.1.x/)
