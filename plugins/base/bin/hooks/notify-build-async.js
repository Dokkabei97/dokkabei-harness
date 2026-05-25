// PostToolUse (async): notify after npm/pnpm/yarn build completes.

const { readEvent, passthrough } = require('./_lib/hook-stdin');

(async () => {
  const { raw } = await readEvent();
  console.error('[Hook] Build completed - async analysis running in background');
  passthrough(raw);
})();
