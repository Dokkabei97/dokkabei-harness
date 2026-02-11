# mongodb-best-practices

> **Note:** `CLAUDE.md` is a symlink to this file.

## Overview

MongoDB performance optimization and best practices. Use this skill when writing, reviewing, or optimizing MongoDB queries, schema designs, aggregation pipelines, or database configurations.

## Structure

```
mongodb-best-practices/
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

Reference files are named `{prefix}-{topic}.md` (e.g., `query-covered-queries.md`).

## Available References

**Query Performance** (`query-`):
- `references/query-covered-queries.md`
- `references/query-projection.md`
- `references/query-regex-optimization.md`
- `references/query-selective-filters.md`
- `references/query-sort-with-index.md`

**Indexing Strategy** (`index-`):
- `references/index-compound-order.md`
- `references/index-esr-rule.md`
- `references/index-partial.md`
- `references/index-redundant.md`
- `references/index-sparse.md`
- `references/index-ttl.md`
- `references/index-wildcard.md`

**Schema Design** (`schema-`):
- `references/schema-anti-patterns.md`
- `references/schema-bucket-pattern.md`
- `references/schema-document-size.md`
- `references/schema-embedding-vs-referencing.md`
- `references/schema-polymorphic.md`
- `references/schema-schema-validation.md`

**Aggregation Pipeline** (`agg-`):
- `references/agg-early-filtering.md`
- `references/agg-lookup-optimization.md`
- `references/agg-memory-limits.md`
- `references/agg-pipeline-ordering.md`

**Connection Management** (`conn-`):
- `references/conn-pool-sizing.md`
- `references/conn-retry-logic.md`
- `references/conn-timeout-settings.md`

**Data Modeling Patterns** (`model-`):
- `references/model-computed-pattern.md`
- `references/model-extended-reference.md`
- `references/model-outlier-pattern.md`
- `references/model-subset-pattern.md`

**Security & Authentication** (`security-`):
- `references/security-authentication.md`
- `references/security-field-level-encryption.md`
- `references/security-injection-prevention.md`
- `references/security-rbac.md`

**Replication & High Availability** (`repl-`):
- `references/repl-read-preference.md`
- `references/repl-write-concern.md`

**Sharding** (`shard-`):
- `references/shard-key-selection.md`
- `references/shard-targeted-queries.md`
- `references/shard-zone-sharding.md`

**Monitoring & Diagnostics** (`monitor-`):
- `references/monitor-currentop.md`
- `references/monitor-explain-plans.md`
- `references/monitor-profiler.md`

**Advanced Features** (`advanced-`):
- `references/advanced-change-streams.md`
- `references/advanced-text-search.md`
- `references/advanced-timeseries.md`
- `references/advanced-transactions.md`

---

*45 reference files across 11 categories*
