---
type: llm
focus: last_message
---

PASS if the reply explains that container RSS includes non-heap JVM memory (metaspace, code cache, thread stacks, direct buffers, GC structures and/or glibc malloc arenas) beyond the Java heap, AND gives at least two concrete, specific remedies or checks among: setting -XX:MaxRAMPercentage (or -Xmx) with headroom below the limit rather than at 100%, Native Memory Tracking (-XX:NativeMemoryTracking + jcmd VM.native_memory), MALLOC_ARENA_MAX (or jemalloc / malloc trim), capping MaxDirectMemorySize / checking direct buffer OOM.
FAIL if it only says "increase the memory limit" or "increase the heap", or never distinguishes heap from native/off-heap memory.
