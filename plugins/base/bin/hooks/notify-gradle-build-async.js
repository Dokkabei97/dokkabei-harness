// PostToolUse (async): notify after gradle build completes.

const { readEvent, passthrough } = require('./_lib/hook-stdin');

(async () => {
  const { raw, json } = await readEvent();
  const cmd = json.tool_input?.command || '';
  if (!/gradlew.*build/.test(cmd)) return passthrough(raw);
  console.error('[Hook] Gradle build completed - async analysis running in background');
  passthrough(raw);
})();
