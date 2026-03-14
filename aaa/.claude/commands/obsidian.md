---
name: obsidian
description: "Obsidian-based technical learning note generation. Systematic learning records using 7 templates (concept, lab, comparison, troubleshoot, pattern, TIL, MOC)."
category: documentation
complexity: basic
mcp-servers: []
personas: []
---

# /obsidian - Technical Learning Note Generation

## Triggers
- Writing technical concept learning notes
- Recording code labs/tutorials
- Comparative analysis of libraries/frameworks
- Documenting error resolution/troubleshooting
- Learning architecture/design patterns
- Writing TIL (Today I Learned) entries
- Creating MOC (Map of Content) indexes

## Usage
```
/obsidian [type] [topic]

Types:
  concept        Technical concept learning note
  lab            Code lab/tutorial record
  comparison     Library/framework comparative analysis
  troubleshoot   Error resolution/troubleshooting record
  pattern        Architecture/design pattern learning
  til            TIL (Today I Learned) entry
  moc            MOC (Map of Content) index generation
```

## Behavioral Flow

### 1. Determine Document Type
If the user does not specify a type, auto-detect from the topic keywords:

| Keyword | Inferred Type |
|---------|---------------|
| vs, compare, difference, alternative | comparison |
| error, bug, fix, resolve, debug | troubleshoot |
| pattern, architecture, design | pattern |
| lab, tutorial, hands-on, workshop | lab |
| TIL, today | til |
| MOC, index, list, roadmap | moc |
| Other | concept (default) |

### 2. Template-Based Note Generation
1. Reference the `skills/obsidian-tech-note/` skill
2. Load the template for the corresponding type
3. Populate note content reflecting the user's topic
4. Follow Obsidian YAML frontmatter format
5. Preserve Templater syntax (`<% %>`) as-is for execution within Obsidian

### 3. Output
- Create the file directly in the Obsidian Vault, or
- Output the markdown content for the user to copy/save

## Examples

### Technical Concept Learning
```
/obsidian concept React Hooks
# Generates a React Hooks concept learning note
# Includes definition, core principles, code examples, and learning checklist
```

### Code Lab Record
```
/obsidian lab Spring Boot REST API
# Generates a Spring Boot REST API lab note
# Includes environment setup, step-by-step code, execution results, and troubleshooting memo
```

### Comparative Analysis
```
/obsidian comparison React vs Vue
# Generates a React vs Vue comparative analysis note
# Includes comparison table, pros/cons, code comparison, and decision matrix
```

### Troubleshooting
```
/obsidian troubleshoot OOM Kubernetes
# Generates a Kubernetes OOM troubleshooting note
# Includes error message, root cause analysis, resolution steps, and prevention measures
```

### Architecture Pattern
```
/obsidian pattern CQRS
# Generates a CQRS pattern learning note
# Includes pattern overview, Mermaid diagram, implementation examples, and trade-offs
```

### TIL
```
/obsidian til
# Generates a TIL note for today's date
# Includes what was learned, key code snippets, problem-solving records, and tomorrow's tasks
```

### MOC Index
```
/obsidian moc Frontend
# Generates a Frontend MOC index
# Includes DataView query-based auto note listing and learning progress statistics
```

## Tool Coordination
- **Read**: Reference existing notes/templates
- **Write**: Create note files
- **WebSearch**: Research technical topics (when needed)
- **Bash**: File system operations (e.g., verifying Vault paths)

## Boundaries

**Will:**
- Generate Obsidian markdown notes matching 7 template types
- Follow Obsidian conventions including YAML frontmatter, tags, and wiki-links
- Include Templater/DataView/Tasks plugin syntax
- Research and organize content for the user's topic

**Will Not:**
- Control the Obsidian app itself or install plugins
- Modify user Vault settings
- Guarantee accuracy of learning content (user verification required)

## Related

- `skills/obsidian-tech-note/SKILL.md` - Template system guide
- `skills/obsidian-tech-note/templates/` - 7 template files
- `skills/document/SKILL.md` - General-purpose document writing skill
