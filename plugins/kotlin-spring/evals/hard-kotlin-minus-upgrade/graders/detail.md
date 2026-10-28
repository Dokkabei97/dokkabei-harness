---
type: llm
focus: last_message
---

Ground truth (Kotlin 1.6 compatibility guide, KT-45438 "Remove brittle contains optimization in minus/removeAll/retainAll"): before 1.6 the stdlib could convert the argument collection of `minus`/`removeAll`/`retainAll` to a HashSet internally; from 1.6.0 a collection argument is no longer converted, so `list - list` does a linear `contains` per element → O(n·m) (here 400k × 400k). The system property `kotlin.collections.convert_arg_to_set_in_removeAll=true` only restored the old behavior temporarily in 1.6; ">= 1.7: the system property above will no longer have an effect".

PASS only if the reply does ALL of:
1. Attributes the slowdown to the Kotlin stdlib change in 1.6 (within the 1.5.31 → 2.0.21 upgrade): `minus` (and removeAll/retainAll) no longer converts the argument collection to a HashSet, so the List argument makes it O(n·m).
2. Recommends converting the argument to a hash set explicitly (e.g. `existingIds - incomingIds.toHashSet()` / `toSet()`), or an equivalent set-based diff.

FAIL if it attributes the slowdown mainly to the JDK, Spring Boot, GC, or boxing without identifying the Kotlin 1.6 stdlib behavior change, or if it says `list - list` was always O(n·m). Also FAIL if it presents the system property `kotlin.collections.convert_arg_to_set_in_removeAll` as a working fix on Kotlin 2.0.21 (it has had no effect since 1.7) — merely mentioning it as a 1.6-only historical toggle is fine.
