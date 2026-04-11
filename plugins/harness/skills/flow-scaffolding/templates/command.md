---
name: {{NAME}}
description: "{{DESCRIPTION}}"
category: {{CATEGORY}}
complexity: {{COMPLEXITY}}
mcp-servers: [{{MCP_SERVERS}}]
personas: [{{PERSONAS}}]
---

> **Note**: As of Claude Code v2.1.3, commands and skills have been unified.
> This command template is maintained for backward compatibility.
> For new components, consider using the skill template (`skills/{name}/SKILL.md`) instead.
> Both `commands/{name}.md` and `skills/{name}/SKILL.md` create the same `/name` slash command.

# /{{NAME}} - {{TITLE}}

## Triggers
- {{TRIGGER_1}}
- {{TRIGGER_2}}
- {{TRIGGER_3}}
- {{TRIGGER_4}}

## Usage
```
/{{NAME}} [target] [options]

Options:
  --{{OPTION_1}}  {{OPTION_1_DESC}}
  --{{OPTION_2}}  {{OPTION_2_DESC}}
```

## Behavioral Flow

### Phase 1: Discovery
{{DISCOVERY_DESCRIPTION}}

**Steps:**
1. **Scan**: {{SCAN_STEP}}
2. **Analyze**: {{ANALYZE_STEP}}
3. **Classify**: {{CLASSIFY_STEP}}

### Phase 2: Execution
{{EXECUTION_DESCRIPTION}}

**Steps:**
1. **Process**: {{PROCESS_STEP}}
2. **Evaluate**: {{EVALUATE_STEP}}
3. **Generate**: {{GENERATE_STEP}}

### Phase 3: Output
{{OUTPUT_DESCRIPTION}}

**Steps:**
1. **Format**: {{FORMAT_STEP}}
2. **Present**: {{PRESENT_STEP}}

## Tool Coordination
- **Glob**: {{GLOB_USAGE}}
- **Read**: {{READ_USAGE}}
- **Grep**: {{GREP_USAGE}}
- **Write**: {{WRITE_USAGE}}
- **Bash**: {{BASH_USAGE}}

## Examples

### Basic Usage
```
/{{NAME}}
# {{BASIC_EXAMPLE_DESC}}
```

### With Options
```
/{{NAME}} {{EXAMPLE_TARGET}} --{{OPTION_1}} {{OPTION_1_VALUE}}
# {{OPTIONS_EXAMPLE_DESC}}
```

### Advanced Usage
```
/{{NAME}} {{ADVANCED_TARGET}} --{{OPTION_1}} {{OPTION_1_VALUE}} --{{OPTION_2}} {{OPTION_2_VALUE}}
# {{ADVANCED_EXAMPLE_DESC}}
```

## Boundaries

**Will:**
- {{WILL_1}}
- {{WILL_2}}
- {{WILL_3}}
- {{WILL_4}}
- {{WILL_5}}

**Will Not:**
- {{WILL_NOT_1}}
- {{WILL_NOT_2}}
- {{WILL_NOT_3}}
