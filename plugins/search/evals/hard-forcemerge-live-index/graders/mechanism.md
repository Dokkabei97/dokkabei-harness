---
type: llm
focus: last_message
---

Ground truth (Elasticsearch force merge API docs): force merge should only be run on a read-only index; it can produce very large segments (greater than 5 GB, the default index.merge.policy.max_merged_segment) that are not eligible for regular/automatic merges, so soft-deleted (tombstoned) documents inside them keep accumulating and are not reclaimed, increasing disk usage and hurting search.

PASS only if ALL of the following hold:
1. It explains the specific mechanism: the force-merged segment(s) exceed the ~5 GB max merged segment size and are therefore excluded from (not considered by) the normal merge policy, so deleted/updated documents inside them are not reclaimed and docs.deleted keeps growing.
2. It says NOT to keep (or increase) force merging this index while it is still receiving writes/updates — force merge only on read-only / no-longer-written indices (e.g. after rollover, ILM warm phase).
FAIL if it attributes the problem only to generic causes (merge I/O cost, "segments need time", refresh, need more frequent merges), recommends running the cron more often, or never mentions that the oversized segments fall out of regular merging. Mentioning only_expunge_deletes or index restructuring as extra options is fine but does not substitute for point 1.
