---
type: llm
focus: last_message
---

This case checks a specific, non-obvious mechanism. Judge only the final reply.

Ground truth: new rows are already populated by the new app, so the leftover NULL rows are old rows the backfill never touched. `FOR UPDATE SKIP LOCKED` skips any row currently row-locked by a concurrent transaction (the hot-table status UPDATEs). Near the end of the backfill, if every remaining `region IS NULL` row in the scan happens to be locked at that instant, the subquery returns 0 rows, ROW_COUNT = 0, and the loop exits treating "0 rows updated" as "done" — while NULL rows remain. Staging has no concurrent writers, so it never happens there.

PASS only if the reply:
1. Identifies SKIP LOCKED skipping rows locked by concurrent application transactions as the cause of leftover NULL rows, AND
2. Identifies the exit condition `EXIT WHEN n = 0` (zero rows updated) as wrong because 0 updated ≠ 0 remaining, AND
3. Proposes a fix whose termination is based on remaining rows (e.g. loop until NOT EXISTS / count of region IS NULL = 0, retry/sleep when a batch is empty but rows remain, or drop SKIP LOCKED / use keyset PK-range batches that wait on locks) and/or asserting zero remaining NULL rows before V43/V44.

FAIL if the reply blames the leftovers mainly on old app pods / new inserts with NULL, on the COMMIT-in-DO-block transaction issue, or on replication/visibility, without stating the SKIP LOCKED + zero-row-exit mechanism. Additional valid advice (keyset batching instead of ORDER BY/LIMIT rescans, batch pacing, replica lag) is fine.
