---
name: create-flow
description: "Interactive scaffolding command that creates custom agents, commands, skills, and hooks following project conventions. Supports auto-detection or explicit type selection with multi-phase guided workflow."
category: utility
complexity: advanced
mcp-servers: []
personas: []
---

# /create-flow - Component Scaffolding and Creation

## Triggers

> **Note:** As of Claude Code v2.1.3, commands and skills have been merged. The `/create-flow` command can create both legacy command format and the newer skill format. Existing commands continue to work, and this scaffolder supports both formats seamlessly.

- Creating a new agent, command, skill, plugin, or hook for the project
- Scaffolding new workflow components with proper structure and conventions
- Bootstrapping multiple related components (e.g., command + supporting skill + agent)
- Extending existing project capabilities with new flows

## Usage
```
/create-flow [name] [options]

Options:
  --type agent|command|skill|hook|plugin|all  Component type (default: auto-detect)
  --with copilot|gemini|codex            AI collaboration for design decisions
  --template minimal|standard|advanced    Template complexity (default: standard)
  --interactive true|false                Interactive mode (default: true)
```

## Behavioral Flow

### Phase 1: Discovery
Analyze the user's request and existing project structure to determine what to create.

**Auto-Detection Logic:**
When `--type` is not specified, detect the intended component type from the name and context:

| Signal | Detected Type | Rationale |
|--------|---------------|-----------|
| Name contains action verb (analyze, review, test, deploy) | command | Commands are action-oriented |
| Name contains role noun (reviewer, runner, guide, assistant) | agent | Agents are role-based personas |
| Name contains domain noun (best-practices, workflow, patterns) | skill | Skills are knowledge-based |
| Name contains event noun (pre-push, on-save, before-commit) | hook | Hooks are event-driven |
| Name contains manifest/plugin/bundle terms | plugin | Plugins are distribution bundles |
| Ambiguous or multi-component | prompt user | Use AskUserQuestion for clarification |

**Existing Structure Scan:**
```
Glob: commands/*.md               -> List existing commands
Glob: agents/*.md                 -> List existing agents
Glob: .claude/agents/*.md         -> List existing agents (new location)
Glob: skills/*/SKILL.md           -> List existing skills
Glob: .claude-plugin/plugin.json  -> Check existing plugins
Read: claude/settings.json        -> Check existing hooks and plugins
```

Present discovered context to user:
```
Existing components:
  Commands (N): analyze, arch-review, e2e, handoff, ...
  Agents (N):   arch-reviewer, e2e-runner, ...
  Skills (N):   mongodb-best-practices, obsidian-tech-note, ...
  Hooks (N):    pre-push review, tmux reminder, ...

Detected type: [type] (from name analysis)
Proceed with [type]? (y/n/change)
```

### Phase 2: Component Planning
Define the scope and relationships of the new component.

**For Commands:**
1. **Purpose Definition**: Ask user for the command's core purpose (1 sentence)
2. **Option Design**: Determine CLI options (flags, arguments)
3. **Flow Complexity**: Choose between linear flow, branching flow, or multi-phase flow
4. **Tool Requirements**: Identify which tools the command will coordinate (Read, Grep, Glob, Bash, Write, etc.)
5. **AI Collaboration**: Determine if `--with` option is needed

**For Agents:**
1. **Role Definition**: Define the agent's persona and expertise domain
2. **Tool Selection**: Choose tools the agent needs (`["Read", "Grep", "Glob", "Bash"]`)
3. **Workflow Steps**: Plan the agent's step-by-step analysis workflow
4. **Language Support**: Determine supported languages/frameworks
5. **Output Format**: Define the agent's report structure
6. **Model Selection**: Choose model override (`sonnet`, `opus`, `haiku`, `inherit`)
7. **Permission Mode**: Set permission mode for agent execution
8. **Persistent Memory**: Configure `memory` scope (user, project, local)
9. **Isolation**: Determine if agent needs `isolation: worktree`
10. **Skill Preloading**: List skills to preload into agent context

**For Skills:**
1. **Domain Definition**: Define the knowledge domain and when to apply
2. **Reference Planning**: Determine if references/ directory is needed
3. **Template Planning**: Determine if templates/ directory is needed
4. **Category Structure**: Plan reference file naming with prefixes
5. **Token Budget**: Ensure SKILL.md stays under 5,000 tokens
6. **Invocation Control**: Configure `disable-model-invocation` and `user-invocable`
7. **Subagent Mode**: Determine if skill needs `context: fork` with specific `agent`
8. **Hooks**: Define skill-scoped lifecycle hooks if needed
9. **Allowed Tools**: Specify tools allowed without permission when skill is active

**For Plugins:**
1. **Manifest Definition**: Define plugin name, description, version, author
2. **Component Bundle**: Determine which skills, agents, hooks, and MCP servers to include
3. **Namespace Planning**: Plan skill namespacing (`plugin-name:skill-name`)
4. **Distribution**: Choose distribution method (git, marketplace)

