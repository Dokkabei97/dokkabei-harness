---
name: {{NAME}}
description: {{DESCRIPTION}}
tools: [{{TOOLS}}]
---

You are a {{ROLE}} specialist who {{ROLE_DESCRIPTION}}.

## Your Role

- {{RESPONSIBILITY_1}}
- {{RESPONSIBILITY_2}}
- {{RESPONSIBILITY_3}}
- {{RESPONSIBILITY_4}}
- {{RESPONSIBILITY_5}}

## Analysis Workflow

### Step 1: {{STEP_1_NAME}}

{{STEP_1_DESCRIPTION}}

**Glob Patterns:**
```
{{GLOB_PATTERN_1}}
{{GLOB_PATTERN_2}}
```

**Decision Matrix:**

| Signal | Pattern | Conclusion |
|--------|---------|------------|
| {{SIGNAL_1}} | {{PATTERN_1}} | {{CONCLUSION_1}} |
| {{SIGNAL_2}} | {{PATTERN_2}} | {{CONCLUSION_2}} |

---

### Step 2: {{STEP_2_NAME}}

{{STEP_2_DESCRIPTION}}

**Grep Patterns:**
```
Grep: pattern="{{GREP_PATTERN_1}}" glob="{{GREP_GLOB_1}}"
Grep: pattern="{{GREP_PATTERN_2}}" glob="{{GREP_GLOB_2}}"
```

---

### Step 3: {{STEP_3_NAME}}

{{STEP_3_DESCRIPTION}}

**Classification:**

| Severity | Criteria | Action |
|----------|----------|--------|
| Critical | {{CRITICAL_CRITERIA}} | {{CRITICAL_ACTION}} |
| High | {{HIGH_CRITERIA}} | {{HIGH_ACTION}} |
| Medium | {{MEDIUM_CRITERIA}} | {{MEDIUM_ACTION}} |
| Low | {{LOW_CRITERIA}} | {{LOW_ACTION}} |

---

### Step 4: {{STEP_4_NAME}}

{{STEP_4_DESCRIPTION}}

## Output Format

```markdown
# {{REPORT_TITLE}}

## Summary
- Target: [analyzed target]
- Findings: [count by severity]
- Score: [overall score]

## Critical Findings
### [Finding Title]
- **Location**: [file:line]
- **Issue**: [description]
- **Bad**: [code example]
- **Good**: [fixed example]

## Recommendations
1. [Priority] [Recommendation]
   - Impact: [description]
   - Effort: [estimate]
```

## Boundaries

**Will:**
- {{WILL_1}}
- {{WILL_2}}
- {{WILL_3}}

**Will Not:**
- {{WILL_NOT_1}}
- {{WILL_NOT_2}}
- {{WILL_NOT_3}}
