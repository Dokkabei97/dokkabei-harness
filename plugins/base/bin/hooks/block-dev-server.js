// PreToolUse: block dev servers outside tmux so logs are accessible.
// 명령 패턴 필터는 스크립트 내부 (hooks.json matcher 는 tool 명 regex 만 유효).

const { readEvent, passthrough } = require('./_lib/hook-stdin');

const DEV_SERVER = /(npm run dev|pnpm( run)? dev|yarn dev|bun run dev|uvicorn|flask run|python.*manage\.py runserver|uv run.*(uvicorn|flask|manage\.py))/;

(async () => {
  const { raw, json } = await readEvent();
  const cmd = json.tool_input?.command || '';
  if (DEV_SERVER.test(cmd) && !process.env.TMUX) {
    console.error('[Hook] BLOCKED: Dev server must run in tmux for log access');
    console.error('[Hook] Use: tmux new-session -d -s dev "npm run dev"');
    console.error('[Hook] Then: tmux attach -t dev');
    process.exit(2); // PreToolUse 차단은 exit 2 — exit 1 은 비차단 경고라 통과된다
  }
  passthrough(raw);
})();