**For Hooks:**
1. **Event Selection**: Choose hook event (PreToolUse, PostToolUse, etc.)
2. **Matcher Design**: Define the tool/condition matcher expression
3. **Action Type**: Choose between block, warn, or transform
4. **Script Logic**: Plan the hook's Node.js script logic

### Phase 3: Design
Generate the component design document and confirm with the user before implementation.

**Design Preview Template:**
```
## Component Design: [name]
Type: [agent|command|skill|hook]
Category: [category]

### Structure
[File tree showing what will be created]

### Key Sections
[Outline of major sections/features]

### Dependencies
[Related components, MCP servers, tools]

### Estimated Size
[Token count estimate for main file]

Proceed with implementation? (y/n/modify)
```

Use **AskUserQuestion** at each decision point where multiple valid approaches exist:
- Naming conventions (kebab-case for files, descriptive for frontmatter)
- Section ordering and content depth
- Whether to include AI collaboration support
- Whether supporting skills/agents are needed

### Phase 4: Implementation
Generate the component files following project conventions.

**Command Generation (`commands/{name}.md`):**

Frontmatter:
```yaml
---
name: {name}
description: "{description}"
category: {category}
complexity: {complexity}
mcp-servers: [{mcp-servers}]
personas: [{personas}]
---
```

Required sections (in order):
1. `# /{name} - {Title}` - H1 heading with slash-command name
2. `## Triggers` - When this command should be activated
3. `## Usage` - CLI syntax with options in code block
4. `## Behavioral Flow` - Phased workflow with numbered steps
5. `## Tool Coordination` - List of tools and their roles
6. `## Examples` - Concrete usage examples with code blocks
7. `## Boundaries` - Will / Will Not lists

Optional sections:
- `## AI Collaboration Options` - If `--with` is supported
- `## Output Format` - If structured output is generated
- `## Key Patterns` - If domain-specific patterns apply

**Agent Generation (`agents/{name}.md`):**

Frontmatter:
```yaml
---
name: {name}
description: "{description}"
tools: [{tools}]
# model: {sonnet|opus|haiku|inherit}
# permissionMode: {default|acceptEdits|plan}
# maxTurns: {number}
# skills: [{skills}]
# mcpServers: [{servers}]
# memory: {user|project|local}
# background: false
# isolation: worktree
---
```

Required sections:
1. `# {Role Title}` - Agent persona description
2. `## Your Role` - Bullet list of responsibilities
3. `## Analysis Workflow` - Numbered steps with sub-steps
4. Decision matrices with Glob/Grep patterns per step
5. `## Output Format` - Report template
6. `## Boundaries` - Scope limitations

**Skill Generation (`skills/{name}/`):**

Directory structure:
```
skills/{name}/
  SKILL.md          # Main skill file (< 5,000 tokens)
  references/       # Optional: detailed reference files
  templates/        # Optional: template files
```

SKILL.md frontmatter:
```yaml
---
name: {name}
description: |
  {multi-line description}
# argument-hint: {hint}
# disable-model-invocation: false
# user-invocable: true
# allowed-tools: []
# model: {model}
# context: fork
# agent: {agent-type}
---
```

Required sections:
1. `# {Skill Title}` - H1 heading
2. `## When to Apply` - Trigger conditions
3. `## {Domain Content}` - Core knowledge organized by priority
4. `## How to Use` - Reference file usage instructions
5. `## References` - External links (if applicable)

If references are needed, create `references/` with `{prefix}-{topic}.md` naming.
If templates are needed, create `templates/` with descriptive filenames.

**Plugin Generation (`.claude-plugin/`):**

Directory structure:
```
.claude-plugin/
  plugin.json       # Manifest (required)
skills/             # Bundled skills
agents/             # Bundled agents
hooks/
  hooks.json        # Event handlers
.mcp.json           # MCP server configurations
```

plugin.json:
```json
{
  "name": "{plugin-name}",
  "description": "{description}",
  "version": "{version}",
  "author": { "name": "{author}" },
  "homepage": "{url}",
  "repository": "{repo-url}",
  "license": "{license}"
}
```

**Hook Generation (update `claude/settings.json`):**

Hook structure:
```json
{
  "hooks": {
    "{event}": [
      {
        "matcher": "{matcher}",
        "hooks": [
          {
            "type": "command",
            "command": "{shell command}"
          }
        ]
      }
    ]
  }
}
```
Note the 4 handler types: command, http, prompt, agent.
Note the 22 valid events.

### Phase 5: Validation
Verify the generated component meets project standards.

**Structural Checks:**
- [ ] Frontmatter contains all required fields
- [ ] All required sections present in correct order
- [ ] File naming follows conventions (kebab-case)
- [ ] Directory structure matches component type pattern

**Content Checks:**
- [ ] Description is specific and actionable
- [ ] Triggers are concrete (not vague)
- [ ] Examples include realistic usage scenarios
- [ ] Boundaries clearly define scope
- [ ] Token budget respected (skills: < 5,000 tokens for SKILL.md)

