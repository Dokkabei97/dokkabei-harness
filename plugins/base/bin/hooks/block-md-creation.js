// PreToolUse: block creation of arbitrary .md / .txt files outside the allowlist.

const { readEvent, passthrough } = require('./_lib/hook-stdin');

const ALLOWED = /(README|CLAUDE|AGENTS|CONTRIBUTING)\.md$/;
const TARGET_EXT = /\.(md|txt)$/;
// mvp 하네스 작업 메모리(.planning/)와 startup 산출물(.planning/business/)은 허용 —
// prd.md·design-spec.md·progress.md·lean-canvas.md 등이 차단되면 파이프라인이 멈춘다.
const PLANNING = /(^|\/)\.planning\//;

(async () => {
  const { raw, json } = await readEvent();
  const path = json.tool_input?.file_path || '';
  if (TARGET_EXT.test(path) && !ALLOWED.test(path) && !PLANNING.test(path)) {
    console.error('[Hook] BLOCKED: Unnecessary documentation file creation');
    console.error('[Hook] File: ' + path);
    console.error('[Hook] Use README.md for documentation instead');
    process.exit(1);
  }
  passthrough(raw);
})();
