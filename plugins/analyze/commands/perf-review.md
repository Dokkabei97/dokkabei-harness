---
name: perf-review
description: "Performance code review with anti-pattern detection and optimization suggestions. Supports Kotlin, Python, and TypeScript/JavaScript."
category: review
complexity: basic
mcp-servers: []
personas: []
---

# /perf-review - Performance Code Review

## Triggers
- Code review where performance is a concern
- High-throughput or latency-sensitive code changes
- Database query optimization needs
- Memory usage or resource management changes
- Batch processing or data pipeline code
- Pre-production performance validation

## Usage
```
/perf-review [target] [options]

Options:
  --focus memory|io|concurrency|serialization|all  Analysis domain (default: all)
  --lang kotlin|python|ts|all                      Target language (default: auto-detect)
  --depth quick|deep                               Analysis depth (default: deep)
```

## Behavioral Flow

### Standard Analysis Flow
1. **Discover**: Identify target files, detect language and framework
2. **Scan**: Apply category-specific anti-pattern detection from checklist
3. **Evaluate**: Classify findings by severity (Critical/High/Medium/Low) with estimated impact
4. **Recommend**: Provide Bad/Good code examples for each finding
5. **Report**: Present structured report with prioritized quick wins

### Focus Domains

| Focus | Categories Covered |
|-------|-------------------|
| `memory` | Object Creation & Memory, Collections, Caching |
| `io` | I/O & Network, Database & Query, Loops (DB-related) |
| `concurrency` | Concurrency & Threading, Resource Management |
| `serialization` | Serialization & Parsing, Logging (formatting) |
| `all` | All 9 categories |

## Tool Coordination
- **Glob**: File discovery and language detection
- **Grep**: Anti-pattern scanning using known regex patterns
- **Read**: Source code inspection for context-aware analysis
- **Bash**: External tool execution (profiler commands)

## Key Patterns
- **Anti-Pattern Detection**: Grep-based scanning for known performance pitfalls
- **Context-Aware Analysis**: Read surrounding code before flagging issues
- **Severity Classification**: Critical > High > Medium > Low with impact estimates
- **Bad/Good Examples**: Every finding includes concrete code improvement
## Examples

### Full Project Performance Review
```
/perf-review
# Scans entire project for performance anti-patterns
# Auto-detects language, analyzes all 9 categories
```

### Focused Memory Analysis
```
/perf-review src/service --focus memory --lang kotlin
# Analyzes Kotlin service layer for:
# - Object creation in hot paths (ObjectMapper, data class copy)
# - Collection misuse (List vs Set)
# - Caching opportunities (Caffeine, @PostConstruct)
```

### I/O and Database Review
```
/perf-review src/repository --focus io
# Checks for:
# - N+1 queries
# - Missing batch operations
# - @Transactional scope issues
# - Sequential I/O where parallel is possible
```

### Serialization Hot Path Review
```
/perf-review src/api --focus serialization --lang ts
# Checks for:
# - JSON.stringify in hot paths
# - Stream parsing for large payloads
# - Unnecessary serialization/deserialization cycles
```

### Quick Pre-Merge Check
```
/perf-review src/handlers --depth quick
# Fast scan for Critical/High severity patterns only
# Suitable for PR review gate
```

## Output Format

### Standard Output
```
## Performance Review Report

### Target: [path]
### Language: [detected language]
### Focus: [domain]
### Depth: [level]
### Files Analyzed: [count]

---

### Critical (X issues)

#### [Issue Title]
- **Category**: [category]
- **File**: [file:line]
- **Impact**: [description]
- **Bad**:
  ```[lang]
  [current code]
  ```
- **Good**:
  ```[lang]
  [suggested fix]
  ```
- **Expected Improvement**: [estimate]

### High (X issues)
...

### Medium (X issues)
...

### Low (X issues)
...

---

### Summary
- Total issues: X
- Top 3 quick wins: [prioritized list]
```

## Boundaries

**Will:**
- Scan code for known performance anti-patterns across Kotlin, Python, and TypeScript
- Classify findings by severity with estimated impact
- Provide Bad/Good code examples for every finding
- Suggest profiling/benchmarking approaches for complex cases

**Will Not:**
- Modify source code directly (suggestions only)
- Run actual profilers or benchmarks (suggests commands to run)
- Analyze compiled/binary code
- Guarantee specific performance numbers (provides estimates)

## Related

- `/analyze --focus performance` - Broader performance analysis (architecture-level)
- `/perf-review` - Code-level anti-pattern detection (this command)
- `perf-reviewer` agent - The underlying agent with full checklist knowledge
- `skills/perf-review-guide/SKILL.md` - Quick reference for common patterns
