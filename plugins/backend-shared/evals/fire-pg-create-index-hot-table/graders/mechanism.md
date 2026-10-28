---
type: llm
focus: last_message
---

PASS if the reply uses CREATE INDEX CONCURRENTLY, notes it cannot run inside a transaction block (so the Flyway migration must be non-transactional / in its own file), AND warns that a failed concurrent build leaves an INVALID index (checking pg_index.indisvalid, then DROP INDEX CONCURRENTLY and retry or REINDEX CONCURRENTLY; or that IF NOT EXISTS will silently skip an INVALID index).
FAIL if it uses a plain CREATE INDEX, or never mentions the INVALID-index failure mode.
