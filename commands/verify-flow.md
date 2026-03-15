---
name: verify-flow
description: "Validates existing agents, commands, skills, and hooks against project conventions. Detects structural issues, missing sections, token budget violations, and security concerns with severity-rated reports and optional auto-fix."
category: review
complexity: basic
mcp-servers: []
personas: []
---

# /verify-flow - Component Validation and Health Check

## Triggers
- Validating newly created agents, commands, skills, or hooks
- Auditing existing components for convention compliance
- Pre-commit quality check on plugin component files
- Detecting structural drift or missing sections after edits
- Token budget verification for skill files

## Usage
```
/verify-flow [target] [options]

Options:
  --target agent|command|skill|hook|plugin|all  Component type to validate (default: all)
  --fix auto|suggest                      Fix mode (default: suggest)
  --severity critical|high|medium|all     Minimum severity to report (default: all)
  --format text|json|report               Output format (default: text)
  --with copilot|gemini|codex             AI collaboration for validation
```

## Behavioral Flow

### Phase 1: Component Discovery
Scan the project to find all components that match the `--target` filter.

**Discovery Patterns:**
```
--target command  -> Glob: commands/*.md
--target agent    -> Glob: agents/*.md AND .claude/agents/*.md
--target skill    -> Glob: skills/*/SKILL.md
--target hook     -> Read: claude/settings.json (extract hooks array)
--target plugin   -> Glob: .claude-plugin/plugin.json + skills/ + agents/ + hooks/
--target all      -> All of the above
```

If a specific `[target]` path is provided, validate only that file/directory.

**Output:**
```
Discovered components:
  Commands: [list with file sizes]
  Agents:   [list with file sizes]
  Skills:   [list with directory contents]
  Hooks:    [count with descriptions]

Total: N components to validate
```

### Phase 2: Structural Validation
Check each component against its type-specific structural requirements.

**Command Validation Rules:**

| ID | Rule | Severity | Check |
|----|------|----------|-------|
| CMD-001 | Frontmatter present and valid YAML | Critical | Parse YAML between `---` delimiters |
| CMD-002 | Required frontmatter fields | Critical | name, description, category, complexity, mcp-servers, personas |
| CMD-003 | H1 heading matches `# /{name}` pattern | High | Regex: `^# /[a-z-]+ - .+` |
| CMD-004 | Triggers section present | High | Grep: `^## Triggers` |
| CMD-005 | Usage section with code block | High | Grep: `^## Usage` + fenced code block |
| CMD-006 | Behavioral Flow section present | Critical | Grep: `^## Behavioral Flow` |
| CMD-007 | Tool Coordination section present | Medium | Grep: `^## Tool Coordination` |
| CMD-008 | Examples section with code blocks | High | Grep: `^## Examples` + min 2 code blocks |
| CMD-009 | Boundaries section with Will/Will Not | High | Grep: `^## Boundaries` + `**Will:**` + `**Will Not:**` |
| CMD-010 | Section ordering follows convention | Medium | Triggers < Usage < Behavioral Flow < Tool Coordination < Examples < Boundaries |
| CMD-013 | Migration advisory to skill format | Low | Check if command could be skill |

**Agent Validation Rules:**

| ID | Rule | Severity | Check |
|----|------|----------|-------|
| AGT-001 | Frontmatter present and valid YAML | Critical | Parse YAML between `---` delimiters |
| AGT-002 | Required frontmatter fields | Critical | name, description (tools now optional) |
| AGT-003 | Tools array contains valid tool names | High | Each tool in ["Read", "Grep", "Glob", "Bash", "Write", "Edit", "WebSearch", "WebFetch"] |
| AGT-004 | Role description section present | High | Grep: `^## Your Role` or `^## Role` |
| AGT-005 | Workflow section with numbered steps | Critical | Grep: `^## .*(Workflow|Analysis)` + `### Step` |
| AGT-006 | Decision matrices or grep patterns | Medium | Presence of table markdown or `Grep:` patterns |
| AGT-007 | Output format section | Medium | Grep: `^## Output` |
| AGT-008 | Boundaries section | High | Grep: `^## Boundaries` |
| AGT-009 | Description trigger quality | Critical | Must contain "Use when" or "Use PROACTIVELY when" + role identification + tech scope |
| AGT-010 | Tools minimality | Low | All declared tools are referenced in agent body |
| AGT-013 | Model override validity | Medium | Valid model identifier |
| AGT-014 | Permission mode validity | High | Valid permission mode |
| AGT-015 | MaxTurns reasonableness | Low | Between 1 and 100 |
| AGT-016 | Skills preload validity | Medium | Referenced skills exist |
| AGT-017 | MCP server references | Medium | Valid MCP references |
| AGT-018 | Memory scope validity | Medium | Valid scope |
| AGT-019 | Isolation mode validity | Low | Must be "worktree" |
| AGT-020 | Agent hooks validity | High | Valid events and types |

