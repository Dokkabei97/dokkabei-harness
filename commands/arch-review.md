---
name: arch-review
description: "Architecture review with dependency direction analysis, layer violation detection, and structural health scoring. Supports Kotlin, Python, and TypeScript/JavaScript."
category: review
complexity: basic
mcp-servers: []
personas: []
---

# /arch-review - Architecture Code Review

## Triggers
- Architecture conformance review for new or existing projects
- Dependency direction validation across layers and modules
- Layer violation detection (domain depending on infrastructure, controller accessing repository)
- Naming convention and package structure consistency checks
- Pre-merge architecture gate for structural changes
- MSA / distributed system architecture assessment

## Usage
```
/arch-review [target] [options]

Options:
  --focus structure|dependency|naming|data|msa|all  Analysis domain (default: all)
  --depth quick|deep                                 Analysis depth (default: deep)
  --with copilot|gemini|codex                        AI collaboration mode
```

## Behavioral Flow

### Standard Analysis Flow
1. **Discover**: Identify project type, module composition, and build configuration (Step 1)
2. **Track**: Analyze import statements for dependency direction compliance (Step 2)
3. **Analyze**: Check package structure, naming conventions, and data modeling (Steps 3-4)
4. **Detect**: Identify MSA patterns and distributed system indicators (Step 5)
5. **Assess**: Evaluate developer intent via Git history, test patterns, exception handling (Step 6)
6. **Report**: Present structured report with Architecture Health Score and prioritized recommendations

### Focus Domains

| Focus | Steps Covered |
|-------|--------------|
| `structure` | Step 1 (Macro Structure), Step 3 (Package/Naming) |
| `dependency` | Step 2 (Dependency Direction), Violation Checklist (V-C1~V-C3, V-H1) |
| `naming` | Step 3 (Naming Conventions), V-M1, V-M2 |
| `data` | Step 4 (Data Modeling / DTO Separation), V-H2 |
| `msa` | Step 5 (MSA / Distributed System Detection) |
| `all` | All 6 steps |

### AI Collaboration Flow (--with option)
When `--with` option is specified, additional collaboration steps are executed:

1. **Prepare**: Build architecture analysis prompt from target and options
2. **Execute AI Analysis**: Run external AI CLI tool
3. **Compare**: Compare Claude's findings with AI response
4. **Synthesize**: Select optimal findings and recommendations
5. **Report**: Present unified report with source attribution

## AI Collaboration Options

### --with gemini
Collaborates with Gemini CLI for architecture analysis comparison.

**Execution Flow:**
1. Store analysis request in `$PROMPT` environment variable
2. Execute: `gemini -m gemini-3-pro-preview -p "$PROMPT" --output-format stream-json`
3. Display Gemini response with Claude's commentary
4. Compare findings and recommendations
5. Select optimal solution based on combined analysis

**Prompt Template:**
```bash
PROMPT="Perform an architecture review on: [target path]
Focus area: [--focus value or 'all steps']
Depth: [--depth value or 'deep']

Analyze for:
- Project structure and module composition
- Dependency direction compliance (inner vs outer layers)
- Layer violations (domain depending on infrastructure)
- Package structure and naming convention consistency
- DTO/Entity separation maturity
- MSA patterns and distributed system indicators
- Architecture health score (0-100)

For each violation provide:
- Violation ID and severity (Critical/High/Medium/Low)
- Bad code example
- Good code example
- Architectural impact description"
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
Collaborates with Codex CLI for architecture analysis comparison.

**Execution Flow:**
1. Store analysis request in `$PROMPT` environment variable
2. Execute: `codex --model gpt-5.3-codex-spark xhigh exec "$PROMPT"`
3. Display Codex response with Claude's commentary
4. Compare findings and recommendations
5. Select optimal solution based on combined analysis

**Prompt Template:**
```bash
PROMPT="Perform an architecture review on: [target path]
Focus area: [--focus value or 'all steps']
Depth: [--depth value or 'deep']

Analyze for:
- Project structure and module composition
- Dependency direction compliance (inner vs outer layers)
- Layer violations (domain depending on infrastructure)
- Package structure and naming convention consistency
- DTO/Entity separation maturity
- MSA patterns and distributed system indicators
- Architecture health score (0-100)

