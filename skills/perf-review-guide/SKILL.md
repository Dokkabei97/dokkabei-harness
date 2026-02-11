---
name: perf-review-guide
description: Use this skill when reviewing or writing performance-sensitive code. Provides quick reference for common performance anti-patterns and optimization strategies across Kotlin, Python, and TypeScript/JavaScript.
---

# Performance Review Quick Reference

This skill provides a condensed checklist for identifying performance anti-patterns during code review or development.

## When to Activate

- Reviewing code that handles high throughput or low-latency requirements
- Writing or modifying database queries, batch processing, or API handlers
- Working with large datasets, collections, or serialization
- Changing concurrency, threading, or async patterns
- Noticing potential memory leaks or excessive object allocation
- Optimizing slow endpoints or background jobs

## Core Principles

### 1. Measure First
Never optimize without profiling. Use benchmarks to confirm bottlenecks before refactoring.

### 2. Focus on Hot Paths
Optimize code that runs frequently (request handlers, loops, batch jobs). Cold paths (startup, config loading) rarely matter.

### 3. Readability vs Performance
Only sacrifice readability when profiling proves measurable impact. Premature optimization causes maintenance burden.

## Quick Reference by Category

### 1. Object Creation & Memory
| Anti-Pattern | Fix | Languages |
|-------------|-----|-----------|
| New ObjectMapper per call | Singleton companion object | Kotlin |
| Missing `__slots__` on data classes | Add `__slots__` | Python |
| `new RegExp()` in functions | Module-level constant | TS/JS |
| Closure retaining large objects | Extract needed values only | TS/JS |

### 2. Loops & Algorithms
| Anti-Pattern | Fix | Languages |
|-------------|-----|-----------|
| DB call inside loop (N+1) | Batch query (`findAllById`) | All |
| String concatenation in loop | `joinToString` / `StringBuilder` | Kotlin |
| List comprehension for sum | Generator expression | Python |
| DOM append in loop | `DocumentFragment` batching | TS/JS |

### 3. I/O & Network
| Anti-Pattern | Fix | Languages |
|-------------|-----|-----------|
| N+1 lazy loading | `@EntityGraph` / fetch join | Kotlin |
| `@Transactional` wrapping HTTP calls | Narrow transaction scope | Kotlin |
| Sequential HTTP requests | `asyncio.gather` / `Promise.all` | Python/TS |
| Loading entire file into memory | Stream response | TS/JS |

### 4. Serialization
| Anti-Pattern | Fix | Languages |
|-------------|-----|-----------|
| New ObjectMapper per request | Inject or companion object | Kotlin |
| `json.loads/dumps` (stdlib) | `orjson` (3-10x faster) | Python |
| `JSON.stringify` for comparison | Deep equality (`isEqual`) | TS/JS |
| Reflection-based DTO mapping | MapStruct (compile-time) | Kotlin |

### 5. Concurrency
| Anti-Pattern | Fix | Languages |
|-------------|-----|-----------|
| `@Synchronized` on entire method | Minimize critical section | Kotlin |
| `runBlocking` on request thread | `suspend fun` | Kotlin |
| `ThreadPoolExecutor` for CPU work | `ProcessPoolExecutor` | Python |
| Heavy computation on main thread | `Worker` threads | TS/JS |
| Unbounded `Promise.all` | `p-limit` concurrency control | TS/JS |

### 6. Collections
| Anti-Pattern | Fix | Languages |
|-------------|-----|-----------|
| `List.contains()` in loop | Convert to `HashSet` | Kotlin |
| `list.pop(0)` | `collections.deque` | Python |
| `Array` for large numeric data | `TypedArray` | TS/JS |
| `Object` as dynamic map | `Map` for frequent mutations | TS/JS |

### 7. Caching
| Anti-Pattern | Fix | Languages |
|-------------|-----|-----------|
| DB query for rarely-changing data | Caffeine cache with TTL | Kotlin |
| Repeated expensive computation | `@cached` / `lru_cache` | Python |
| Strong reference cache | `WeakRef`-based cache | TS/JS |
| Recomputing derived data each render | `useMemo` | React/TS |

### 8. Logging & Exceptions
| Anti-Pattern | Fix | Languages |
|-------------|-----|-----------|
| String concat in disabled log level | Lambda-based `logger.debug { }` | Kotlin |
| f-string in debug log | `%s` lazy formatting | Python |
| Exceptions for expected flow | `Result` pattern | Kotlin |
| `Error` creation for flow control | Return validation result | TS/JS |

### 9. Elasticsearch / Search
| Anti-Pattern | Fix | Languages |
|-------------|-----|-----------|
| Single-document indexing in loop | Bulk API | All |
| `from/size` deep pagination | `search_after` | All |
| Expensive aggregation every request | Cache with TTL | All |
| Same analyzer for index & search | Separate analyzers | All |

## Top 5 Most Common Anti-Patterns

These are the patterns most frequently encountered in production code reviews:

### 1. N+1 Queries
```kotlin
// BAD
ids.map { userRepository.findById(it) }
// GOOD
userRepository.findAllById(ids)
```

### 2. ObjectMapper / JSON Serializer Per Call
```kotlin
// BAD
val mapper = ObjectMapper()
// GOOD
companion object { private val mapper = jacksonObjectMapper() }
```

### 3. Sequential I/O Where Parallel Is Possible
```typescript
// BAD
const a = await fetchA(); const b = await fetchB()
// GOOD
const [a, b] = await Promise.all([fetchA(), fetchB()])
```

### 4. Wrong Collection Type for Lookups
```python
# BAD: O(n) per check
if item in large_list: ...
# GOOD: O(1) per check
if item in large_set: ...
```

### 5. Oversized Transaction Scope
```kotlin
// BAD: @Transactional wrapping external HTTP call
// GOOD: Split into DB-only transaction + separate HTTP call
```

## Severity Guide

| Severity | When to Flag |
|----------|-------------|
| **Critical** | OOM risk, deadlock, production outage potential |
| **High** | Measurable latency/throughput degradation |
| **Medium** | Suboptimal but functional, improvement opportunity |
| **Low** | Minor optimization, nice-to-have |

## Integration with Other Tools

- Use `/perf-review [target]` command for structured analysis with full report
- Use `/analyze --focus performance` for broader architecture-level review
- The `perf-reviewer` agent contains the complete checklist with all code examples
- This skill provides quick reference during regular development

---

**Remember**: Performance matters most in hot paths. Always profile before optimizing, and keep code readable unless the benchmark proves otherwise.
