---
name: mongodb-best-practices
description: MongoDB performance optimization and best practices. Use this skill when writing, reviewing, or optimizing MongoDB queries, schema designs, aggregation pipelines, or database configurations.
license: MIT
metadata:
  author: community
  version: "1.0.0"
  organization: MongoDB Community
  date: February 2026
  abstract: Comprehensive MongoDB performance optimization guide for developers. Contains performance rules across 11 categories, prioritized by impact from critical (query performance, indexing strategy) to incremental (advanced features). Each rule includes detailed explanations, incorrect vs. correct code examples using mongosh and Node.js Driver, execution plan analysis, and specific performance metrics to guide automated optimization and code generation.
---

# MongoDB Best Practices

Comprehensive performance optimization guide for MongoDB. Contains rules across 11 categories, prioritized by impact to guide automated query optimization, schema design, and operational excellence.

## When to Apply

Reference these guidelines when:
- Writing MongoDB queries or designing document schemas
- Creating indexes or optimizing query performance
- Building aggregation pipelines
- Reviewing database performance issues
- Configuring replica sets, sharding, or connection management
- Working with MongoDB Atlas or self-managed deployments
- Implementing security, authentication, or authorization patterns

## Rule Categories by Priority

| Priority | Category | Impact | Prefix |
|----------|----------|--------|--------|
| 1 | Query Performance | CRITICAL | `query-` |
| 2 | Indexing Strategy | CRITICAL | `index-` |
| 3 | Schema Design | CRITICAL | `schema-` |
| 4 | Aggregation Pipeline | HIGH | `agg-` |
| 5 | Connection Management | HIGH | `conn-` |
| 6 | Data Modeling Patterns | MEDIUM-HIGH | `model-` |
| 7 | Security & Authentication | MEDIUM-HIGH | `security-` |
| 8 | Replication & High Availability | MEDIUM | `repl-` |
| 9 | Sharding | MEDIUM | `shard-` |
| 10 | Monitoring & Diagnostics | LOW-MEDIUM | `monitor-` |
| 11 | Advanced Features | LOW | `advanced-` |

## How to Use

Read individual rule files for detailed explanations and code examples:

```
references/query-covered-queries.md
references/index-esr-rule.md
references/_sections.md
```

Each rule file contains:
- Brief explanation of why it matters
- Incorrect code example with explanation
- Correct code example with explanation
- Optional explain() output or metrics
- Additional context and references
- MongoDB Atlas-specific notes (when applicable)

## References

- https://www.mongodb.com/docs/manual/
- https://www.mongodb.com/docs/drivers/node/current/
- https://www.mongodb.com/docs/manual/core/aggregation-pipeline/
- https://www.mongodb.com/docs/manual/indexes/
- https://www.mongodb.com/docs/atlas/