For each violation provide:
- Violation ID and severity (Critical/High/Medium/Low)
- Bad code example
- Good code example
- Architectural impact description"
```

## Tool Coordination
- **Glob**: Project structure discovery, build config detection, directory pattern analysis
- **Grep**: Import statement analysis, violation pattern scanning, architecture marker detection
- **Read**: Source code inspection for context-aware analysis
- **Bash**: Git history analysis, file size metrics, external tool execution (AI CLI)

## Key Patterns
- **Architecture Detection**: Scoring matrix for Layered/Hexagonal/Clean/MVC identification
- **Dependency Direction Tracking**: Import analysis to verify inward-only dependency flow
- **Violation Classification**: V-C1~V-L3 checklist with severity and detection patterns
- **Health Scoring**: 0-100 score based on violations (deductions) and best practices (bonuses)
- **AI Collaboration**: Multi-model comparison for enhanced coverage

## Examples

### Full Project Architecture Review
```
/arch-review
# Runs all 6 analysis steps on entire project
# Detects architecture style, checks dependency direction, scores health
```

### Focused Dependency Direction Analysis
```
/arch-review src --focus dependency --depth deep
# Deep analysis of dependency direction:
# - Domain layer imports (should have zero outward deps)
# - Controller-to-Repository skipping (V-H1)
# - UseCase-to-Adapter coupling (V-C3)
# - Circular module dependencies (V-C2)
```

### Package Structure & Naming Review
```
/arch-review src --focus naming
# Checks for:
# - PascalCase/camelCase/snake_case consistency
# - Package-by-layer vs package-by-feature mixing
# - God class detection (files > 500 lines)
# - Misplaced classes (Service in controller package)
```

### Data Modeling Assessment
```
/arch-review src --focus data
# Checks for:
# - DTO/Entity separation maturity (Level 0-3)
# - Entity exposed in API responses (V-H2)
# - CQRS pattern detection (Command/Query DTOs)
# - Mapping strategy (manual vs MapStruct)
```

### MSA Architecture Assessment
```
/arch-review --focus msa
# Detects:
# - Message broker usage (Kafka, RabbitMQ, SQS)
# - Service-to-service communication (Feign, gRPC, REST)
# - Service discovery and API gateway patterns
# - Circuit breaker and resilience patterns
# - Docker/Kubernetes deployment configuration
# - MSA Maturity Level (0-4)
```

### Quick Pre-Merge Check
```
/arch-review src --depth quick
# Fast scan for Critical/High severity violations only
# Suitable for PR review gate
```

### AI-Assisted Review with Gemini
```
/arch-review src --with gemini --focus dependency
# Dependency analysis with Gemini collaboration
# Compares Claude and Gemini findings for comprehensive coverage
```

### AI-Assisted Review with Codex
```
/arch-review src --with codex --focus structure
# Structure analysis with Codex collaboration
# Compares Claude and Codex findings for comprehensive coverage
```

### AI-Assisted Review with Copilot
```
/arch-review --with copilot --depth deep
# Deep analysis with Copilot multi-model comparison
# Aggregates insights from GPT-5.2, Claude, and Gemini via Copilot
```

## Output Format

### Standard Output
```
## Architecture Review Report

### Target: [path]
### Detected Architecture: [Layered / Hexagonal / Clean / MVC / Hybrid]
### Project Type: [Monolith / Multi-Module / MSA]
### Languages: [detected languages]

---

### Architecture Detection Summary

| Category | Detection | Confidence |
|----------|-----------|------------|
| Module Structure | [type] | [High/Medium/Low] |
| Architecture Style | [type] | [High/Medium/Low] |
| Dependency Direction | [status] | [High/Medium/Low] |
| DTO Separation | [Level 0-3] | [High/Medium/Low] |
| MSA Maturity | [Level 0-4] | [High/Medium/Low] |
| Test Coverage | [status] | [High/Medium/Low] |

---

### Critical (X violations)

#### [V-ID]: [Violation Title]
- **Category**: [category]
- **File**: [file:line]
- **Rule**: [violated rule]
- **Impact**: [description]
- **Bad**:
  ```[lang]
  [current code]
  ```
- **Good**:
  ```[lang]
  [suggested fix]
  ```

### High (X violations)
...

### Medium (X violations)
...

### Low (X violations)
...

---

### Summary
- Total violations: X
- Architecture health score: [0-100] ([Rating])
- Top 3 immediate actions: [prioritized list]
```

### AI Collaboration Output
```
## Architecture Review Report
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
- Scan codebase for architecture violations across Kotlin, Python, and TypeScript
- Detect architecture style and verify dependency direction compliance
- Classify violations by severity with Architecture Health Score (0-100)
- Provide Bad/Good code examples for every violation
- Execute AI collaboration via Gemini or Copilot CLI when requested
- Analyze MSA maturity and distributed system patterns

**Will Not:**
- Modify source code directly (suggestions only)
- Force a specific architecture style (detect and validate, not prescribe)
- Run actual build/compile processes
- Guarantee specific health scores (provides objective assessment)
- Use multiple `--with` options simultaneously (copilot/gemini/codex)

## Related

- `/analyze --focus architecture` - Broader architecture analysis (multi-domain)
- `/arch-review` - Structural review with violation checklist (this command)
- `arch-reviewer` agent - The underlying agent with full analysis methodology
- `skills/arch-review-guide/SKILL.md` - Quick reference for common architecture patterns
- `/perf-review` - Performance-focused code review (complementary)
