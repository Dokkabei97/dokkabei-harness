---
type: llm
focus: last_message
---

PASS if the reply explains that with GOGC=100 the next GC target is about twice the live heap (≈1GB here), so the heap can grow past the container limit, AND recommends setting GOMEMLIMIT (or debug.SetMemoryLimit) to roughly 90% of the container limit (leaving 5-10% headroom for non-Go memory), keeping GOGC at default as the starting point.
FAIL if it only suggests raising the memory limit or lowering GOGC without mentioning GOMEMLIMIT.
