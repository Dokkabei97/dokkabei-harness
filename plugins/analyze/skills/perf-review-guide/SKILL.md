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

## Symptom-Based Diagnosis Tree

증상에서 원인을 역추적하는 진단 가이드. "무엇이 느린가?"에서 시작한다.

```
무엇이 느린가?
├── 특정 API 엔드포인트
│   ├── DB 쿼리가 느린가? → EXPLAIN ANALYZE, 인덱스 확인
│   ├── N+1 쿼리인가? → fetch join, @EntityGraph, batch query
│   ├── 외부 API 호출이 느린가? → 타임아웃 설정, 비동기 전환, 캐싱
│   └── 직렬화/역직렬화가 느린가? → ObjectMapper 싱글톤, orjson
├── 전체 API가 느림
│   ├── Connection pool 부족? → HikariCP maximumPoolSize 확인
│   ├── 메모리/CPU 부족? → JVM heap, GC 로그, Python memory profiler
│   └── 스레드/코루틴 고갈? → runBlocking 확인, 스레드풀 사이즈
├── 간헐적으로 느림
│   ├── Lock contention? → synchronized 범위 최소화
│   ├── GC pause? → GC 로그 분석, 객체 생성 패턴 확인
│   └── 외부 의존성 불안정? → circuit breaker, timeout, retry
└── 배치/백그라운드 작업
    ├── 단건 처리? → bulk/batch 전환
    ├── 메모리에 전체 로드? → streaming/cursor 기반 처리
    └── 순차 처리? → 병렬 처리 (coroutine, ProcessPoolExecutor)
```

## VERIFY & GUARD Workflow

성능 수정 후 반드시 거쳐야 할 검증 단계:

### VERIFY (수정 후 검증)
- [ ] 수정 전/후 측정값이 존재하는가? (구체적 숫자)
- [ ] 특정 병목이 식별되고 해결되었는가?
- [ ] API 응답 시간이 목표 이내인가? (예: p95 < 200ms)
- [ ] 새로운 N+1 쿼리가 없는가?
- [ ] 기존 테스트가 모두 통과하는가?

### GUARD (회귀 방지)
- [ ] 성능 테스트가 CI에 포함되었는가? (가능한 경우)
- [ ] 성능 모니터링 대시보드에 해당 메트릭이 추적되고 있는가?
- [ ] 슬로우 쿼리 로그가 설정되어 있는가?
- [ ] 부하 테스트 시나리오에 해당 엔드포인트가 포함되어 있는가?

> "탐지 → 수정"으로 끝내지 마라. **"탐지 → 수정 → 검증 → 회귀 방지"**가 완전한 사이클이다.

---

## Integration with Other Tools

- Use `/perf-review [target]` command for structured analysis with full report
- Use `/analyze --focus performance` for broader architecture-level review
- The `perf-reviewer` agent contains the complete checklist with all code examples
- This skill provides quick reference during regular development

---

**Remember**: Performance matters most in hot paths. Always profile before optimizing, and keep code readable unless the benchmark proves otherwise.
