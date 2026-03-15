# Command Validation Rules (CMD-*)

> **Note**: As of Claude Code v2.1.3, commands and skills have been merged.
> New components should use the skill format (`skills/{name}/SKILL.md`).
> These rules remain valid for existing command files and backward compatibility.

## CMD-001: Frontmatter Present and Valid YAML
- **Severity**: Critical
- **Check**: File starts with `---` and contains valid YAML block
- **Auto-fixable**: No (cannot generate meaningful content)
- **Pattern**: `^---\n[\s\S]+?\n---`

## CMD-002: Required Frontmatter Fields
- **Severity**: Critical
- **Check**: YAML contains: name, description, category, complexity, mcp-servers, personas
- **Auto-fixable**: Yes (add missing fields with defaults)
- **Defaults**: `category: "utility"`, `complexity: "basic"`, `mcp-servers: []`, `personas: []`
- **Valid categories**: `review`, `utility`, `documentation`
- **Valid complexity**: `basic`, `intermediate`, `advanced`
- **Name must match filename**: `commands/{name}.md`

## CMD-003: H1 Heading Pattern
- **Severity**: High
- **Check**: First H1 matches `# /{name} - {Title}` where name matches frontmatter
- **Auto-fixable**: Yes (generate from frontmatter name)
- **Pattern**: `^# /[a-z][a-z0-9-]+ - .{3,}`

## CMD-004: Triggers Section
- **Severity**: High
- **Check**: `## Triggers` section exists with 3+ bullet items
- **Auto-fixable**: No (requires domain knowledge)
- **Pattern**: `^## Triggers\n(- .+\n){3,}`

## CMD-005: Usage Section with Code Block
- **Severity**: High
- **Check**: `## Usage` section exists with fenced code block showing syntax
- **Auto-fixable**: No (requires understanding of command purpose)
- **Pattern**: `^## Usage\n` followed by triple backtick block

## CMD-006: Behavioral Flow Section
- **Severity**: Critical
- **Check**: `## Behavioral Flow` section exists with numbered phases
- **Auto-fixable**: No (core command logic)
- **Pattern**: `^## Behavioral Flow` with `### Phase` or `### Step` subsections

## CMD-007: Tool Coordination Section
- **Severity**: Medium
- **Check**: `## Tool Coordination` section listing tools used
- **Auto-fixable**: Yes (generate from tool references in Behavioral Flow)
- **Pattern**: `^## Tool Coordination\n(- \*\*.+\*\*: .+\n)+`

## CMD-008: Examples Section
- **Severity**: High
- **Check**: `## Examples` with 2+ code block examples
- **Auto-fixable**: No (requires realistic usage scenarios)
- **Pattern**: `^## Examples` with 2+ fenced code blocks

## CMD-009: Boundaries Section
- **Severity**: High
- **Check**: `## Boundaries` with both `**Will:**` and `**Will Not:**` subsections
- **Auto-fixable**: No (requires scope understanding)
- **Pattern**: `**Will:**` and `**Will Not:**` within Boundaries section

## CMD-010: Section Ordering
- **Severity**: Medium
- **Check**: Sections appear in conventional order
- **Auto-fixable**: Yes (reorder sections)
- **Expected Order**: Triggers, Usage, Behavioral Flow, [AI Collaboration], Tool Coordination, [Key Patterns], Examples, [Output Format], Boundaries, [Related]

## CMD-011: AI Collaboration Consistency
- **Severity**: Low
- **Check**: If `--with` option exists in Usage section, a corresponding `## AI Collaboration Options` section must exist with execution flows for each AI tool
- **Auto-fixable**: No (requires prompt design)

## CMD-012: Related Section
- **Severity**: Low
- **Check**: `## Related` section exists cross-referencing related commands, agents, and skills
- **Auto-fixable**: No (requires knowledge of project relationships)
- **Recommended**: Include links to complementary commands and supporting skills/agents

## CMD-013: Migration Advisory
- **Severity**: Low
- **Check**: Command file could be migrated to skill format for future compatibility
- **Auto-fixable**: No (migration requires structural changes)