**Skill Validation Rules:**

| ID | Rule | Severity | Check |
|----|------|----------|-------|
| SKL-001 | SKILL.md exists in skill directory | Critical | Glob: `skills/{name}/SKILL.md` |
| SKL-002 | Frontmatter present and valid YAML | Critical | Parse YAML between `---` delimiters |
| SKL-003 | Required frontmatter fields | Critical | name, description |
| SKL-004 | SKILL.md body under 5,000 tokens | High | Estimate: word_count * 1.3 < 5000 |
| SKL-005 | "When to" section present | High | Grep: `^## When to (Apply|Activate|Use)` |
| SKL-006 | References directory consistency | Medium | If references/ exists, all files follow `{prefix}-{topic}.md` naming |
| SKL-007 | Templates directory consistency | Medium | If templates/ exists, all files are referenced in SKILL.md |
| SKL-008 | No orphaned reference files | Low | All reference files are mentioned in SKILL.md or AGENTS.md |
| SKL-009 | Progressive disclosure structure | Medium | SKILL.md links to references, not inlining all content |
| SKL-012 | Agent Skills standard compliance | Low | agentskills.io fields valid |
| SKL-013 | Invocation control consistency | Medium | Not both restricted |
| SKL-014 | Context fork configuration | High | Agent reference valid |
| SKL-015 | Allowed tools validity | Medium | Valid tool names |
| SKL-016 | Model override validity | Medium | Valid model ID |
| SKL-017 | Skill hooks validity | High | Valid events/types |
| SKL-018 | String substitution variables | Low | $ARGUMENTS with argument-hint |

**Hook Validation Rules:**

| ID | Rule | Severity | Check |
|----|------|----------|-------|
| HK-001 | Valid JSON structure | Critical | Parse JSON without errors |
| HK-002 | Matcher expression present | Critical | Non-empty matcher string |
| HK-003 | Hook type validity | High | `hooks[].type` is one of: command, http, prompt, agent |
| HK-004 | Description present | Medium | Non-empty description string |
| HK-005 | No duplicate matchers | High | Unique matcher expressions across all hooks |
| HK-006 | Script command is safe | High | No `rm -rf`, `eval`, or dangerous patterns |
| HK-007 | Event name validity | Critical | One of 22 valid events |
| HK-008 | Handler type completeness | High | Required fields per type |
| HK-009 | HTTP handler URL validity | High | Valid URL format |
| HK-010 | Blocking event consistency | Medium | Non-blocking events check |
| HK-011 | Handler type availability | Medium | Event supports type |
| HK-012 | Async hook configuration | Low | Only on command type |

### Phase 3: Content Quality Validation
Assess the quality of component content beyond structure.

**Description Quality:**
- [ ] Description is specific (not generic like "does things")
- [ ] Description length: 10-300 characters
- [ ] No placeholder text ({{...}}, TODO, FIXME, TBD)
- [ ] Agent descriptions must contain: role identification + trigger phrase ("Use when...") + at least 2 use cases + technology scope
- [ ] Skill descriptions must specify WHEN to use, not just WHAT it does
- [ ] Command descriptions must summarize the command's action and output

**Bad Description Examples:**
- `"Helps with code review"` (no trigger, no scope, too vague)
- `"MongoDB best practices"` (no "when to use")
- `"Testing tool"` (too vague, no specifics)

**Good Description Examples:**
- `"Architecture review specialist that analyzes codebase structure, dependency direction, and design pattern compliance. Use when reviewing projects for architecture conformance, layer violations, naming conventions, and structural integrity. Supports Kotlin (Spring Boot), Python (FastAPI/Django), and TypeScript/JavaScript (Next.js/NestJS)."`
- `"MongoDB performance optimization and best practices. Use this skill when writing, reviewing, or optimizing MongoDB queries, schema designs, aggregation pipelines, or database configurations."`

**Trigger Quality:**
- [ ] Minimum 3 triggers per command
- [ ] Triggers use concrete action phrases
- [ ] No duplicate or overlapping triggers

**Example Quality:**
- [ ] Minimum 2 examples per command
- [ ] Examples include comments explaining behavior
- [ ] Examples cover basic and advanced usage

**Security Check:**
See SEC-001 through SEC-006 in Cross-Reference Validation phase.

### Phase 4: Cross-Reference Validation
Check relationships between components.

**Checks:**

