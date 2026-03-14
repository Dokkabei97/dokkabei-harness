# Hook Validation Rules (HK-*)

## HK-001: Valid JSON Structure
- **Severity**: Critical
- **Check**: settings.json hooks section parses without errors
- **Auto-fixable**: No (malformed JSON needs manual review)

## HK-002: Matcher Expression Present
- **Severity**: Critical
- **Check**: Each hook entry has non-empty matcher string
- **Auto-fixable**: No

## HK-003: Hook Type Valid
- **Severity**: High
- **Check**: `hooks[].type` is "command"
- **Auto-fixable**: Yes (set to "command" if missing)

## HK-004: Description Present
- **Severity**: Medium
- **Check**: Non-empty description string
- **Auto-fixable**: Yes (generate from matcher expression)

## HK-005: No Duplicate Matchers
- **Severity**: High
- **Check**: All matcher expressions are unique across hook entries
- **Auto-fixable**: No (need to determine which to keep)

## HK-006: Script Safety
- **Severity**: High
- **Check**: Hook command does not contain dangerous patterns
- **Auto-fixable**: No (requires security review)
- **Blocked patterns**: `rm -rf`, `eval(`, `exec(`, `child_process`, `fs.unlinkSync("/")`
