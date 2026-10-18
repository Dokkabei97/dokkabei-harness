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

## Tool Coordination
- **Glob**: Project structure discovery, build config detection, directory pattern analysis
- **Grep**: Import statement analysis, violation pattern scanning, architecture marker detection
- **Read**: Source code inspection for context-aware analysis
- **Bash**: Git history analysis, file size metrics

## Key Patterns
- **Architecture Detection**: Scoring matrix for Layered/Hexagonal/Clean/MVC identification
- **Dependency Direction Tracking**: Import analysis to verify inward-only dependency flow
- **Violation Classification**: V-C1~V-L3 checklist with severity and detection patterns
- **Health Scoring**: 0-100 score based on violations (deductions) and best practices (bonuses)
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

## Boundaries

**Will:**
- Scan codebase for architecture violations across Kotlin, Python, and TypeScript
- Detect architecture style and verify dependency direction compliance
- Classify violations by severity with Architecture Health Score (0-100)
- Provide Bad/Good code examples for every violation
- Analyze MSA maturity and distributed system patterns

**Will Not:**
- Modify source code directly (suggestions only)
- Force a specific architecture style (detect and validate, not prescribe)
- Run actual build/compile processes
- Guarantee specific health scores (provides objective assessment)

## Related

- `/analyze --focus architecture` - Broader architecture analysis (multi-domain)
- `/arch-review` - Structural review with violation checklist (this command)
- `arch-reviewer` agent - The underlying agent with full analysis methodology
- `skills/arch-review-guide/SKILL.md` - Quick reference for common architecture patterns
- `/perf-review` - Performance-focused code review (complementary)
