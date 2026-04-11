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
- **Check**: `hooks[].type` is one of: "command", "http", "prompt", "agent"
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

## HK-007: Event Name Validity
- **Severity**: Critical
- **Check**: Hook event name is one of 27 valid events
- **Auto-fixable**: No
- **Valid events**: SessionStart, SessionEnd, Setup, UserPromptSubmit, InstructionsLoaded, PreToolUse, PostToolUse, PostToolUseFailure, PermissionRequest, PermissionDenied, SubagentStart, SubagentStop, TaskCreated, TaskCompleted, TeammateIdle, Elicitation, ElicitationResult, FileChanged, CwdChanged, ConfigChange, PreCompact, PostCompact, WorktreeCreate, WorktreeRemove, Notification, Stop, StopFailure

## HK-008: Handler Type Field Completeness
- **Severity**: High
- **Check**: Each handler type has required fields:
  - command: `command` (required), `timeout` (optional)
  - http: `url` (required), `headers` (optional)
  - prompt: `prompt` (required)
  - agent: `prompt` (required), `tools` (optional)
- **Auto-fixable**: No

## HK-009: HTTP Handler URL Validity
- **Severity**: High
- **Check**: If handler type is "http", url is a valid URL
- **Auto-fixable**: No

## HK-010: Blocking Event Consistency
- **Severity**: Medium
- **Check**: Non-blocking events (SessionStart, PostToolUse, PostToolUseFailure, Notification, SubagentStart, WorktreeRemove, PreCompact, PostCompact, SessionEnd, StopFailure) should not expect exit code-based blocking behavior
- **Auto-fixable**: No

## HK-011: Handler Type Availability by Event
- **Severity**: Medium
- **Check**: Some events only support "command" handler type (SessionStart, Notification, SubagentStart, InstructionsLoaded, ConfigChange, WorktreeCreate, WorktreeRemove, PreCompact, PostCompact, SessionEnd, Setup, CwdChanged, FileChanged)
- **Auto-fixable**: No

## HK-012: Async Hook Configuration
- **Severity**: Low
- **Check**: If `async: true` is set, it's only on command type handlers
- **Auto-fixable**: No

## HK-013: Conditional If Field Validity
- **Severity**: Medium
- **Check**: If `if` field is present on a hook entry, it must use valid permission rule syntax
- **Auto-fixable**: No
- **Note**: Added in Claude Code v2.1.85. Uses same syntax as permission rules to conditionally execute hooks
