// PreToolUse: warn when long-running commands run outside tmux.
// 명령 패턴 필터는 스크립트 내부 (hooks.json matcher 는 tool 명 regex 만 유효).

const { readEvent, passthrough } = require('./_lib/hook-stdin');

const LONG_RUNNING = /(npm (install|test)|pnpm (install|test)|yarn (install|test)?|bun (install|test)|cargo build|make|docker|pytest|vitest|playwright|gradlew|pip install|uv (install|sync|pip|run)|tox)/;

(async () => {
  const { raw, json } = await readEvent();
  const cmd = json.tool_input?.command || '';
  if (LONG_RUNNING.test(cmd) && !process.env.TMUX) {
    console.error('[Hook] Consider running in tmux for session persistence');
    console.error('[Hook] tmux new -s dev  |  tmux attach -t dev');
  }
  passthrough(raw);
})();
