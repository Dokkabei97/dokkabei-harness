---
type: llm
focus: last_message
---

Ground truth (Elasticsearch terms aggregation docs): each shard returns its top `shard_size` terms, and shard_size defaults to `size * 1.5 + 10` (so 25 for size 10). Ordering by ascending `_count` produces an unbounded error that Elasticsearch cannot accurately report (doc_count_error_upper_bound is -1); for rare terms use the `rare_terms` aggregation, and to get all terms exactly use the `composite` aggregation. `show_term_doc_count_error: true` exposes doc_count_error_upper_bound (only meaningful for descending count order).

PASS only if ALL of the following hold:
1. It states the default shard_size correctly as size*1.5+10, i.e. 25 terms per shard for size 10 (saying "25" with the formula, or the formula applied correctly). A wrong default (e.g. "each shard sends exactly 10", "size*1.5" without +10 giving 15, or "shard_size = size") fails this point.
2. For the "least sold" dashboard it says ascending _count ordering has unbounded / unreportable error and recommends replacing it with `rare_terms` and/or a `composite` aggregation full scan (or an exact alternative computed outside ES), rather than merely raising shard_size.
3. For the top-10 dashboard it recommends raising shard_size (and/or monitoring via show_term_doc_count_error / doc_count_error_upper_bound).
FAIL if any point is missing or factually wrong.
