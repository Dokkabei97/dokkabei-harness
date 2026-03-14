# Quality Validation Rules (QUA-*)

## QUA-001: Description Specificity
- **Severity**: Medium
- **Check**: Description is specific (not generic like "does things" or "useful tool")
- **Auto-fixable**: No
- **Min length**: 10 characters
- **Max length**: 300 characters
- **Blocked words**: "stuff", "things", "misc", "various", "etc"

## QUA-002: No Placeholder Text
- **Severity**: High
- **Check**: No unfilled placeholders remain in component files
- **Auto-fixable**: No (placeholders need real content)
- **Patterns**: `{{.+}}`, `TODO`, `FIXME`, `TBD`, `XXX`, `PLACEHOLDER`

## QUA-003: Trigger Concreteness
- **Severity**: Medium
- **Check**: Command triggers use concrete action phrases, not vague descriptions
- **Auto-fixable**: No
- **Good**: "Security vulnerability scanning of authentication modules"
- **Bad**: "When you need to do security stuff"

## QUA-004: Example Completeness
- **Severity**: Medium
- **Check**: Each example includes a comment explaining expected behavior
- **Auto-fixable**: No
- **Pattern**: Code block should contain `#` comment lines

## QUA-005: Behavioral Flow Depth
- **Severity**: Medium
- **Check**: Each phase in behavioral flow has at least 2 sub-steps
- **Auto-fixable**: No
- **Pattern**: Phase heading followed by numbered or bulleted sub-items

## QUA-006: Boundary Balance
- **Severity**: Low
- **Check**: Will and Will Not lists have reasonable count (3-8 items each)
- **Auto-fixable**: No
- **Thresholds**: Min 3 Will items, Min 2 Will Not items, Max 10 each
