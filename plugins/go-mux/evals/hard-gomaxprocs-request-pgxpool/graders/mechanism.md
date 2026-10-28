---
type: llm
focus: last_message
---

All three of the following are required for PASS:
(a) GOMAXPROCS: states that Go 1.25's container-aware default GOMAXPROCS is derived from the cgroup CPU *limit* (quota/period, e.g. cpu.max) and does NOT consider the CPU *request*, so with no CPU limit GOMAXPROCS stays at the node's logical CPU count (64 here); recommends setting GOMAXPROCS explicitly (env var or runtime.GOMAXPROCS, e.g. around 2) or adding a CPU limit if the team wants it bounded.
(b) Pool default: states that pgxpool's default MaxConns (pool_max_conns) is the greater of 4 and runtime.NumCPU(), and that runtime.NumCPU reflects the host/affinity CPU count rather than the cgroup request or quota — so each pod gets ~64 max connections, and 20 pods × 64 = 1280 exceeds max_connections 500.
(c) Remedy: set MaxConns / pool_max_conns explicitly and size it so that (HPA max replicas) × MaxConns stays below max_connections minus reserved/admin/migration headroom (i.e. roughly ≤ 20–24 per pod for 20 replicas and 500), optionally mentioning PgBouncer.
FAIL if it claims Go 1.25 sets GOMAXPROCS from the CPU request (e.g. "GOMAXPROCS is now 2"), if it states the pgxpool default as a fixed number (e.g. 4, 10, 25) or as derived from GOMAXPROCS, or if it never connects the per-pod pool size to the 64-core node.
