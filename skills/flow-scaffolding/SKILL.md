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

## Template Complexity Levels

| Level | Description | Sections | Use Case |
|-------|-------------|----------|----------|
| `minimal` | Core structure only | Required sections with minimal content | Quick prototyping |
| `standard` | Complete structure | All required + common optional sections | Most components |
| `advanced` | Full-featured | All sections + AI collaboration + references | Complex workflows |

## Naming Conventions

| Component | File Pattern | Name Format |
|-----------|-------------|-------------|
| Command | `commands/{name}.md` | kebab-case verb-noun (e.g., `deploy-check`) |
| Agent | `agents/{name}.md` | kebab-case role-noun (e.g., `security-scanner`) |
| Skill | `skills/{name}/SKILL.md` | kebab-case domain-noun (e.g., `redis-best-practices`) |
| Hook | Entry in `settings.json` | descriptive sentence |

## Frontmatter Field Reference

### Command Fields
| Field | Required | Type | Example |
|-------|----------|------|---------|
| `name` | Yes | string | `"deploy-check"` |
| `description` | Yes | string | `"Pre-deployment validation..."` |
| `category` | Yes | string | `"utility"` / `"review"` / `"workflow"` |
| `complexity` | Yes | string | `"basic"` / `"advanced"` |
| `mcp-servers` | Yes | array | `[]` or `["grafana"]` |
| `personas` | Yes | array | `[]` or `["arch-reviewer"]` |

### Agent Fields
| Field | Required | Type | Example |
|-------|----------|------|---------|
| `name` | Yes | string | `"security-scanner"` |
| `description` | Yes | string | `"Security analysis specialist..."` |
| `tools` | Yes | array | `["Read", "Grep", "Glob", "Bash"]` |

### Skill Fields
| Field | Required | Type | Example |
|-------|----------|------|---------|
| `name` | Yes | string | `"redis-best-practices"` |
| `description` | Yes | string (multiline) | `"Redis optimization guide..."` |

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
