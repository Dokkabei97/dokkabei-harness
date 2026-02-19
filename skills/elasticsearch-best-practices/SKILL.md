---
name: elasticsearch-best-practices
description: Elasticsearch performance optimization and best practices for enterprise deployments. Use this skill when writing, reviewing, or optimizing Elasticsearch queries, mappings, cluster configurations, or Java client integrations.
license: MIT
metadata:
  author: community
  version: "1.0.0"
  organization: Community
  date: February 2026
  abstract: Comprehensive Elasticsearch performance optimization guide for enterprise-scale deployments (10+ nodes, 100M+ documents, 1000+ QPS). Contains 30 performance rules across 10 categories, prioritized by impact from critical (mapping design, query performance, cluster architecture) to incremental (monitoring). Each rule includes detailed explanations, incorrect vs. correct examples (JSON DSL and Java code), and specific performance metrics. Covers ES 8.x baseline with ES 9.x migration notes.
---

# Elasticsearch Best Practices

Comprehensive performance optimization guide for Elasticsearch, targeting enterprise-scale deployments. Contains 30 rules across 10 categories, prioritized by impact to guide automated query optimization, mapping design, and cluster configuration.

## When to Apply

Reference these guidelines when:
- Designing index mappings and field types
- Writing or optimizing search queries (bool, filter, aggregation)
- Configuring cluster architecture and node roles
- Implementing bulk indexing pipelines (BulkIngester, Kafka integration)
- Using Spring Data ES or elasticsearch-java client
- Tuning shard sizing and index lifecycle management
- Building custom analyzers (Korean/Nori, autocomplete)
- Diagnosing slow queries and cluster performance

## Rule Categories by Priority

| Priority | Category | Impact | Prefix |
|----------|----------|--------|--------|
| 1 | Mapping & Schema Design | CRITICAL | `mapping-` |
| 2 | Query Performance | CRITICAL | `query-` |
| 3 | Cluster Architecture | CRITICAL | `cluster-` |
| 4 | Shard Strategy | HIGH | `shard-` |
| 5 | Indexing & Bulk | HIGH | `indexing-` |
| 6 | Analyzer | HIGH | `analyzer-` |
| 7 | Client & Framework | HIGH | `client-` |
| 8 | Streaming & Integration | MEDIUM-HIGH | `streaming-` |
| 9 | Aggregation | MEDIUM | `agg-` |
| 10 | Monitoring | LOW-MEDIUM | `monitor-` |

## How to Use

Read individual rule files for detailed explanations and examples:

```
references/query-filter-vs-must.md
references/indexing-bulk-ingester.md
references/client-spring-data-query-string.md
references/_sections.md
```

Each rule file contains:
- Brief explanation of why it matters
- Incorrect example with explanation
- Correct example with explanation
- Performance comparison tables (where applicable)
- Migration guides (where applicable)
- Additional context and references

## Key Highlights

- **filter vs must**: Put non-scoring clauses in `filter` for 2-10x speedup via filter cache
- **BulkIngester(v9)**: Migrate from BulkProcessor with size-based flush (15MB) instead of count-based
- **Spring Data ES**: Avoid method name derivation (`findByXxx`) → use `@Query` or elasticsearch-java client
- **Kafka integration**: Match consuming strategy to bulk approach — no double-buffering

## References

- https://www.elastic.co/guide/en/elasticsearch/reference/current/
- https://www.elastic.co/guide/en/elasticsearch/client/java-api-client/current/
- https://docs.spring.io/spring-data/elasticsearch/reference/
- https://www.elastic.co/blog/
