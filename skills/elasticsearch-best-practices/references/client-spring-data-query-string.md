---
title: "Avoid Spring Data ES Default query_string"
impact: HIGH
impactDescription: "Eliminates Lucene parser overhead, enables filter cache, prevents injection"
tags: client, spring-data, query-string, elasticsearch-java, best-practice
---

## Avoid Spring Data ES Default query_string

Spring Data Elasticsearch converts repository method names (e.g., `findByStatusAndPriceLessThan`) into `query_string` queries at runtime. This triggers the full Lucene query parser on every execution, bypasses the filter cache entirely because `query_string` always scores, and exposes your cluster to query injection when user input contains Lucene syntax (`AND`, `OR`, `*`, `~`). On a 100M+ document index, switching from `query_string` to explicit `bool/filter` reduces p99 latency by 40-60% and eliminates an entire class of security vulnerabilities.

**Incorrect (method name auto-generation):**

```java
// Spring Data derives query_string from method name
// Internally generates: {"query_string": {"query": "status:active AND price:<100"}}
public interface ProductRepository extends ElasticsearchRepository<Product, String> {
    List<Product> findByStatusAndPriceLessThan(String status, double price);
    // Problem 1: Lucene parser overhead on every call — parses query syntax at runtime
    // Problem 2: No filter cache — query_string always calculates relevance scores
    // Problem 3: Injection risk — if status = "active OR *", Lucene interprets it as syntax
    // Problem 4: No control over bool query structure (must vs filter vs should)
}
```

```java
// Typical controller using the auto-generated method
@GetMapping("/products")
public List<Product> search(@RequestParam String status, @RequestParam double maxPrice) {
    // If user sends status = "active AND price:[0 TO 999999]" → Lucene injection
    return productRepository.findByStatusAndPriceLessThan(status, maxPrice);
}
```

The `query_string` parser runs on every query execution, parsing the generated Lucene syntax string. For non-scoring filters (exact match on `status`, range on `price`), this parsing step is pure waste. Worse, the query executes in the query context (not filter context), so results are scored unnecessarily and cannot leverage the filter cache.

**Correct A (@Query annotation — explicit bool/filter DSL):**

```java
public interface ProductRepository extends ElasticsearchRepository<Product, String> {
    @Query("""
        {
          "bool": {
            "filter": [
              { "term": { "status": "?0" } },
              { "range": { "price": { "lt": ?1 } } }
            ]
          }
        }
        """)
    List<Product> findActiveUnderPrice(String status, double price);
    // GOOD: Explicit filter context — results are cached, no scoring overhead
    // GOOD: No Lucene parser invocation — DSL sent directly to ES
    // GOOD: Parameters are value-substituted, not syntax-interpreted
}
```

This approach keeps the repository abstraction while giving full control over the query DSL. Filter context enables the node query cache (up to 10% of heap by default), which can serve repeated filter combinations from cache with zero computation.

**Correct B (elasticsearch-java client — recommended for production):**

```java
@Service
@RequiredArgsConstructor
public class ProductSearchService {
    private final ElasticsearchClient client;

    public List<Product> findActiveUnderPrice(String status, double price) {
        SearchResponse<Product> response = client.search(s -> s
            .index("products")
            .query(q -> q
                .bool(b -> b
                    .filter(f -> f.term(t -> t.field("status").value(status)))
                    .filter(f -> f.range(r -> r.field("price").lt(JsonData.of(price))))
                )
            ),
            Product.class
        );
        return response.hits().hits().stream()
            .map(Hit::source)
            .filter(Objects::nonNull)
            .toList();
    }
}
// GOOD: Full type-safe control — compile-time validation of query structure
// GOOD: Lambda builder pattern prevents malformed queries
// GOOD: No abstraction leaks — you see exactly what ES receives
// GOOD: Easy to add aggregations, highlights, sort, collapse, etc.
```

**3-tier recommendation summary:**

```
Approach                     | Cache | Type-Safe | Injection-Safe | DSL Control
-----------------------------|-------|-----------|----------------|------------
findByXxx (method name)      |  NO   |    NO     |      NO        |    NONE
@Query annotation            |  YES  |    NO     |     PARTIAL    |    FULL
elasticsearch-java client    |  YES  |    YES    |      YES       |    FULL
```

**Key rules:**

- Never use repository method name derivation for production queries on indices over 1M documents.
- Use `@Query` annotation as a quick improvement when you need the repository pattern for simple queries.
- Use the elasticsearch-java client for all complex queries, aggregations, and any query involving user input.
- Always place exact-match and range filters in `filter` context to leverage the node query cache.
- Validate and sanitize user input even when using the elasticsearch-java client — defense in depth.

Reference:
[Spring Data Elasticsearch — Query Methods](https://docs.spring.io/spring-data/elasticsearch/reference/elasticsearch/template.html) |
[Elasticsearch Java Client](https://www.elastic.co/guide/en/elasticsearch/client/java-api-client/current/index.html)
