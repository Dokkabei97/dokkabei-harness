// PostToolUse: run tsc --noEmit after .ts/.tsx edits, report errors related to the edited file.

const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');
const { readEvent, passthrough } = require('./_lib/hook-stdin');

const findTsconfigDir = (start) => {
  let dir = start;
  while (dir !== path.dirname(dir)) {
    if (fs.existsSync(path.join(dir, 'tsconfig.json'))) return dir;
    dir = path.dirname(dir);
  }
  return null;
};

(async () => {
  const { raw, json } = await readEvent();
  const p = json.tool_input?.file_path;
  if (!p || !fs.existsSync(p)) return passthrough(raw);

  const dir = findTsconfigDir(path.dirname(p));
  if (!dir) return passthrough(raw);

  try {
    const r = execSync('npx tsc --noEmit --pretty false 2>&1', {
      cwd: dir,
      encoding: 'utf8',
      stdio: ['pipe', 'pipe', 'pipe'],
    });
    const lines = r.split('\n').filter((l) => l.includes(p)).slice(0, 10);
    if (lines.length) console.error(lines.join('\n'));
  } catch (e) {
    const lines = (e.stdout || '').split('\n').filter((l) => l.includes(p)).slice(0, 10);
    if (lines.length) console.error(lines.join('\n'));
  }
  passthrough(raw);
})();
