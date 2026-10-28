> **English** · [한국어](README_KO.md)

# kotlin-spring

> A JVM · Kotlin · Spring specialist layer: a symptom-to-pitfall triage skill covering what strong senior generalists still miss (GC and container memory, map and collection choice, coroutines and virtual threads, transactions, JPA and connection pools, profiling), plus convention-first CRUD scaffolding and a read-only runtime diagnostic agent.

## Overview

`kotlin-spring` does not restate idioms the model already knows. Its core is `kotlin-spring-guide`, a triage index that maps symptoms (OOMKilled, latency spikes past 64 concurrent requests, `UnexpectedRollbackException`, `HHH90003004`, stack-less NPEs, ...) to **67 specialist items** with stable IDs (`JVM-GC-02`, `KT-CORO-03`, `SPR-JPA-05`, ...). Every item states its applicability (JDK/Spring/library version and conditions), signal, mechanism, prescription, counter-case, verification method and source URL, so it can be applied only where it fits and selected per project by `workflow:project-rules`.

Nothing about the stack is assumed: the skill, the command and both agents first read the build file, Dockerfile/manifests and existing code to confirm JDK and Boot versions, data-access technology, web stack and migration tool.

Language-neutral backend concerns (API contracts, migration safety, security, ...) belong to `backend-shared`.

## Components

### Skill

- `kotlin-spring-guide` — Specialist triage (entry skill, preloaded by both agents). `SKILL.md` is a fact-check table plus a symptom → item-ID index; details live in one-level `references/`:
  - `jvm-gc-memory.md` — JVM-GC-01~09, JVM-MEM-01~04 (Serial GC ergonomics in small containers, MaxRAMPercentage, CPU-shares change in JDK 19, compressed-oops 32GB boundary, G1 humongous objects, generational ZGC per JDK version, Shenandoah availability, DisableExplicitGC vs direct buffers, glibc arenas, Korean strings and compact strings, compact object headers, OOM heap dumps)
  - `collections.md` — JVM-COL-01~06, KT-COL-01~03·05~06 (HashMap capacity vs threshold, treeification conditions, EnumMap/EnumSet, IdentityHashMap, LRU `get` as structural change, CHM `computeIfAbsent`, Kotlin Linked defaults, boxing and primitive maps, Sequence break-even, Kotlin 1.6 `minus`/`removeAll` without set conversion, value-class boxing)
  - `concurrency.md` — KT-CORO-01~06, JVM-CONC-01~05 (Dispatchers.IO 64 limit and `limitedParallelism`, `runBlocking`, swallowed cancellation, `withTimeout`, MDC/transaction context loss, virtual-thread pinning and JEP 491, Boot executor defaults, commonPool, false sharing)
  - `jit-allocation.md` — JVM-JIT-01~07, KT-LOG-01 (escape analysis limits, megamorphic call sites, regex recompilation and Kotlin vs Java `split`, exception cost, OmitStackTraceInFastThrow, code cache, CDS/AOT warm-up, log templates)
  - `spring-data-tx.md` — SPR-TX-01~05, SPR-JPA-01~06, SPR-POOL-01~03 (kotlin-spring/allOpen proxies, self-invocation and Spring 6 visibility, rollback on checked exceptions, rollback-only, readOnly routing, open-in-view, in-memory pagination, batch fetch, bulk writes, `isNew` merge, driver ResultSet buffering on large reads, Hikari sizing, pool deadlock, maxLifetime)
  - `spring-runtime.md` — SPR-JSON-01~03, SPR-OPS-01~02, KT-VAL-01 (ObjectMapper reuse, Jackson 2 vs 3 in Boot 4, Kotlin-module null semantics, graceful shutdown on k8s, metric cardinality, Bean Validation annotation use-site targets)
  - `observability.md` — JVM-OBS-01~03 (always-on JFR, async-profiler modes, GC/safepoint logging)
  - `team-conventions.md` — the team's own naming/review decisions and code-generation defaults (used only when a project has no convention of its own)

### Command

- `/spring-gen [domain]` — Scaffolds Entity → Repository → Service → Controller → DTO → Test. User-invoked only (`disable-model-invocation`). Phase 1 detects the stack (build file, compiler plugins, data access, web stack, test libraries, migration tool, an existing domain sample) before generating; detected conventions override the bundled examples. Options: `--fields`, `--layers`, `--no-test`, `--reactive`, `--soft-delete`, `--audit`.

### Agents

- `spring-developer` — Generation engine for `/spring-gen`. Detects conventions, generates, checks generated code against relevant pitfall IDs (SPR-TX-01, SPR-JPA-05, KT-CORO-03, ...), then compiles and runs tests.
- `spring-boot-guide` — Read-only runtime diagnosis: confirms facts, maps symptoms to item IDs, rules out by applicability/counter-case, collects code evidence and proposes concrete measurements before prescribing.

## Usage

```
/plugin install kotlin-spring@dokkabei-harness

/spring-gen Order
/spring-gen Product --fields "name:String, price:BigDecimal, stock:Int"
/spring-gen Notification --reactive
```

`kotlin-spring-guide` activates on Kotlin/Spring performance, memory, GC, concurrency or transaction questions and code reviews of hot or transactional paths. Pin the items that matter for a project in its `CLAUDE.md`/`.claude/rules` via `workflow:project-rules`.

## Dependencies

- `backend-shared` (language-neutral backend patterns).

## Notes

- Retired in 2026-10 and moved to `archive/components/kotlin-spring/`: the `spring-boot-patterns` and `naming-conventions` skills (generic idioms; the team-specific naming rules were merged into `references/team-conventions.md`) and the generic `layer-patterns`/`jpa-patterns`/`testing-patterns` references.
- `/spring-gen` never edits existing files or adds build dependencies without confirmation, and leaves business logic as `TODO(human)`.