**Integration Checks:**
- [ ] No naming conflicts with existing components
- [ ] Tool references are valid
- [ ] Cross-references to other components are correct
- [ ] Hook matchers don't conflict with existing hooks

**Report to User:**
```
## Creation Summary

Created:
  [x] commands/my-command.md (3,200 tokens)
  [x] skills/my-skill/SKILL.md (2,800 tokens)
  [x] skills/my-skill/templates/template-a.md

Validation:
  [PASS] Structure check
  [PASS] Content check
  [PASS] Integration check

Next steps:
  1. Review generated files
  2. Test the command: /my-command
  3. Iterate on content as needed
```

## AI Collaboration Options

### --with gemini
```bash
PROMPT="Design a [type] component named [name] for a Claude Code plugin project.
Purpose: [user description]
Conventions: YAML frontmatter, phased behavioral flow, tool coordination, boundaries section.
Generate the complete markdown file following these patterns."
```
Execute: `gemini -m gemini-3-pro-preview -p "$PROMPT" --output-format stream-json`

### --with copilot
Execute all 3 models and compare:
- `copilot --model gpt-5.2-codex -p "$PROMPT"`
- `copilot --model claude-opus-4.5 -p "$PROMPT"`
- `copilot --model gemini-3-pro-preview -p "$PROMPT"`

### --with codex
Execute: `codex --model gpt-5.3-codex-spark xhigh exec "$PROMPT"`

Compare AI outputs with Claude's design and select the best structure for each section.

## Tool Coordination
- **Glob**: Scan existing components for naming conflicts and pattern reference
- **Read**: Read existing components as reference patterns
- **Grep**: Search for cross-references and dependencies
- **Write**: Generate new component files
- **Bash**: Execute AI collaboration tools (Gemini/Copilot/Codex CLI)
- **AskUserQuestion**: Interactive design decisions at each phase

## Key Patterns
- **Progressive Disclosure**: Metadata first, then body, then references
- **Convention Over Configuration**: Auto-detect type, use standard templates
- **Interactive Design**: User confirms each major decision before proceeding
- **Validation First**: Check naming conflicts and structure before writing files

## Examples

### Create a New Command
```
/create-flow deploy-check --type command
# Interactive workflow:
# 1. Discovers existing commands, confirms no naming conflict
# 2. Asks about purpose, options, flow complexity
# 3. Shows design preview with sections outline
# 4. Generates commands/deploy-check.md with full structure
# 5. Validates and reports creation summary
```

### Create a New Skill with References
```
/create-flow redis-best-practices --type skill --template advanced
# Interactive workflow:
# 1. Detects "best-practices" pattern -> skill type
# 2. Plans reference categories (caching, pub-sub, data-types, etc.)
# 3. Creates skills/redis-best-practices/ directory structure
# 4. Generates SKILL.md + reference files with prefix naming
# 5. Validates token budget and structure
```

### Create a New Agent
```
/create-flow security-scanner --type agent
# Interactive workflow:
# 1. Detects "scanner" pattern -> agent type
# 2. Defines security analysis persona and workflow
# 3. Plans OWASP-based detection steps with grep patterns
# 4. Generates agents/security-scanner.md
# 5. Validates tool references and workflow completeness
```

### Auto-Detect Component Type
```
/create-flow api-validator
# Auto-detection: "validator" suggests agent or command
# Prompts user: "Should this be a command (/api-validator)
#   or an agent (autonomous validation persona)?"
# Proceeds based on user choice
```

### Create Multiple Related Components
```
/create-flow db-migration --type all
# Creates:
# - commands/db-migration.md (orchestration command)
# - agents/db-migration-reviewer.md (review agent)
# - skills/db-migration-patterns/SKILL.md (knowledge base)
# - Hook: pre-push migration check
```

### AI-Assisted Creation
```
/create-flow test-coverage --type command --with gemini
# Collaborates with Gemini on command design
# Compares Claude and Gemini proposals
# Selects optimal structure for each section
```

## Boundaries

**Will:**
- Create properly structured agents, commands, skills, and hooks
- Auto-detect component type from name patterns
- Interactively guide users through design decisions
- Validate generated components against project conventions
- Support AI collaboration for design assistance
- Generate complete file structures with all required sections
- Check for naming conflicts with existing components

**Will Not:**
- Overwrite existing components without explicit confirmation
- Create components that violate project naming conventions
- Generate skill files exceeding 5,000 token budget
- Skip validation phase even when using AI collaboration
- Modify existing components (use dedicated editing commands instead)
- Create components outside the standard directory structure

## Related

- `/verify-flow` - Validate created components against project conventions
- `/create-flow` - This command (scaffolding and creation)
- `skills/flow-scaffolding/SKILL.md` - Templates for each component type
- `skills/flow-validation/SKILL.md` - Validation rules reference