| ID | Rule | Severity | Check |
|----|------|----------|-------|
| XRF-001 | Commands referencing agents | High | Verify agents exist in `agents/` directory |
| XRF-002 | Commands referencing skills | High | Verify skills exist in `skills/` directory |
| XRF-003 | Hooks referencing tools | Medium | Verify tool names are valid |
| XRF-004 | Skills referencing other skills | Medium | Verify cross-links are valid |
| XRF-005 | Personas in command frontmatter | Medium | Verify agent files exist |
| XRF-006 | Agent skill preload references | High | Verify preloaded skills exist |
| XRF-007 | Plugin component references | Critical | Verify bundled skills/agents/hooks exist |
| XRF-008 | MCP server references | Medium | Verify referenced MCP servers are configured |
| XRF-009 | Context fork agent references | High | Verify agent referenced in skill fork exists |

**Security Checks:**

| ID | Rule | Severity | Check |
|----|------|----------|-------|
| SEC-001 | No hardcoded credentials or API keys | Critical | Pattern match for secrets |
| SEC-002 | No unsafe Bash commands in examples | High | No `rm -rf`, `eval`, etc. |
| SEC-003 | Hook scripts don't expose sensitive data | High | No env var leaking |
| SEC-004 | No file paths with user-specific information | Medium | No absolute user paths in templates |
| SEC-005 | HTTP hook URL security | High | HTTPS required for remote URLs |
| SEC-006 | Plugin manifest integrity | Critical | No script injection in plugin.json fields |

### Phase 5: Report Generation
Generate a severity-rated report of all findings.

**Severity Definitions:**

| Severity | Description | Action |
|----------|-------------|--------|
| Critical | Component will not function correctly | Must fix before use |
| High | Component works but violates conventions | Should fix soon |
| Medium | Convention deviation, may cause confusion | Fix when convenient |
| Low | Minor style or optimization suggestion | Optional improvement |

**Health Score Calculation:**
```
Base Score: 100

Deductions:
  Each Critical finding: -20 points
  Each High finding:     -10 points
  Each Medium finding:    -3 points
  Each Low finding:       -1 point

Rules per type (approximate):
  Commands: 11 rules (CMD-001..CMD-013)
  Agents:   18 rules (AGT-001..AGT-020)
  Skills:   16 rules (SKL-001..SKL-018)
  Hooks:    12 rules (HK-001..HK-012)
  Cross-ref: 9 rules (XRF-001..XRF-009)
  Security:  6 rules (SEC-001..SEC-006)

Rating:
  90-100: Excellent - Ready for production use
  75-89:  Good - Minor improvements recommended
  60-74:  Fair - Notable gaps need attention
  40-59:  Poor - Significant issues found
  0-39:   Critical - Not ready for use

Final Score = max(0, Base Score - Deductions)
```

**Report Format:**
```
## Verification Report

### Summary
- Components scanned: N
- Total findings: N (Critical: X, High: X, Medium: X, Low: X)
- Health score: X/100 (Rating)
- Pass rate: X%

### Critical Findings
#### [CMD-001] Missing frontmatter in commands/my-command.md
- **Severity**: Critical
- **Location**: commands/my-command.md:1
- **Issue**: File does not start with YAML frontmatter delimiters (---)
- **Fix**: Add frontmatter block with required fields
  ```yaml
  ---
  name: my-command
  description: "..."
  category: utility
  complexity: basic
  mcp-servers: []
  personas: []
  ---
  ```

### High Findings
...

### Medium Findings
...

### Low Findings
...

### Auto-Fix Summary (--fix auto)
- [x] CMD-010: Reordered sections in commands/my-command.md
- [x] SKL-004: Trimmed SKILL.md to token budget
- [ ] AGT-005: Cannot auto-fix missing workflow (manual required)
```

### Fix Mode Behavior

**--fix suggest (default):**
- Report all findings with suggested fixes
- Show code snippets for each fix
- Do not modify any files

**--fix auto:**
- Automatically fix issues that have safe, deterministic fixes:
  - Reorder sections to match convention
  - Add missing frontmatter fields with defaults
  - Fix file naming to kebab-case
  - Remove placeholder text
- Report issues that require manual intervention
- Show diff of all auto-applied changes
- Use **Write** tool for file modifications
- Use **Edit** tool for targeted section fixes

**Auto-fixable Issues:**

| ID | Fix Description |
|----|----------------|
| CMD-002 | Add missing frontmatter fields with sensible defaults |
| CMD-010 | Reorder sections to match convention |
| AGT-003 | Remove invalid tool names from tools array |
| SKL-006 | Rename reference files to `{prefix}-{topic}.md` pattern |
| HK-004 | Generate description from matcher expression |

**Manual-only Issues:**

| ID | Reason |
|----|--------|
| CMD-006 | Behavioral Flow requires domain-specific content |
| AGT-005 | Workflow steps require understanding of agent purpose |
| SKL-004 | Content reduction requires human judgment |
| HK-006 | Unsafe scripts need manual security review |

