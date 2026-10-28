> **English** · [한국어](README_KO.md)

# search

> Elasticsearch specialist layer — the pitfalls even strong senior engineers miss in ES/Lucene performance, mapping, cluster ops, the Kotlin/Java and Go clients, ingestion, relevance with Korean (nori) analysis, and vector/hybrid search. Every item has an ID, applicability conditions, a detection signal, the mechanism, a prescription, a counter-case, a verification method, and an official source.

Install: `/plugin install search@dokkabei-harness`

## Design

- **Three entry hubs, many references.** Only three skills are model-invocable. Each `SKILL.md` is a short triage index (symptom → reference file → item ID); the knowledge lives in `references/*.md` as ID'd items (`ES-*`, `LUC-*`, `KO-*`, `VEC-*`). This keeps the skill listing small so descriptions are not dropped from the listing budget.
- **Guidance, not enforcement.** Hubs tell the model to confirm project facts first (ES version, deployment, client, mapping source, ingestion path) and never to assume a stack. Items carry `적용` (applicability) and `반례` (counter-case) so they can be discarded when they don't fit.
- **Project-specific selection.** Which item IDs apply to a given repository is meant to be recorded in that project's `CLAUDE.md`/`.claude/rules` (e.g. via `workflow:project-rules`); this plugin is the stack-wide layer.

## Components

### Skills (model-invocable entry hubs)

| Skill | Scope | Item prefixes |
|---|---|---|
| `es-deep-patterns` | ES/Lucene performance, shards, bulk indexing, mapping, query/aggregation cost, segments/merge, JVM/circuit breakers/429, Kotlin/Java and Go clients, Kafka/Spark→ES ingestion, symptom-based diagnostics | `ES-SHD` `ES-IDX` `ES-MAP` `ES-QRY` `ES-AGG` `LUC-SEG` `LUC-EXE` `ES-JVM` `ES-OPS` `ES-CLI` `ES-ING` |
| `search-relevance-engineering` | Relevance, nori analysis, synonyms, autocomplete, BM25/multi_match, reranking/RRF, quality evaluation | `KO-ANA` `KO-SYN` `KO-AC` `ES-REL` `ES-RNK` `ES-EVL` |
| `vector-hybrid-search-patterns` | dense_vector memory/quantization, kNN filters and recall, hybrid fusion, Korean embeddings | `VEC-MEM` `VEC-IDX` `VEC-QRY` `VEC-HYB` `VEC-EMB` |

User-invoked only: `search-team-orchestrator` (`/search-team-orchestrator`) — fans out cross-domain work to the agents below and merges one report.

### Commands (user-invoked, `disable-model-invocation: true`)

- `/es-query-review` — query DSL and aggregation cost review against `ES-QRY`/`ES-AGG`/`LUC-EXE`.
- `/es-mapping-review` — mapping and analyzer review, breaking-change detection.
- `/index-lifecycle` — shard sizing, ILM, zero-downtime reindex runbook, and ingestion-path checks (`--pipeline`, formerly `/index-pipeline-check`).
- `/vector-search-review` — vector/hybrid review with memory estimate.
- `/search-quality` — golden query set, `_rank_eval`, online evaluation design.

### Agents

| Agent | Role | Preloaded skills |
|---|---|---|
| `es-query-optimizer` | Query and cluster performance (profile, aggregations, mapping cost, shards, JVM) | `es-deep-patterns` |
| `search-relevance-engineer` | Relevance, Korean analysis, reranking, vector/hybrid | `search-relevance-engineering`, `vector-hybrid-search-patterns` |
| `search-service-architect` | Client, timeouts/retries, bulk, Kafka/Spark ingestion, reindex | `es-deep-patterns` |
| `search-code-reviewer` | Team tech-lead-style pre-PR Kotlin review (`[Sug]`/`[Q]`/`[High]`), invoked explicitly | — |

## Archived (2026-10)

Moved to `archive/components/search/` — specialist content was extracted into the hubs' references:
skills `kotlin-es-client-patterns`, `lucene-internals`, `search-data-pipeline`, `search-diagnostics` (now `es-deep-patterns/references/diagnostics.md`), `search-observability`, `search-pipeline-reranking`; commands `index-pipeline-check` (merged into `/index-lifecycle --pipeline`), `search-architecture-review`; agents `hybrid-search-architect` (merged into `search-relevance-engineer`), `search-pipeline-engineer` (merged into `search-service-architect`).

## Notes

- Items state the ES version they apply to (8.x vs 9.x differences are called out, e.g. default `dense_vector` index options, `exclude_source_vectors`, Rest5Client). Defaults and numbers come from the linked official docs; verify against your cluster version.
- Nothing here touches a live cluster. Agents and commands produce findings with the exact requests to run for verification (`_profile`, `_analyze`, `_rank_eval`, recall@k).
