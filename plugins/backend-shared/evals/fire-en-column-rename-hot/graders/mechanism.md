---
type: llm
focus: last_message
---

PASS if the reply rejects a direct RENAME COLUMN during the rolling deploy and lays out an expand-contract sequence: add the new column, keep both in sync (dual-write or trigger) and backfill in batches, deploy code that reads the new column, stop using the old one, and only then drop the old column in a later deploy.
FAIL if it recommends a single ALTER TABLE ... RENAME COLUMN while old pods are running, or drops the old column before the code stops using it.
