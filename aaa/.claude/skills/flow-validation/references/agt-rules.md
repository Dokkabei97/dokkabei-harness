# Agent Validation Rules (AGT-*)

## AGT-001: Frontmatter Present and Valid YAML
- **Severity**: Critical
- **Check**: File starts with `---` and contains valid YAML block
- **Auto-fixable**: No
- **Pattern**: `^---\n[\s\S]+?\n---`

## AGT-002: Required Frontmatter Fields
- **Severity**: Critical
- **Check**: YAML contains: name, description, tools
- **Auto-fixable**: Yes (add missing tools with default `["Read", "Grep", "Glob"]`)

## AGT-003: Valid Tool Names
- **Severity**: High
- **Check**: Each tool in array is a recognized tool name
- **Auto-fixable**: Yes (remove invalid entries)
- **Valid tools**: Read, Grep, Glob, Bash, Write, Edit, WebFetch, WebSearch

## AGT-004: Role Description
- **Severity**: High
- **Check**: `## Your Role` or `## Role` section with 3+ bullet responsibilities
- **Auto-fixable**: No

## AGT-005: Workflow Section
- **Severity**: Critical
- **Check**: Section matching `Workflow` or `Analysis` with numbered steps
- **Auto-fixable**: No (requires domain expertise)

## AGT-006: Decision Matrices
- **Severity**: Medium
- **Check**: At least one markdown table or Grep/Glob pattern block in workflow
- **Auto-fixable**: No

## AGT-007: Output Format
- **Severity**: Medium
- **Check**: `## Output` section with report template
- **Auto-fixable**: No

## AGT-008: Boundaries
- **Severity**: High
- **Check**: `## Boundaries` with Will/Will Not lists
- **Auto-fixable**: No

## AGT-009: Description Trigger Quality
- **Severity**: Critical
- **Check**: Agent description must contain "Use when" or "Use PROACTIVELY when" phrase, clearly identify the agent's role, and specify technology scope
- **Auto-fixable**: No (requires understanding of agent purpose)
- **Good example**: "Architecture review specialist that analyzes codebase structure. Use when reviewing projects for architecture conformance. Supports Kotlin (Spring Boot), Python (FastAPI/Django)."
- **Bad example**: "A helpful agent that does code review."

## AGT-010: Tools Minimality
- **Severity**: Low
- **Check**: All tools declared in frontmatter `tools` array are actually referenced or used in the agent body
- **Auto-fixable**: Yes (remove unreferenced tools from array)
- **Rationale**: Declaring unused tools inflates the agent's capabilities description without purpose

## AGT-011: System Prompt Structure
- **Severity**: High
- **Check**: Agent body must contain these structural elements:
  1. Role definition paragraph starting with "You are a/an..."
  2. `## Your Role` or `## Core Responsibilities` with bulleted list
  3. Numbered workflow steps in `## Analysis Workflow` or `## Workflow`
  4. At least one BAD/GOOD code example pattern
  5. `## Output Format` with expected output structure
- **Auto-fixable**: No (requires domain expertise)

## AGT-012: Token Budget Warning
- **Severity**: Medium
- **Check**: Agent body should be flagged if exceeding 50,000 characters as it may cause context window issues
- **Auto-fixable**: No (content reduction requires judgment)
- **Thresholds**: OK < 30,000 chars, Warning < 50,000 chars, Critical > 50,000 chars
