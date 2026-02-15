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
  --with copilot|gemini|codex                      AI collaboration mode
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

### AI Collaboration Flow (--with option)
When `--with` option is specified, additional collaboration steps are executed:

1. **Prepare**: Build performance analysis prompt from target and options
2. **Execute AI Analysis**: Run external AI CLI tool
3. **Compare**: Compare Claude's findings with AI response
4. **Synthesize**: Select optimal findings and recommendations
5. **Report**: Present unified report with source attribution

## AI Collaboration Options

### --with gemini
Collaborates with Gemini CLI for performance analysis comparison.

**Execution Flow:**
1. Store analysis request in `$PROMPT` environment variable
2. Execute: `gemini -m gemini-3-pro-preview -p "$PROMPT" --output-format stream-json`
3. Display Gemini response with Claude's commentary
4. Compare findings and recommendations
5. Select optimal solution based on combined analysis

**Prompt Template:**
```bash
PROMPT="Perform a performance code review on: [target path]
Language: [--lang value or 'auto-detect']
Focus area: [--focus value or 'all categories']
Depth: [--depth value or 'deep']

Analyze for:
- Object creation and memory anti-patterns
- I/O and network bottlenecks
- Concurrency issues
- Serialization overhead
- Collection misuse
- Caching opportunities
- Logging performance impact

For each finding provide:
- Severity (Critical/High/Medium/Low)
- Bad code example
- Good code example
- Estimated improvement impact"
```

### --with copilot
Collaborates with Copilot CLI using multiple models for comprehensive analysis.

**Execution Flow:**
1. Store analysis request in `$PROMPT` environment variable
2. Execute 3 models sequentially:
   - `copilot --model gpt-5.2-codex -p "$PROMPT"`
   - `copilot --model claude-opus-4.5 -p "$PROMPT"`
   - `copilot --model gemini-3-pro-preview -p "$PROMPT"`
3. Display each model's response with Claude's commentary
4. Compare all results and identify consensus/divergence
5. Select optimal findings based on multi-model analysis
6. If copilot fails, retry execution

### --with codex
Collaborates with Codex CLI for performance analysis comparison.

**Execution Flow:**
1. Store analysis request in `$PROMPT` environment variable
2. Execute: `codex --model gpt-5.3-codex-spark xhigh exec "$PROMPT"`
3. Display Codex response with Claude's commentary
4. Compare findings and recommendations
5. Select optimal solution based on combined analysis

**Prompt Template:**
```bash
PROMPT="Perform a performance code review on: [target path]
Language: [--lang value or 'auto-detect']
Focus area: [--focus value or 'all categories']
Depth: [--depth value or 'deep']

Analyze for:
- Object creation and memory anti-patterns
- I/O and network bottlenecks
- Concurrency issues
- Serialization overhead
- Collection misuse
- Caching opportunities
- Logging performance impact

For each finding provide:
- Severity (Critical/High/Medium/Low)
- Bad code example
- Good code example
- Estimated improvement impact"
```

## Tool Coordination
- **Glob**: File discovery and language detection
- **Grep**: Anti-pattern scanning using known regex patterns
- **Read**: Source code inspection for context-aware analysis
- **Bash**: External tool execution (profiler commands, AI CLI)

## Key Patterns
- **Anti-Pattern Detection**: Grep-based scanning for known performance pitfalls
- **Context-Aware Analysis**: Read surrounding code before flagging issues
- **Severity Classification**: Critical > High > Medium > Low with impact estimates
- **Bad/Good Examples**: Every finding includes concrete code improvement
- **AI Collaboration**: Multi-model comparison for enhanced coverage

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

### AI-Assisted Review with Gemini
```
/perf-review src --with gemini --focus concurrency
# Concurrency analysis with Gemini collaboration
# Compares Claude and Gemini findings for comprehensive coverage
```

### AI-Assisted Review with Codex
```
/perf-review src --with codex --focus memory
# Memory analysis with Codex collaboration
# Compares Claude and Codex findings for comprehensive coverage
```

### AI-Assisted Review with Copilot
```
/perf-review --with copilot --depth deep
# Deep analysis with Copilot multi-model comparison
# Aggregates insights from GPT-5.2, Claude, and Gemini via Copilot
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

### AI Collaboration Output
```
## Performance Review Report
[Standard report]

## Claude Analysis
[Claude's findings and recommendations]

## [Gemini/Copilot] Analysis
[External AI findings]

## Comparison & Synthesis
- Consensus: [agreed findings]
- Divergence: [different perspectives]
- Selected Approach: [optimal recommendation with rationale]
```

## Boundaries

**Will:**
- Scan code for known performance anti-patterns across Kotlin, Python, and TypeScript
- Classify findings by severity with estimated impact
- Provide Bad/Good code examples for every finding
- Execute AI collaboration via Gemini or Copilot CLI when requested
- Suggest profiling/benchmarking approaches for complex cases

**Will Not:**
- Modify source code directly (suggestions only)
- Run actual profilers or benchmarks (suggests commands to run)
- Analyze compiled/binary code
- Guarantee specific performance numbers (provides estimates)
- Use multiple `--with` options simultaneously (copilot/gemini/codex)

## Related

- `/analyze --focus performance` - Broader performance analysis (architecture-level)
- `/perf-review` - Code-level anti-pattern detection (this command)
- `perf-reviewer` agent - The underlying agent with full checklist knowledge
- `skills/perf-review-guide/SKILL.md` - Quick reference for common patterns
