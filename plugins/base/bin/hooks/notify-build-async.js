// PostToolUse (async): notify after npm/pnpm/yarn build completes.

const { readEvent, passthrough } = require('./_lib/hook-stdin');

(async () => {
  const { raw, json } = await readEvent();
  const cmd = json.tool_input?.command || '';
  if (!/(npm run build|pnpm build|yarn build)/.test(cmd)) return passthrough(raw);
  console.error('[Hook] Build completed - async analysis running in background');
  passthrough(raw);
})();
