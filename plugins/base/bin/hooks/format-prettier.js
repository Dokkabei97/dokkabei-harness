// PostToolUse: auto-format edited JS/TS files with Prettier.

const { execFileSync } = require('child_process');
const fs = require('fs');
const { readEvent, passthrough } = require('./_lib/hook-stdin');

(async () => {
  const { raw, json } = await readEvent();
  const p = json.tool_input?.file_path;
  if (p && fs.existsSync(p)) {
    try {
      execFileSync('npx', ['prettier', '--write', p], { stdio: ['pipe', 'pipe', 'pipe'] });
    } catch (_) {}
  }
  passthrough(raw);
})();
