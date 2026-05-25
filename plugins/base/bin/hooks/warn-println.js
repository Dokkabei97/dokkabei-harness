// PostToolUse: warn if println() appears in edited Kotlin file (ignoring commented lines).

const fs = require('fs');
const { readEvent, passthrough } = require('./_lib/hook-stdin');

(async () => {
  const { raw, json } = await readEvent();
  const p = json.tool_input?.file_path;
  if (!p || !fs.existsSync(p)) return passthrough(raw);

  const lines = fs.readFileSync(p, 'utf8').split('\n');
  const matches = [];
  lines.forEach((l, idx) => {
    if (/println\s*\(/.test(l) && !/\/\//.test(l.split('println')[0])) {
      matches.push((idx + 1) + ': ' + l.trim());
    }
  });

  if (matches.length) {
    console.error('[Hook] WARNING: println() found in ' + p);
    matches.slice(0, 5).forEach((m) => console.error(m));
    console.error('[Hook] Consider using a logger instead of println before committing');
  }
  passthrough(raw);
})();
