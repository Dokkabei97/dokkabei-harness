// PostToolUse: validate Python syntax with py_compile after .py edits.

const { execSync } = require('child_process');
const fs = require('fs');
const { readEvent, passthrough } = require('./_lib/hook-stdin');

(async () => {
  const { raw, json } = await readEvent();
  const p = json.tool_input?.file_path;
  if (!p || !fs.existsSync(p)) return passthrough(raw);

  try {
    execSync('python3 -m py_compile ' + JSON.stringify(p) + ' 2>&1', {
      encoding: 'utf8',
      stdio: ['pipe', 'pipe', 'pipe'],
    });
  } catch (e) {
    const out = (e.stdout || '') + (e.stderr || '');
    const lines = out.split('\n').filter((l) => l.trim()).slice(0, 10);
    if (lines.length) {
      console.error('[Hook] Python syntax error in ' + p);
      console.error(lines.join('\n'));
    }
  }
  passthrough(raw);
})();
