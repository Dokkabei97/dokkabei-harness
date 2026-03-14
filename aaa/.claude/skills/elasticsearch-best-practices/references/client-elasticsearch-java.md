---
title: "Use elasticsearch-java Client for Full Query Control"
impact: MEDIUM-HIGH
impactDescription: "Type-safe queries, full DSL access, no abstraction leaks"
tags: client, elasticsearch-java, type-safe, query-builder
---

## Use elasticsearch-java Client for Full Query Control

The High Level Rest Client (HLRC) was deprecated in Elasticsearch 7.15 and removed in 8.x. It relied on the Elasticsearch server codebase, pulling in hundreds of transitive dependencies and tightly coupling client and server versions. The new `elasticsearch-java` client uses a lightweight, code-generated API with a lambda-based builder pattern that provides compile-time type safety and zero dependency on the server codebase. Migrating eliminates version-mismatch runtime errors and reduces your client JAR footprint by over 80%.

**Incorrect (deprecated RestHighLevelClient):**

```java
// BAD: HLRC is deprecated since 7.15, removed in 8.x
// BAD: Pulls in server dependencies (~200 transitive JARs)
// BAD: No compile-time query structure validation
import org.elasticsearch.client.RestHighLevelClient;
import org.elasticsearch.action.search.SearchRequest;
import org.elasticsearch.index.query.QueryBuilders;

RestHighLevelClient client = new RestHighLevelClient(
    RestClient.builder(new HttpHost("localhost", 9200, "https"))
);

SearchRequest request = new SearchRequest("products");
request.source().query(
    QueryBuilders.boolQuery()
        .filter(QueryBuilders.termQuery("status", "active"))
        .filter(QueryBuilders.rangeQuery("price").lt(100))
);
SearchResponse response = client.search(request, RequestOptions.DEFAULT);
// No type mapping — hits come back as raw Maps or require manual ObjectMapper
```

**Correct (elasticsearch-java client with type-safe builders):**

```xml
<!-- Maven dependency — single artifact, minimal transitive deps -->
<dependency>
    <groupId>co.elastic.clients</groupId>
    <artifactId>elasticsearch-java</artifactId>
    <version>8.15.3</version>
</dependency>
<dependency>
    <groupId>com.fasterxml.jackson.core</groupId>
    <artifactId>jackson-databind</artifactId>
    <version>2.17.2</version>
</dependency>
```

```java
// Client initialization with connection pooling and authentication
RestClient restClient = RestClient.builder(
        new HttpHost("es-node-1", 9200, "https"),
        new HttpHost("es-node-2", 9200, "https"),
        new HttpHost("es-node-3", 9200, "https")
    )
    .setDefaultHeaders(new Header[]{
        new BasicHeader("Authorization", "ApiKey " + apiKey)
    })
    .build();

ElasticsearchTransport transport = new RestClientTransport(
    restClient, new JacksonJsonpMapper()
);

ElasticsearchClient client = new ElasticsearchClient(transport);
```

```java
// Search — lambda builder pattern with automatic type mapping
SearchResponse<Product> response = client.search(s -> s
    .index("products")
    .query(q -> q
        .bool(b -> b
            .filter(f -> f.term(t -> t.field("status").value("active")))
            .filter(f -> f.range(r -> r.field("price").lt(JsonData.of(100))))
        )
    )
    .sort(so -> so.field(f -> f.field("created_at").order(SortOrder.Desc)))
    .size(20),
    Product.class  // Automatic deserialization into POJO
);

List<Product> products = response.hits().hits().stream()
    .map(Hit::source)
    .filter(Objects::nonNull)
    .toList();
```

```java
// Index a document
IndexResponse indexResponse = client.index(i -> i
    .index("products")
    .id(product.getId())
    .document(product)
);
```

```java
// Bulk operations with BulkIngester for high-throughput
BulkIngester<Void> ingester = BulkIngester.of(b -> b
    .client(client)
    .maxOperations(500)
    .maxSize(15 * 1024 * 1024)  // 15MB
    .flushInterval(5, TimeUnit.SECONDS)
);

for (Product product : products) {
    ingester.add(op -> op.index(i -> i
        .index("products")
        .id(product.getId())
        .document(product)
    ));
}
ingester.close();  // Flush remaining
```

**Key advantages of the lambda builder pattern:**

```
Feature                  | HLRC (deprecated)     | elasticsearch-java
-------------------------|-----------------------|---------------------
Compile-time safety      | Partial (strings)     | Full (typed builders)
Server dependency        | Yes (~200 JARs)       | No (code-generated)
Type mapping             | Manual ObjectMapper   | Automatic via generics
Version coupling         | Tight (same version)  | Loose (protocol-level)
Async support            | Separate async client | Built-in async methods
Bulk ingestion           | Manual batching       | BulkIngester built-in
```

**Key rules:**

- Remove all `org.elasticsearch.client:elasticsearch-rest-high-level-client` dependencies.
- Use `co.elastic.clients:elasticsearch-java` with matching Jackson databind.
- Always specify the target POJO class in search calls for automatic deserialization.
- Use `BulkIngester` for indexing throughput over 100 docs/sec.
- Use the async variant (`ElasticsearchAsyncClient`) for non-blocking I/O in reactive stacks.

Reference:
[Elasticsearch Java Client Guide](https://www.elastic.co/guide/en/elasticsearch/client/java-api-client/current/index.html) |
[Migration from HLRC](https://www.elastic.co/guide/en/elasticsearch/client/java-api-client/current/migrate-hlrc.html)
