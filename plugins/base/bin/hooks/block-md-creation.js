// PreToolUse: block creation of arbitrary .md / .txt files outside the allowlist.

const { readEvent, passthrough } = require('./_lib/hook-stdin');

const ALLOWED = /(README|CLAUDE|AGENTS|CONTRIBUTING)\.md$/;
const TARGET_EXT = /\.(md|txt)$/;

(async () => {
  const { raw, json } = await readEvent();
  const path = json.tool_input?.file_path || '';
  if (TARGET_EXT.test(path) && !ALLOWED.test(path)) {
    console.error('[Hook] BLOCKED: Unnecessary documentation file creation');
    console.error('[Hook] File: ' + path);
    console.error('[Hook] Use README.md for documentation instead');
    process.exit(1);
  }
  passthrough(raw);
})();
