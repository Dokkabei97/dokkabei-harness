// PostToolUse: warn if console.log appears in edited JS/TS file.

const fs = require('fs');
const { readEvent, passthrough } = require('./_lib/hook-stdin');

(async () => {
  const { raw, json } = await readEvent();
  const p = json.tool_input?.file_path;
  if (!p || !fs.existsSync(p)) return passthrough(raw);

  const lines = fs.readFileSync(p, 'utf8').split('\n');
  const matches = [];
  lines.forEach((l, idx) => {
    if (/console\.log/.test(l)) matches.push((idx + 1) + ': ' + l.trim());
  });

  if (matches.length) {
    console.error('[Hook] WARNING: console.log found in ' + p);
    matches.slice(0, 5).forEach((m) => console.error(m));
    console.error('[Hook] Remove console.log before committing');
  }
  passthrough(raw);
})();
