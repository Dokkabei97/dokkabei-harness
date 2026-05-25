// PostToolUse: warn if bare print() appears in edited Python file (skip comments and logger calls).

const fs = require('fs');
const { readEvent, passthrough } = require('./_lib/hook-stdin');

(async () => {
  const { raw, json } = await readEvent();
  const p = json.tool_input?.file_path;
  if (!p || !fs.existsSync(p)) return passthrough(raw);

  const lines = fs.readFileSync(p, 'utf8').split('\n');
  const matches = [];
  lines.forEach((l, idx) => {
    const stripped = l.trim();
    if (
      /^print\s*\(/.test(stripped) &&
      !/^#/.test(stripped) &&
      !/logging|logger|log\./.test(stripped)
    ) {
      matches.push((idx + 1) + ': ' + stripped);
    }
  });

  if (matches.length) {
    console.error('[Hook] WARNING: print() found in ' + p);
    matches.slice(0, 5).forEach((m) => console.error(m));
    console.error('[Hook] Consider using logging module instead of print before committing');
  }
  passthrough(raw);
})();
