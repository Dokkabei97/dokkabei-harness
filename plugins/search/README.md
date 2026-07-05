> **English** · [한국어](README_KO.md)

# search

> Elasticsearch search-engineering specialist harness — designs, reviews, and diagnoses query optimization, relevance tuning, vector/hybrid search, and indexing pipelines with a team of specialist agents.

## Overview

`search` is a harness dedicated to the search platform team that works on production Elasticsearch (8.x, Korean nori context) search systems. It covers the full range of the search domain: ES query DSL optimization, search relevance (BM25/analyzers/synonyms) tuning, vector and hybrid search (kNN, dense_vector, HNSW, RRF), Kafka/Spark/Iceberg data pipeline integration, index lifecycle, and symptom-based diagnostics (`_profile`/`_explain`/`_termvectors`).

The core design is an **Expert Pool + Fan-out/Fan-in** team orchestration. The `search-team-orchestrator` skill classifies a task into Single/Multi/Full Review, then either dispatches one of five domain-specialist agents singly or fans them out in parallel, and afterwards fans in the results into a single unified report. It is composed as a three-layer structure (command → agent → skill) that references slash commands when a formalized review is needed, and skills when deep knowledge is needed.

It includes the Kotlin/Spring Boot search-service code perspective, but the orchestrator and agents draw their boundary at producing design, review, and diagnostic advice without directly modifying code or accessing the ES cluster.

## Components

### Commands

- `es-query-review` — ES query DSL review. Anti-pattern detection, complexity rating, optimization suggestions.
- `es-mapping-review` — Index mapping review. Field type validation, analyzer checks, compatibility analysis.
- `vector-search-review` — Vector search review. `dense_vector` mapping validation, kNN query optimization, embedding pipeline analysis, hybrid (RRF) configuration checks.
- `search-architecture-review` — Multi-stage retrieval architecture review. Pipeline stage assessment, missing stage detection, latency budget analysis.
- `search-quality` — Search quality evaluation. Relevance test case design, metric frameworks, A/B test specifications.
- `index-lifecycle` — Index lifecycle management. ILM policy design, reindexing plans, shard sizing.
- `index-pipeline-check` — Indexing pipeline health check. Kafka consumer configuration validation, ES bulk indexing pattern review, monitoring setup audit.

### Agents

The five-member Expert Pool orchestrated via Fan-out by the orchestrator:

- `es-query-optimizer` — Query DSL performance analysis and optimization. Anti-pattern detection, `_profile` output interpretation, query rewrite suggestions. (QO)
- `search-relevance-engineer` — Search quality and relevance tuning. Analyzer design, scoring strategy, synonym management, Korean morphological analysis, quality evaluation. (RE)
- `search-service-architect` — Kotlin (Spring Boot) + ES service architecture design. Client setup, bulk indexing, async search, circuit breaker, observability. (SA)
- `hybrid-search-architect` — Vector, semantic, and hybrid (RRF) search design. Embedding model selection, `dense_vector` mapping, HNSW tuning, Korean embedding optimization. (HA)
- `search-pipeline-engineer` — Data pipeline → ES indexing integration. Kafka consumer, Spark batch indexing, Iceberg sync, DLQ, pipeline monitoring. (PE)

On-demand reviewer invoked explicitly, separate from the Pool:

- `search-code-reviewer` — Search-service Kotlin code review (tech-lead style, `[Sug]`/`[Q]`/`[High]` tags). Naming, hexagonal boundaries, DTO, Nullable, hardcoding, search-domain perspective. Developers invoke it directly for self-review before a PR (not a target for automatic Fan-out).

### Skills

- `search-team-orchestrator` — Team orchestrator. Task classification (Single/Multi/Full Review), keyword- and symptom-based routing, parallel dispatch, unified report generation.
- `es-deep-patterns` — Deep patterns/anti-patterns for ES queries, mappings, indexing, and operations (Korean analysis support).
- `search-relevance-engineering` — Relevance tuning, analyzer design, multi-field search, synonyms, BM25 tuning, Korean analyzers, quality metrics.
- `vector-hybrid-search-patterns` — Vector (kNN)/semantic (ELSER, embeddings)/hybrid (RRF) design. `dense_vector` mapping, HNSW tuning, Korean embeddings, RRF fusion, Kotlin client patterns.
- `search-pipeline-reranking` — Multi-stage retrieval, reranking (rescore/Retriever/LTR/cross-encoder), query understanding, result diversification, personalization. Includes the ES 8.x Retriever abstraction.
- `search-data-pipeline` — Data ingestion pipeline for loading into ES. Kafka consumer patterns, Iceberg/Spark/Trino batch reindexing, pipeline monitoring.
- `kotlin-es-client-patterns` — Kotlin/Python ES integration implementation. Client setup, search implementation, bulk indexing, testing, common mistakes (elasticsearch-java v8, elasticsearch-py).
- `lucene-internals` — Segment/Lucene-level performance diagnostics. `_profile`/`_explain` interpretation, scoring internals, inverted index structure, merge policy tuning, OS-level performance factors.
- `search-observability` — Search metrics collection, click tracking, search A/B testing, quality monitoring, slow query analysis. Micrometer, Kotlin/Spring Boot dashboard design.
- `search-diagnostics` — Symptom-based diagnostics hub. A decision tree that routes symptoms such as no results, misordering, slowness, and unstable latency to the correct diagnostic API (`_profile`/`_explain`/`_termvectors`/`_validate`/`_analyze`/`_tasks`/`hot_threads`/`breaker`).

## Usage

- **Formalized review**: Use slash commands such as `/es-query-review`, `/vector-search-review`, `/search-architecture-review` to instantly inspect a specific target.
- **Complex task orchestration**: When the keywords "search team" or "harness" or a task that crosses two or more domains is detected, `search-team-orchestrator` is triggered automatically to select and combine the appropriate experts.
  - Single (single domain) → dispatch 1, Multi (2–3 crossing) → parallel Fan-out of the relevant agents, Full Review (comprehensive review/new design) → Fan-out all five.
  - Predefined scenario examples: new search feature design (SA+RE+QO), vector search introduction (HA+SA+RE), indexing pipeline check (PE+SA), comprehensive search performance diagnosis (QO+SA+PE).
- **Symptom-based diagnostics**: When search misbehaves (documents not matched / order off / slow / p99 spikes), `search-diagnostics` routes the symptom to a diagnostic API and, if needed, connects to the RE or QO agent.
- **Pre-PR self-review**: Explicitly invoke `search-code-reviewer` to inspect Kotlin search-service code locally.
- **Deep learning**: If deeper study is needed after agent analysis, the orchestrator guides you to per-domain skills (es-deep-patterns, lucene-internals, etc.) as references.

## Dependencies

There are no forced dependencies (`requires`) in `plugin.json`/`marketplace.json`. However, when the search service is implemented in Kotlin/Spring Boot it is complementary to use together with the `backend-kotlin` plugin, and when deep SQL, architecture, or performance reviews are needed, with the `analyze` plugin.

## Notes

- The target stack presumes **Elasticsearch 8.x**, and Korean analysis presumes the **nori** morphological analyzer context.
- The orchestrator and the five-member Pool agents **do not directly modify code or access the ES cluster** — they produce design, review, and diagnostic advice, and the actual changes are performed by the user/developer.
- `search-code-reviewer` is not a target for automatic Fan-out and must be **invoked explicitly** for pre-PR self-review.
- The outputs are relevance and performance improvement advice, and do not replace production load testing or verification based on actual indexed data. Confirm destructive operations such as mapping changes and reindexing in a verification environment before applying them.
