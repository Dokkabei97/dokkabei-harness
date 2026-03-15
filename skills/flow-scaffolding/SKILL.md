---
name: flow-scaffolding
description: |
  Template system for scaffolding Claude Code plugin components.
  Provides ready-to-use templates for agents, commands, skills, and hooks
  following project conventions. Used by the /create-flow command.
---

# Flow Scaffolding Templates

Standardized templates for creating new Claude Code plugin components. Each template includes required frontmatter, section structure, and placeholder content that follows project conventions.

## When to Apply

Reference these templates when:
- Creating new agents, commands, skills, or hooks via `/create-flow`
- Manually scaffolding components and need the correct structure
- Validating existing components against standard structure

## Component Templates

### 1. Command Template
File: [templates/command.md](templates/command.md)

Creates a command in `commands/{name}.md` with:
- YAML frontmatter (name, description, category, complexity, mcp-servers, personas)
- Standard sections: Triggers, Usage, Behavioral Flow, Tool Coordination, Examples, Boundaries
- Optional AI collaboration section

### 2. Agent Template
File: [templates/agent.md](templates/agent.md)

Creates an agent in `agents/{name}.md` with:
- YAML frontmatter (name, description, tools)
- Standard sections: Role, Analysis Workflow, Decision Matrices, Output Format, Boundaries
- Step-by-step workflow with Glob/Grep patterns

### 3. Skill Template
File: [templates/skill.md](templates/skill.md)

Creates a skill directory `skills/{name}/` with:
- SKILL.md with frontmatter (name, description)
- Standard sections: When to Apply, Domain Content, How to Use, References
- Optional references/ and templates/ directories

### 4. Hook Template
File: [templates/hook.json](templates/hook.json)

Creates a hook entry for `claude/settings.json` with:
- Matcher expression for tool/condition filtering
- Hook command (Node.js script)
- Description

### 5. Plugin Template
File: [templates/plugin.json](templates/plugin.json)

Creates a plugin manifest in `.claude-plugin/plugin.json` with:
- Plugin metadata (name, description, version, author)
- Directory structure for bundled skills, agents, hooks, MCP servers

## Template Complexity Levels

| Level | Description | Sections | Use Case |
|-------|-------------|----------|----------|
| `minimal` | Core structure only | Required sections with minimal content | Quick prototyping |
| `standard` | Complete structure | All required + common optional sections | Most components |
| `advanced` | Full-featured | All sections + AI collaboration + references + plugin manifest | Complex workflows |

## Naming Conventions

| Component | File Pattern | Name Format |
|-----------|-------------|-------------|
| Command | `commands/{name}.md` | kebab-case verb-noun (e.g., `deploy-check`) |
| Agent | `agents/{name}.md` | kebab-case role-noun (e.g., `security-scanner`) |
| Skill | `skills/{name}/SKILL.md` | kebab-case domain-noun (e.g., `redis-best-practices`) |
| Hook | Entry in `settings.json` | descriptive sentence |
| Plugin | `.claude-plugin/plugin.json` | kebab-case (e.g., `my-plugin`) |

## Frontmatter Field Reference

### Command Fields (Legacy)
> As of Claude Code v2.1.3, commands and skills are unified.
> New components should use skill format. Command format is maintained for backward compatibility.

| Field | Required | Type | Example |
|-------|----------|------|---------|
| `name` | Yes | string | `"deploy-check"` |
| `description` | Yes | string | `"Pre-deployment validation..."` |
| `category` | Yes | string | `"utility"` / `"review"` / `"workflow"` |
| `complexity` | Yes | string | `"basic"` / `"advanced"` |
| `mcp-servers` | Yes | array | `[]` or `["grafana"]` |
| `personas` | Yes | array | `[]` or `["arch-reviewer"]` |

