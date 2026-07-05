// PreToolUse: block creation of arbitrary .md / .txt files outside the allowlist.

const { readEvent, passthrough } = require("./_lib/hook-stdin");

// HANDOFF.md 는 workflow:/handoff, CHANGELOG.md 는 workflow:/release-notes 의 정식 산출물.
const ALLOWED = /(README|CLAUDE|AGENTS|CONTRIBUTING|HANDOFF|CHANGELOG)\.md$/;
const TARGET_EXT = /\.(md|txt)$/;
// mvp 하네스 작업 메모리(.planning/)와 startup 산출물(.planning/business/)은 허용 —
// prd.md·design-spec.md·progress.md·lean-canvas.md 등이 차단되면 파이프라인이 멈춘다.
const PLANNING = /(^|\/)\.planning\//;
// tasks/ 하위는 워크플로우 규약 산출물(todo.md, lessons.md — /retro·태스크 관리) 이므로 허용.
const TASKS = /(^|\/)tasks\//;
// Claude Code 자동 메모리(~/.claude/projects/<슬러그>/memory/)는 하네스 관리 영역 —
// 시스템 프롬프트가 Write 를 지시하는 per-fact .md 저장소라 차단하면 메모리 기능이 죽는다.
const MEMORY = /\/\.claude\/projects\/[^/]+\/memory\//;
// 세션 스크래치패드(/tmp/claude-<uid>/…)도 하네스 관리 영역 — Artifact 렌더링용 .md 가 여기 쓰인다.
const SCRATCHPAD = /^(?:\/private)?\/tmp\/claude-[^/]+\//;

(async () => {
  const { raw, json } = await readEvent();
  const path = json.tool_input?.file_path || "";
  if (
    TARGET_EXT.test(path) &&
    !ALLOWED.test(path) &&
    !PLANNING.test(path) &&
    !TASKS.test(path) &&
    !MEMORY.test(path) &&
    !SCRATCHPAD.test(path)
  ) {
    console.error("[Hook] BLOCKED: Unnecessary documentation file creation");
    console.error("[Hook] File: " + path);
    console.error("[Hook] Use README.md for documentation instead");
    process.exit(2); // PreToolUse 차단은 exit 2 — exit 1 은 비차단 경고라 통과된다
  }
  passthrough(raw);
})();
