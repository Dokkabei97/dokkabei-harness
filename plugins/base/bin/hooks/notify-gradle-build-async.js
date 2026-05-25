// PostToolUse (async): notify after gradle build completes.

const { readEvent, passthrough } = require('./_lib/hook-stdin');

(async () => {
  const { raw } = await readEvent();
  console.error('[Hook] Gradle build completed - async analysis running in background');
  passthrough(raw);
})();
