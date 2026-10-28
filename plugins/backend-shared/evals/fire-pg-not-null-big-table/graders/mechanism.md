---
type: llm
focus: last_message
---

PASS if the reply splits the change into steps — add the column as nullable (or with a non-volatile default), backfill in small keyset/PK-range batches with commits between them (not one big UPDATE), add a CHECK (col IS NOT NULL) NOT VALID constraint, VALIDATE it separately, then SET NOT NULL (which skips the full scan on PG12+ because of the validated CHECK) — AND sets lock_timeout before the locking DDL.
FAIL if it recommends a single `ALTER TABLE ... ADD COLUMN ... NOT NULL` / `SET NOT NULL` directly on the 300M-row table, or a single UPDATE backfill, or omits the CHECK NOT VALID → VALIDATE step.
