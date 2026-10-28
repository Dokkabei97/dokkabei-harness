---
type: llm
focus: last_message
---

PASS if the reply explains that Go maps never shrink — delete (and clear) frees slots but keeps the bucket/group storage sized for the peak — AND prescribes periodically copying the live entries into a freshly made map and swapping it in (or rotating generation maps); it should also either note that RSS lags because freed pages are returned to the OS gradually by the scavenger, or recommend verifying with heap profiles (pprof inuse / -base diff) or runtime/metrics rather than RSS.
FAIL if it concludes it must be a goroutine leak or GC bug without mentioning that maps do not shrink, or only suggests runtime.GC()/debug.FreeOSMemory.
