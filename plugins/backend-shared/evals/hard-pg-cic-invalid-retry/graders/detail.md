---
type: llm
focus: last_message
---

This case checks specialist detail, not general advice. Judge only the final reply.

PASS only if the reply states ALL of the following:
1. The cancelled CREATE INDEX CONCURRENTLY left behind an index named idx_users_email that is INVALID (pg_index.indisvalid = false / shown as INVALID in \d).
2. The re-run did nothing because IF NOT EXISTS only checks that a relation with that name exists (it just emits a NOTICE) — so the "successful" second migration silently skipped the build. The existing index is not checked for validity.
3. The INVALID index is ignored by the planner (hence the Seq Scan) but is still maintained on every INSERT/UPDATE, which explains the added write latency.
4. A concrete recovery: find it via pg_index WHERE NOT indisvalid (or \d), then DROP INDEX CONCURRENTLY and re-create it CONCURRENTLY, or REINDEX INDEX CONCURRENTLY.

FAIL if any item is missing, if the reply attributes the Seq Scan mainly to stale statistics / need for ANALYZE / low selectivity, or if it never explains why the second run "succeeded" without building the index. Mentioning extra good practices (pre-check step before IF NOT EXISTS, disabling statement_timeout for the CIC session) is fine but not required.
