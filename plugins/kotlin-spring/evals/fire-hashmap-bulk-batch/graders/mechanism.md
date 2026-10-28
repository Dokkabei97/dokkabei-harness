---
type: llm
focus: last_message
---

PASS if the reply explains that HashMap(n) takes a capacity, not an expected size, so with load factor 0.75 the map still resizes/rehashes before holding n entries, and recommends a correct pre-sizing (HashMap.newHashMap(n) on JDK 19+, or capacity n/0.75+1); AND it also points out the boxing cost of Long keys (java.lang.Long objects) with a primitive-keyed alternative (e.g. fastutil Long2ObjectOpenHashMap, Eclipse Collections, HPPC, or array indexing).
FAIL if it treats HashMap(rows.size) as already correctly sized, or never mentions boxing/primitive maps.
