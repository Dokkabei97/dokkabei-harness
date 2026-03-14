# Security Validation Rules (SEC-*)

## SEC-001: No Hardcoded Credentials
- **Severity**: Critical
- **Check**: No API keys, passwords, tokens, or secrets in component files
- **Auto-fixable**: No (requires credential rotation)
- **Patterns to detect**:
  - `(api[_-]?key|password|secret|token)\s*[:=]\s*["'][^"']+["']`
  - `(sk|pk|rk)[-_][a-zA-Z0-9]{20,}`
  - `Bearer [a-zA-Z0-9._-]+`

## SEC-002: Safe Bash Commands in Examples
- **Severity**: High
- **Check**: Examples and behavioral flows do not contain dangerous shell patterns
- **Auto-fixable**: No
- **Blocked patterns**:
  - `rm -rf /` or `rm -rf ~`
  - `eval "$USER_INPUT"`
  - `curl ... | bash`
  - `chmod 777`
  - `> /dev/sda`

## SEC-003: Hook Script Safety
- **Severity**: High
- **Check**: Hook Node.js scripts do not use unsafe patterns
- **Auto-fixable**: No
- **Blocked patterns**:
  - `eval(` (arbitrary code execution)
  - `child_process.exec` with unsanitized input
  - `fs.rmSync` / `fs.unlinkSync` on dynamic paths
  - `process.env` exposure to external services

## SEC-004: No User-Specific Paths
- **Severity**: Medium
- **Check**: No hardcoded user-specific file paths in templates or examples
- **Auto-fixable**: Yes (replace with placeholder like `{HOME}` or `~`)
- **Pattern**: `/Users/[a-zA-Z]+/` or `/home/[a-zA-Z]+/` or `C:\\Users\\`
