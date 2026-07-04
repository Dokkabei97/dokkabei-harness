// PostToolUse: warn if console.log appears in edited JS/TS file.

const fs = require('fs');
const { readEvent, passthrough } = require('./_lib/hook-stdin');

(async () => {
  const { raw, json } = await readEvent();
  const p = json.tool_input?.file_path;
  if (!p || !/\.(ts|tsx|js|jsx)$/.test(p) || !fs.existsSync(p)) return passthrough(raw);

  // existsSync 통과 후에도 읽기는 실패할 수 있다(EACCES/TOCTOU) — 조용히 passthrough
  let content;
  try { content = fs.readFileSync(p, 'utf8'); } catch (_) { return passthrough(raw); }
  const lines = content.split('\n');
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
