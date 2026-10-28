---
type: llm
focus: last_message
---

PASS if the reply explains that Dispatchers.IO is a shared pool with default parallelism of 64 (max(64, cores)), so a slow dependency starves every other IO user, AND recommends per-dependency bulkheads via Dispatchers.IO.limitedParallelism(n) (ideally sized to the DB connection pool, e.g. Hikari maximumPoolSize).
FAIL if it only suggests raising the global thread count or switching to virtual threads without mentioning the 64-thread shared limit and limitedParallelism bulkheads.