## AI Collaboration Options

### --with gemini
```bash
PROMPT="Review the following Claude Code plugin component for quality and convention compliance.
Component type: [type]
Content: [file content]
Conventions: [validation rules summary]
Provide findings with severity ratings and suggested fixes."
```
Execute: `gemini -m gemini-3-pro-preview -p "$PROMPT" --output-format stream-json`

### --with copilot
Execute all 3 models and compare validation findings:
- `copilot --model gpt-5.2-codex -p "$PROMPT"`
- `copilot --model claude-opus-4.5 -p "$PROMPT"`
- `copilot --model gemini-3-pro-preview -p "$PROMPT"`

### --with codex
Execute: `codex --model gpt-5.3-codex-spark xhigh exec "$PROMPT"`

Compare AI validation findings with rule-based results. AI can catch:
- Logical inconsistencies in behavioral flows
- Missing edge cases in examples
- Overly vague or overly specific descriptions
- Content quality issues that rules cannot detect

## Tool Coordination
- **Glob**: Discover component files across project directories
- **Read**: Read component content for validation
- **Grep**: Pattern-match required sections and content rules
- **Write**: Apply auto-fixes to component files (--fix auto)
- **Edit**: Targeted section modifications for auto-fix
- **Bash**: Execute AI collaboration tools, token counting utilities

## Examples

### Validate All Components
```
/verify-flow
# Scans all commands, agents, skills, and hooks
# Generates comprehensive report with all severities
# Suggests fixes for each finding
```

### Validate Specific Command
```
/verify-flow commands/deploy-check.md --target command
# Validates single command file
# Checks structure, content quality, and cross-references
```

### Validate Skills Only
```
/verify-flow --target skill --severity high
# Validates all skills in skills/ directory
# Only reports High and Critical findings
```

### Auto-Fix Common Issues
```
/verify-flow --target command --fix auto
# Scans all commands
# Automatically fixes: section ordering, missing fields, naming
# Reports remaining manual-fix items
```

### JSON Output for CI
```
/verify-flow --target all --format json --severity critical
# Outputs machine-readable JSON for CI pipeline integration
# Only includes critical issues that block functionality
```

### AI-Assisted Validation
```
/verify-flow commands/analyze.md --with gemini
# Rule-based validation + Gemini content review
# Catches both structural and semantic issues
```

### Validate After Creation
```
/create-flow test-runner --type command
/verify-flow commands/test-runner.md --target command
# Create then immediately validate
# Ensures the created component meets all standards
```

## Output Format

### Text Output (--format text)
```
## Verification Report

Target: all | Severity: all | Fix: suggest

### Summary
  Commands:  7 scanned, 2 findings
  Agents:    4 scanned, 1 finding
  Skills:   21 scanned, 3 findings
  Hooks:     5 scanned, 0 findings
  Total:    37 scanned, 6 findings

### Findings by Severity
  Critical: 1 (-20)
  High:     3 (-30)
  Medium:   2  (-6)
  Low:      0   (0)

### Health Score: 44/100 (Poor)
  Base: 100 - Deductions: 56 = 44

### Details
[findings listed by severity, then by component]

### Top 3 Immediate Actions
1. [Most impactful fix - Critical findings first]
2. [Second priority]
3. [Third priority]
```

### JSON Output (--format json)
```json
{
  "summary": {
    "scanned": 37,
    "findings": 6,
    "pass_rate": 83.8,
    "health_score": 44,
    "rating": "Poor"
  },
  "findings": [
    {
      "id": "CMD-006",
      "severity": "critical",
      "component": "commands/my-command.md",
      "line": null,
      "message": "Missing Behavioral Flow section",
      "fix": "Add ## Behavioral Flow section with phased workflow",
      "auto_fixable": false
    }
  ]
}
```

## Boundaries

**Will:**
- Validate structure, content, and cross-references of all component types
- Generate severity-rated reports with actionable fix suggestions
- Auto-fix deterministic structural issues when `--fix auto` is specified
- Support JSON output for CI pipeline integration
- Detect security concerns in hook scripts and examples
- Verify token budgets for skill files
- Cross-validate component references

**Will Not:**
- Validate runtime behavior or execution correctness
- Fix content quality issues automatically (requires human judgment)
- Modify files without `--fix auto` flag
- Validate MCP server configurations or external dependencies
- Delete components even if they fail all checks
- Override user-customized sections that deviate from templates

## Related

- `/create-flow` - Scaffolds new components that pass verify-flow checks (complementary pair)
- `/arch-review` - Architecture code review (complementary structural analysis)
- `/perf-review` - Performance code review (complementary performance analysis)
- `/analyze` - Broader code analysis with AI collaboration
