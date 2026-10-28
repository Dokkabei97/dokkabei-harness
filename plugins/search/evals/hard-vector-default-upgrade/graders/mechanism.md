---
type: llm
focus: last_message
---

Ground truth: Elasticsearch 8.14 made `int8_hnsw` the default index_options type for new dense_vector (float) fields (release notes 8.14.0: "Make int8_hnsw our default index for new dense-vector fields"). Indices created on 8.12 with no index_options used plain `hnsw` (float). So after upgrading to 8.17, newly created indices from the unchanged template are int8-quantized: recall can drop, disk grows because the raw float vectors are kept on disk alongside the quantized copy, and the RAM/page-cache working set shrinks (~4x). The default only applies to newly created fields/indices.

PASS only if ALL of the following hold:
1. It identifies the cause as the changed default index_options for float dense_vector — new indices now default to int8_hnsw (scalar int8 quantization) instead of hnsw, with the change attributed to 8.14 (or "between 8.12 and 8.17" while naming int8_hnsw as the new default).
2. It explains the observed symptoms consistently with that: lower recall from quantization, more disk because raw floats are stored in addition to the quantized vectors, less page cache because only the quantized vectors + graph need to be in memory.
3. Remedy: set `index_options.type` explicitly in the template (e.g. `hnsw` to restore previous behavior, or keep int8_hnsw and recover recall via oversampling/rescoring with raw floats or larger num_candidates), verify with `_mapping?include_defaults=true` or recall measurement, and note existing indices need reindexing for a type change.
FAIL if it does not identify the int8_hnsw default change (e.g. blames analyzer, similarity, HNSW m/ef_construction defaults, segment count, or "upgrade bugs"), or claims a wrong default type.
