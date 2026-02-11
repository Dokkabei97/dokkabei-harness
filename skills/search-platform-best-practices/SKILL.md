---
name: search-platform-best-practices
description: Elasticsearch/OpenSearch performance optimization and best practices. Use this skill when writing, reviewing, or optimizing search queries, mapping designs, cluster configurations, or indexing strategies.
license: MIT
metadata:
  author: search-engineering
  version: "1.0.0"
  organization: Search Engineering
  date: February 2026
  abstract: Comprehensive Elasticsearch/OpenSearch performance optimization guide for developers and SREs. Contains performance rules across 14 categories, prioritized by impact from critical (mapping design, query performance, cluster architecture) to incremental (advanced features). Each rule includes detailed explanations, incorrect vs. correct JSON DSL examples, REST API patterns, and specific performance metrics to guide automated optimization and code generation.
---

# Search Platform Best Practices

Comprehensive performance optimization guide for Elasticsearch and OpenSearch. Contains rules across 14 categories, prioritized by impact to guide automated query optimization, mapping design, and cluster management.

## When to Apply

Reference these guidelines when:
- Writing search queries or designing index mappings
- Implementing analyzers for Korean/CJK or multi-language search
- Reviewing search performance issues or slow queries
- Configuring cluster topology, shard strategies, or node roles
- Optimizing bulk indexing or data ingestion pipelines
- Managing index lifecycle (ILM), data tiers, or retention policies
- Setting up cross-cluster search or replication
- Deploying Elasticsearch on Kubernetes with ECK
- Implementing security (TLS, RBAC, field-level security)
- Building aggregation dashboards or analytics queries

## Rule Categories by Priority

| Priority | Category | Impact | Prefix |
|----------|----------|--------|--------|
| 1 | Mapping & Schema Design | CRITICAL | `mapping-` |
| 2 | Query Performance | CRITICAL | `query-` |
| 3 | Cluster & Node Architecture | CRITICAL | `cluster-` |
| 4 | Index & Shard Strategy | HIGH | `shard-` |
| 5 | Indexing Performance | HIGH | `indexing-` |
| 6 | Korean/CJK Search & Analyzers | HIGH | `analyzer-` |
| 7 | Security | MEDIUM-HIGH | `security-` |
| 8 | Aggregation Optimization | MEDIUM-HIGH | `agg-` |
| 9 | Resilience & Recovery | MEDIUM | `resilience-` |
| 10 | Data Lifecycle | MEDIUM | `lifecycle-` |
| 11 | Cross-Cluster | MEDIUM | `crosscluster-` |
| 12 | Monitoring & Diagnostics | LOW-MEDIUM | `monitor-` |
| 13 | Kubernetes / ECK Operations | LOW-MEDIUM | `k8s-` |
| 14 | Advanced Features | LOW | `advanced-` |

## How to Use

Read individual rule files for detailed explanations and JSON DSL examples:

```
references/mapping-text-vs-keyword.md
references/query-filter-context.md
references/_sections.md
```

Each rule file contains:
- Brief explanation of why it matters
- Incorrect JSON DSL example with explanation
- Correct JSON DSL example with explanation
- Optional Profile API output or metrics
- Additional context and references
- OpenSearch compatibility notes (when applicable)

## References

- https://www.elastic.co/guide/en/elasticsearch/reference/current/index.html
- https://opensearch.org/docs/latest/
- https://www.elastic.co/guide/en/elasticsearch/reference/current/tune-for-search-speed.html
- https://www.elastic.co/guide/en/elasticsearch/reference/current/tune-for-indexing-speed.html
- https://www.elastic.co/guide/en/cloud-on-k8s/current/index.html
