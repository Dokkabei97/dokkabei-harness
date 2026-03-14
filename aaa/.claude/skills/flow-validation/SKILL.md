---
name: flow-validation
description: |
  Validation rules and checklists for Claude Code plugin components.
  Contains structural, content, and security validation rules for
  agents, commands, skills, and hooks. Used by the /verify-flow command.
---

# Flow Validation Rules

Comprehensive validation ruleset for Claude Code plugin components. Rules are organized by component type and severity to enable systematic quality checks.

## When to Apply

Reference these rules when:
- Running `/verify-flow` to validate components
- Creating new components and need to verify compliance
- Reviewing pull requests that modify plugin components
- Setting up CI validation for plugin repositories

## Rule Categories

| Prefix | Component | Rule Count |
|--------|-----------|------------|
| `CMD-` | Commands | 12 rules |
| `AGT-` | Agents | 12 rules |
| `SKL-` | Skills | 11 rules |
| `HK-` | Hooks | 6 rules |
| `XRF-` | Cross-Reference | 5 rules |
| `SEC-` | Security | 4 rules |
| `QUA-` | Quality | 6 rules |

## Severity Scale

| Level | Impact | Auto-Fixable | Action |
|-------|--------|-------------|--------|
| Critical | Component broken | Some | Must fix immediately |
| High | Convention violation | Some | Fix before merge |
| Medium | Style deviation | Most | Fix when convenient |
| Low | Optimization hint | All | Optional |

## Validation Order

Execute validation in this order for optimal dependency resolution:

1. **Structural** (CMD/AGT/SKL/HK rules) - File exists, frontmatter valid, sections present
2. **Content Quality** (QUA rules) - Descriptions specific, examples present, triggers concrete
3. **Security** (SEC rules) - No credentials, safe scripts, no dangerous commands
4. **Cross-Reference** (XRF rules) - Component references valid, no orphans

## Quick Reference: Required Sections

### Command Required Sections
```
---
frontmatter (6 fields)
---
# /{name} - {Title}
## Triggers (3+ items)
## Usage (code block with options)
## Behavioral Flow (phased, numbered)
## Tool Coordination (tool list)
## Examples (2+ with code blocks)
## Boundaries (Will + Will Not)
```

### Agent Required Sections
```
---
frontmatter (3 fields)
---
Persona description paragraph
## Your Role (5+ responsibilities)
## Analysis Workflow (numbered steps)
## Output Format (report template)
## Boundaries (Will + Will Not)
```

### Skill Required Structure
```
skills/{name}/
  SKILL.md (< 5,000 tokens)
    ---
    frontmatter (2 fields)
    ---
    # {Title}
    ## When to Apply (3+ conditions)
    ## {Domain Content}
    ## How to Use
  references/ (optional, {prefix}-{topic}.md naming)
  templates/ (optional, referenced in SKILL.md)
```

## Reference Files

Detailed rule definitions with examples:
- [references/cmd-rules.md](references/cmd-rules.md) - Command validation rules
- [references/agt-rules.md](references/agt-rules.md) - Agent validation rules
- [references/skl-rules.md](references/skl-rules.md) - Skill validation rules
- [references/hk-rules.md](references/hk-rules.md) - Hook validation rules
- [references/xrf-rules.md](references/xrf-rules.md) - Cross-reference rules
- [references/sec-rules.md](references/sec-rules.md) - Security rules
- [references/qua-rules.md](references/qua-rules.md) - Quality rules

## Token Budget Estimation

For skill SKILL.md files, estimate token count:
```
tokens ≈ word_count × 1.3
```

| Budget | Words | Status |
|--------|-------|--------|
| < 3,500 | < 2,700 | Optimal |
| 3,500-5,000 | 2,700-3,850 | Acceptable |
| > 5,000 | > 3,850 | Over budget - split into references |

## Health Score Calculation

```
Base Score: 100

Deductions per finding:
  Critical: -20
  High:     -10
  Medium:    -3
  Low:       -1

Rating Scale:
  90-100: Excellent - Ready for production use
  75-89:  Good - Minor improvements recommended
  60-74:  Fair - Notable gaps need attention
  40-59:  Poor - Significant issues found
   0-39:  Critical - Not ready for use
```
