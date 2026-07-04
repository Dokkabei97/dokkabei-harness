// PreToolUse: block creation of arbitrary .md / .txt files outside the allowlist.

const { readEvent, passthrough } = require('./_lib/hook-stdin');

// HANDOFF.md 는 workflow:/handoff, CHANGELOG.md 는 workflow:/release-notes 의 정식 산출물.
const ALLOWED = /(README|CLAUDE|AGENTS|CONTRIBUTING|HANDOFF|CHANGELOG)\.md$/;
const TARGET_EXT = /\.(md|txt)$/;
// mvp 하네스 작업 메모리(.planning/)와 startup 산출물(.planning/business/)은 허용 —
// prd.md·design-spec.md·progress.md·lean-canvas.md 등이 차단되면 파이프라인이 멈춘다.
const PLANNING = /(^|\/)\.planning\//;
// tasks/ 하위는 워크플로우 규약 산출물(todo.md, lessons.md — /retro·태스크 관리) 이므로 허용.
const TASKS = /(^|\/)tasks\//;

(async () => {
  const { raw, json } = await readEvent();
  const path = json.tool_input?.file_path || '';
  if (TARGET_EXT.test(path) && !ALLOWED.test(path) && !PLANNING.test(path) && !TASKS.test(path)) {
    console.error('[Hook] BLOCKED: Unnecessary documentation file creation');
    console.error('[Hook] File: ' + path);
    console.error('[Hook] Use README.md for documentation instead');
    process.exit(2); // PreToolUse 차단은 exit 2 — exit 1 은 비차단 경고라 통과된다
  }
  passthrough(raw);
})();
