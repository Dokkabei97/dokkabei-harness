---
type: llm
focus: last_message
---

All three of the following are required for PASS:
(a) States that Go maps do not shrink in any version, including the Swiss-table implementation in Go 1.24+ (the premise in the question is wrong), and that both `delete` and `clear(m)` leave the already-allocated table capacity in place — `clear` empties entries but does not release memory.
(b) Explains the CPU symptom: iterating a map costs time proportional to its allocated capacity (all groups/buckets/slots are walked), not to len(m), so a map that once held ~4M entries is expensive to range over even with <50 live keys.
(c) Remedy: replace the map with a freshly allocated one (e.g. `m = make(map[string]struct{})`, or copy the live keys into a new map) under the lock, instead of `clear(m)`; may add a generational/rotating-map scheme. Noting that `clear` is appropriate only when the map will be refilled to a similar size is welcome but not required.
FAIL if it says Swiss tables (1.24+) shrink maps or that `clear` frees the memory, if its primary fix keeps `clear(m)` or relies on `runtime.GC()` / `debug.FreeOSMemory()` instead of replacing the map, or if it never explains why ranging over a near-empty map is CPU-heavy. Mentioning `debug.FreeOSMemory()` only as an optional, secondary way to return RSS faster *after* the map has been replaced is fine and must not cause a FAIL.
