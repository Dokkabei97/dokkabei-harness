# Skill Validation Rules (SKL-*)

## SKL-001: SKILL.md Exists
- **Severity**: Critical
- **Check**: `skills/{name}/SKILL.md` file exists
- **Auto-fixable**: No (requires content)

## SKL-002: Frontmatter Present and Valid YAML
- **Severity**: Critical
- **Check**: SKILL.md starts with `---` and contains valid YAML
- **Auto-fixable**: No

## SKL-003: Required Frontmatter Fields
- **Severity**: Critical
- **Check**: YAML contains: name, description
- **Auto-fixable**: Yes (derive name from directory name)

## SKL-004: Token Budget
- **Severity**: High
- **Check**: SKILL.md body under 5,000 tokens (approx word_count * 1.3)
- **Auto-fixable**: No (content reduction needs judgment)
- **Thresholds**: Optimal < 3,500, Acceptable < 5,000, Over > 5,000

## SKL-005: "When to" Section
- **Severity**: High
- **Check**: Section matching `## When to (Apply|Activate|Use)` with 3+ conditions
- **Auto-fixable**: No
- **Accepted variants**: `## When to Apply`, `## When to Activate`, `## When to Use`

## SKL-006: Reference File Naming
- **Severity**: Medium
- **Check**: Files in references/ follow `{prefix}-{topic}.md` pattern
- **Auto-fixable**: Yes (rename files to match pattern)
- **Pattern**: `^[a-z]+-[a-z0-9-]+\.md$`

## SKL-007: Template References
- **Severity**: Medium
- **Check**: All files in templates/ are referenced in SKILL.md
- **Auto-fixable**: No (missing reference may be intentional)

## SKL-008: Orphaned References
- **Severity**: Low
- **Check**: All reference files are mentioned in SKILL.md or AGENTS.md
- **Auto-fixable**: No (orphan may be newly added)

## SKL-009: Progressive Disclosure
- **Severity**: Medium
- **Check**: SKILL.md provides overview, references/ provides detail
- **Auto-fixable**: No (requires content restructuring)
- **Signal**: If SKILL.md > 3,500 tokens and no references/ directory, suggest splitting
- **Levels**: Level 1 (SKILL.md overview) -> Level 2 (AGENTS.md/CLAUDE.md navigation) -> Level 3 (references/*.md details)

## SKL-010: Description Trigger Quality
- **Severity**: Medium
- **Check**: Description specifies WHEN to use, not just WHAT it does
- **Auto-fixable**: No
- **Good example**: "MongoDB performance optimization and best practices. Use this skill when writing, reviewing, or optimizing MongoDB queries, schema designs, aggregation pipelines, or database configurations."
- **Bad example**: "MongoDB best practices"

## SKL-011: References Index File
- **Severity**: Low
- **Check**: If references/ directory has 5+ files, a `_sections.md` index file is recommended
- **Auto-fixable**: Yes (generate index from directory listing)
- **Pattern**: Based on mongodb-best-practices which uses `_sections.md` for navigation

## SKL-012: Agent Skills Standard Compliance
- **Severity**: Low
- **Check**: If `license` or `compatibility` fields present, they follow agentskills.io spec
- **Auto-fixable**: No

## SKL-013: Invocation Control Consistency
- **Severity**: Medium
- **Check**: `disable-model-invocation` and `user-invocable` are not both set to restrictive values (would make skill unreachable)
- **Auto-fixable**: No
- **Bad**: `disable-model-invocation: true` AND `user-invocable: false` (skill is completely hidden)

## SKL-014: Context Fork Configuration
- **Severity**: High
- **Check**: If `context: fork` is set, `agent` field should reference a valid agent (built-in: Explore, Plan, general-purpose, Bash, or custom in `.claude/agents/`)
- **Auto-fixable**: No

## SKL-015: Allowed Tools Validity
- **Severity**: Medium
- **Check**: If `allowed-tools` specified, each tool name is valid
- **Auto-fixable**: Yes (remove invalid entries)
- **Valid tools**: Read, Write, Edit, Bash, Glob, Grep, WebSearch, WebFetch, Agent, Skill, NotebookEdit

## SKL-016: Model Override Validity
- **Severity**: Medium
- **Check**: If `model` specified, it's a valid model identifier
- **Auto-fixable**: No
- **Valid values**: sonnet, opus, haiku, or full model ID

## SKL-017: Skill Hooks Validity
- **Severity**: High
- **Check**: If `hooks` defined in frontmatter, each hook has valid event and handler type
- **Auto-fixable**: No
- **Valid events in skill scope**: PreToolUse, PostToolUse, Stop
- **Valid handler types**: command, http, prompt, agent

## SKL-018: String Substitution Variables
- **Severity**: Low
- **Check**: If skill body uses `$ARGUMENTS`, verify `argument-hint` is set for documentation
- **Auto-fixable**: No
