# elasticsearch-best-practices

> **Note:** `CLAUDE.md` is a symlink to this file.

## Overview

Elasticsearch performance optimization and best practices for enterprise deployments. Use this skill when writing, reviewing, or optimizing Elasticsearch queries, mappings, cluster configurations, or Java client integrations.

## Structure

```
elasticsearch-best-practices/
  SKILL.md       # Main skill file - read this first
  AGENTS.md      # This navigation guide
  CLAUDE.md      # Symlink to AGENTS.md
  references/    # Detailed reference files
```

## Usage

1. Read `SKILL.md` for the main skill instructions
2. Browse `references/` for detailed documentation on specific topics
3. Reference files are loaded on-demand - read only what you need

## Reference Categories

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

Reference files are named `{prefix}-{topic}.md` (e.g., `query-filter-vs-must.md`).

## Available References

**Mapping & Schema Design** (`mapping-`):
- `references/mapping-text-vs-keyword.md`
- `references/mapping-explicit-mapping.md`
- `references/mapping-nested-vs-object.md`
- `references/mapping-multi-field.md`

**Query Performance** (`query-`):
- `references/query-filter-vs-must.md`
- `references/query-bool-optimization.md`
- `references/query-pagination-search-after.md`
- `references/query-source-filtering.md`
- `references/query-profile-api.md`

**Cluster Architecture** (`cluster-`):
- `references/cluster-node-roles.md`
- `references/cluster-heap-memory.md`
- `references/cluster-hot-warm-cold.md`

**Shard Strategy** (`shard-`):
- `references/shard-sizing.md`
- `references/shard-primary-count.md`
- `references/shard-index-template.md`

**Indexing & Bulk** (`indexing-`):
- `references/indexing-bulk-api.md`
- `references/indexing-bulk-ingester.md`
- `references/indexing-initial-load.md`
- `references/indexing-refresh-interval.md`

**Analyzer** (`analyzer-`):
- `references/analyzer-custom-chain.md`
- `references/analyzer-nori-korean.md`
- `references/analyzer-ngram-autocomplete.md`

**Client & Framework** (`client-`):
- `references/client-spring-data-query-string.md`
- `references/client-elasticsearch-java.md`
- `references/client-connection-pool.md`

**Streaming & Integration** (`streaming-`):
- `references/streaming-kafka-bulk-strategy.md`
- `references/streaming-backpressure.md`

**Aggregation** (`agg-`):
- `references/agg-composite-pagination.md`
- `references/agg-terms-cardinality.md`

**Monitoring** (`monitor-`):
- `references/monitor-slow-log.md`

---

*30 reference files across 10 categories*
