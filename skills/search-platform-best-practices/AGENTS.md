# search-platform-best-practices

> **Note:** `CLAUDE.md` is a symlink to this file.

## Overview

Elasticsearch/OpenSearch performance optimization and best practices. Use this skill when writing, reviewing, or optimizing search queries, mapping designs, cluster configurations, or indexing strategies.

## Structure

```
search-platform-best-practices/
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

Reference files are named `{prefix}-{topic}.md` (e.g., `mapping-text-vs-keyword.md`).

## Available References

**Mapping & Schema Design** (`mapping-`):
- `references/mapping-explicit-mapping.md`
- `references/mapping-flattened-type.md`
- `references/mapping-ignore-above.md`
- `references/mapping-multi-field.md`
- `references/mapping-nested-vs-object.md`
- `references/mapping-reindex-strategy.md`
- `references/mapping-source-excludes.md`
- `references/mapping-text-vs-keyword.md`

**Query Performance** (`query-`):
- `references/query-aggregation-size-zero.md`
- `references/query-bool-optimization.md`
- `references/query-copy-to.md`
- `references/query-expensive-patterns.md`
- `references/query-filter-context.md`
- `references/query-match-vs-term.md`
- `references/query-pagination-search-after.md`
- `references/query-profile-api.md`
- `references/query-source-filtering.md`

**Cluster & Node Architecture** (`cluster-`):
- `references/cluster-dedicated-master.md`
- `references/cluster-heap-memory.md`
- `references/cluster-hot-warm-cold.md`
- `references/cluster-node-roles.md`
- `references/cluster-shard-limit.md`

**Index & Shard Strategy** (`shard-`):
- `references/shard-ilm-rollover.md`
- `references/shard-index-alias.md`
- `references/shard-index-template.md`
- `references/shard-primary-count.md`
- `references/shard-replica-count.md`
- `references/shard-shrink-split.md`
- `references/shard-sizing.md`

**Indexing Performance** (`indexing-`):
- `references/indexing-bulk-api.md`
- `references/indexing-id-generation.md`
- `references/indexing-ingest-pipeline.md`
- `references/indexing-initial-load.md`
- `references/indexing-merge-policy.md`
- `references/indexing-translog.md`

**Korean/CJK Search & Analyzers** (`analyzer-`):
- `references/analyzer-autocomplete-ngram.md`
- `references/analyzer-chosung-search.md`
- `references/analyzer-custom-chain.md`
- `references/analyzer-korean-tokenizer.md`
- `references/analyzer-nori-decompound.md`
- `references/analyzer-synonym-filter.md`
- `references/analyzer-user-dictionary.md`

**Security** (`security-`):
- `references/security-api-key.md`
- `references/security-audit-logging.md`
- `references/security-authentication.md`
- `references/security-field-document-level.md`
- `references/security-rbac.md`
- `references/security-tls-encryption.md`

**Aggregation Optimization** (`agg-`):
- `references/agg-composite.md`
- `references/agg-dashboard-optimization.md`
- `references/agg-date-histogram.md`
- `references/agg-depth-limit.md`
- `references/agg-sampler.md`
- `references/agg-terms-size.md`

**Resilience & Recovery** (`resilience-`):
- `references/resilience-circuit-breaker.md`
- `references/resilience-cluster-health.md`
- `references/resilience-forced-awareness.md`
- `references/resilience-shard-allocation.md`
- `references/resilience-snapshot.md`

**Data Lifecycle** (`lifecycle-`):
- `references/lifecycle-data-stream.md`
- `references/lifecycle-forcemerge.md`
- `references/lifecycle-ilm-policy.md`
- `references/lifecycle-searchable-snapshot.md`
- `references/lifecycle-tiered-storage.md`

**Cross-Cluster** (`crosscluster-`):
- `references/crosscluster-remote-cluster.md`
- `references/crosscluster-replication.md`
- `references/crosscluster-search.md`

**Monitoring & Diagnostics** (`monitor-`):
- `references/monitor-cat-api.md`
- `references/monitor-gc-heap.md`
- `references/monitor-node-stats.md`
- `references/monitor-slow-log.md`
- `references/monitor-stack-monitoring.md`
- `references/monitor-tasks-api.md`
- `references/monitor-thread-pool.md`

**Kubernetes / ECK Operations** (`k8s-`):
- `references/k8s-eck-resources.md`
- `references/k8s-init-container.md`
- `references/k8s-pdb.md`
- `references/k8s-rolling-upgrade.md`
- `references/k8s-storage.md`
- `references/k8s-topology.md`

**Advanced Features** (`advanced-`):
- `references/advanced-alerting.md`
- `references/advanced-esql.md`
- `references/advanced-ltr.md`
- `references/advanced-painless.md`
- `references/advanced-runtime-fields.md`
- `references/advanced-semantic-search.md`
- `references/advanced-transform.md`
- `references/advanced-vector-search.md`

---

*88 reference files across 14 categories*