### Skill Fields
| Field | Required | Type | Example |
|-------|----------|------|---------|
| `name` | No* | string | `"redis-best-practices"` |
| `description` | Recommended | string (multiline) | `"Redis optimization guide..."` |
| `argument-hint` | No | string | `"[issue-number]"` |
| `disable-model-invocation` | No | boolean | `true` |
| `user-invocable` | No | boolean | `false` |
| `allowed-tools` | No | array | `["Read", "Grep"]` |
| `model` | No | string | `"sonnet"` / `"opus"` |
| `context` | No | string | `"fork"` |
| `agent` | No | string | `"Explore"` / `"Plan"` |
| `hooks` | No | object | `{PreToolUse: [...]}` |

*Defaults to directory name if omitted.

#### Agent Skills Open Standard Fields (Optional)
| Field | Type | Example |
|-------|------|---------|
| `license` | string | `"MIT"` |
| `compatibility` | array | `["claude-code", "cursor", "gemini-cli"]` |
| `metadata` | object | `{version: "1.0", category: "review"}` |

### Agent Fields
| Field | Required | Type | Example |
|-------|----------|------|---------|
| `name` | Yes | string | `"security-scanner"` |
| `description` | Yes | string | `"Security analysis specialist..."` |
| `tools` | No | array | `["Read", "Grep", "Glob", "Bash"]` |
| `disallowedTools` | No | array | `["Write", "Edit"]` |
| `model` | No | string | `"sonnet"` / `"opus"` / `"haiku"` / `"inherit"` |
| `permissionMode` | No | string | `"acceptEdits"` / `"plan"` |
| `maxTurns` | No | number | `50` |
| `skills` | No | array | `["my-skill"]` |
| `mcpServers` | No | array | `["server-name"]` or inline config |
| `hooks` | No | object | `{PreToolUse: [...]}` |
| `memory` | No | string | `"user"` / `"project"` / `"local"` |
| `background` | No | boolean | `true` |
| `isolation` | No | string | `"worktree"` |

### Plugin Fields (plugin.json)
| Field | Required | Type | Example |
|-------|----------|------|---------|
| `name` | Yes | string | `"my-plugin"` |
| `description` | Yes | string | `"Plugin description..."` |
| `version` | Yes | string | `"1.0.0"` |
| `author` | No | object | `{"name": "Author Name"}` |
| `homepage` | No | string | URL |
| `repository` | No | string | Git URL |
| `license` | No | string | `"MIT"` |

## String Substitution Variables

Available in skill body content:

| Variable | Description |
|----------|-------------|
| `$ARGUMENTS` | All arguments passed to the skill |
| `$ARGUMENTS[N]` / `$N` | Specific argument by 0-based index |
| `${CLAUDE_SESSION_ID}` | Current session ID |
| `${CLAUDE_SKILL_DIR}` | Directory containing the skill's SKILL.md |

Dynamic context injection via shell:
```
!`command`    # Output replaces placeholder before Claude sees content
```

## Skill Loading Priority

| Priority | Location | Scope |
|----------|----------|-------|
| 1 | Enterprise (managed settings) | Organization-wide |
| 2 | Personal (`~/.claude/skills/`) | All projects |
| 3 | Project (`.claude/skills/`) | Current project |
| 4 | Plugin (`<plugin>/skills/`) | Namespaced |

## Section Content Guidelines

### Triggers
- Use concrete action phrases, not vague descriptions
- List 4-6 specific scenarios
- Each trigger should be independently sufficient to activate the component

### Behavioral Flow
- Number each phase sequentially
- Use bold phase names: **Phase 1: Discovery**
- Include sub-steps with tool-specific instructions
- Decision matrices for branching logic

### Examples
- Minimum 2 examples per command
- Include both simple and complex usage
- Show expected output or behavior in comments
- Cover edge cases in advanced examples

### Boundaries
- **Will**: 5-8 specific capabilities
- **Will Not**: 3-5 explicit limitations
- Use active voice, be specific about what is in/out of scope
