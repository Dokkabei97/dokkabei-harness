# Writing Guidelines for Elasticsearch References

This document provides guidelines for creating effective Elasticsearch best
practice references that work well with AI agents and LLMs.

## Key Principles

### 1. Concrete Transformation Patterns

Show exact query/mapping rewrites. Avoid philosophical advice.

**Good:** "Move `term` and `range` from `must` to `filter` for non-scoring clauses"
**Bad:** "Write efficient queries"

### 2. Error-First Structure

Always show the problematic pattern first, then the solution. This trains agents
to recognize anti-patterns.

```markdown
**Incorrect (scoring unnecessary clauses):** [bad example]

**Correct (filter context for non-scoring):** [good example]
```

### 3. Quantified Impact

Include specific metrics. Helps agents prioritize fixes.

**Good:** "2-10x faster queries", "50% memory reduction", "Eliminates scoring overhead"
**Bad:** "Faster", "Better", "More efficient"

### 4. Self-Contained Examples

Examples should be complete and runnable against Elasticsearch REST API.
Include mapping definitions if context is needed.

```json
// Include mapping when needed for clarity
PUT /products
{
  "mappings": {
    "properties": {
      "name": { "type": "text" },
      "status": { "type": "keyword" },
      "price": { "type": "double" }
    }
  }
}

// Now show the query
GET /products/_search
{
  "query": {
    "bool": {
      "filter": [
        { "term": { "status": "active" } }
      ]
    }
  }
}
```

### 5. Semantic Naming

Use meaningful index/field names. Names carry intent for LLMs.

**Good:** `products`, `orders`, `user_id`, `created_at`, `is_active`
**Bad:** `index1`, `field1`, `data`, `flag`

---

## Code Example Standards

### JSON Formatting (ES REST API)

```json
// Use clear formatting with proper indentation
GET /products/_search
{
  "query": {
    "bool": {
      "must": [
        { "match": { "name": "wireless headphones" } }
      ],
      "filter": [
        { "term": { "status": "active" } },
        { "range": { "price": { "lte": 100 } } }
      ]
    }
  }
}
```

### Java Code (Client/Indexing)

```java
// Use elasticsearch-java client with type-safe builders
SearchResponse<Product> response = client.search(s -> s
    .index("products")
    .query(q -> q
        .bool(b -> b
            .must(m -> m.match(t -> t.field("name").query("wireless headphones")))
            .filter(f -> f.term(t -> t.field("status").value("active")))
        )
    ),
    Product.class
);
```

### Comments

- Explain _why_, not _what_
- Highlight performance implications
- Point out common pitfalls

### Language Tags

- `json` — Elasticsearch REST API (mappings, queries, settings, aggregations)
- `java` — Application code (elasticsearch-java client, Spring Data ES, BulkIngester)
- `yaml` — Cluster/node configuration (elasticsearch.yml)

---

## When to Include Application Code

**Default: JSON (ES REST API)**

Most references should focus on Elasticsearch DSL patterns. This keeps examples portable.

**Include Java Code When:**

- Client library usage (elasticsearch-java, Spring Data ES)
- Bulk indexing patterns (BulkIngester, BulkProcessor)
- Connection pooling and timeout configuration
- Kafka/MQ integration patterns

**Format for Mixed Examples:**

````markdown
**Incorrect (single-document indexing loop):**

```java
for (Product product : products) {
    client.index(i -> i
        .index("products")
        .id(product.getId())
        .document(product)
    );
}
```

**Correct (bulk indexing):**

```java
BulkRequest.Builder br = new BulkRequest.Builder();
for (Product product : products) {
    br.operations(op -> op
        .index(idx -> idx
            .index("products")
            .id(product.getId())
            .document(product)
        )
    );
}
client.bulk(br.build());
```
````

---

## Impact Level Guidelines

| Level | Improvement | Use When |
|-------|-------------|----------|
| **CRITICAL** | 10-100x | Missing filter context, dynamic mapping explosion, wrong node roles |
| **HIGH** | 5-20x | Wrong shard sizing, no bulk API, unoptimized analyzers |
| **MEDIUM-HIGH** | 2-5x | Deep pagination, missing source filtering, connection pool issues |
| **MEDIUM** | 1.5-3x | Aggregation cardinality, refresh interval tuning |
| **LOW-MEDIUM** | 1.2-2x | Slow log tuning, monitoring configuration |
| **LOW** | Incremental | Advanced patterns, edge cases |

---

## Reference Standards

**Primary Sources:**

- Official Elasticsearch documentation
- Elastic blog and engineering posts
- Elasticsearch: The Definitive Guide
- Elastic community best practices

**Format:**

```markdown
Reference:
[Elasticsearch Bool Query](https://www.elastic.co/guide/en/elasticsearch/reference/current/query-dsl-bool-query.html)
```

---

## Review Checklist

Before submitting a reference:

- [ ] Title is clear and action-oriented
- [ ] Impact level matches the performance gain
- [ ] impactDescription includes quantification
- [ ] Explanation is concise (1-2 sentences)
- [ ] Has at least 1 **Incorrect** example
- [ ] Has at least 1 **Correct** example
- [ ] Uses semantic naming (products, orders, not index1)
- [ ] Comments explain _why_, not _what_
- [ ] Trade-offs mentioned if applicable
- [ ] Reference links included
- [ ] ES version noted when relevant (v8 vs v9)
