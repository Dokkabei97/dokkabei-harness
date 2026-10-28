---
type: llm
focus: last_message
---

Ground truth (LinkedHashMap javadoc): "In access-ordered linked hash maps, merely querying the map with get is a structural modification." The third constructor argument `true` enables access order, so every `get` relinks the entry to the tail of the doubly linked list.

PASS only if the reply does ALL of:
1. Identifies that because of access order (`accessOrder = true`, the third constructor argument), `get` itself is a structural modification / mutates the internal linked list (moves the entry to the tail).
2. Concludes that the read lock — which multiple threads hold concurrently — is therefore insufficient for `get`: concurrent gets race with each other and with `snapshot()` iteration, corrupting links (explaining the CME, the spinning thread and/or the size anomaly).
3. Recommends a correct fix: take the exclusive/write lock (or a plain mutex / synchronized) for `get`, or replace the hand-rolled cache with Caffeine (or another concurrent bounded cache).

FAIL if it blames only `put`/`removeEldestEntry` or the iteration in `snapshot()` without stating that `get` mutates the map in access-order mode, or if it recommends ConcurrentHashMap/Collections.synchronizedMap without addressing that get is a write.
