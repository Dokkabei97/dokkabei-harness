// PreToolUse: reminder before git push.
// 명령 패턴 필터는 스크립트 내부 (hooks.json matcher 는 tool 명 regex 만 유효).

const { readEvent, passthrough } = require('./_lib/hook-stdin');

(async () => {
  const { raw, json } = await readEvent();
  const cmd = json.tool_input?.command || '';
  if (/git push/.test(cmd)) {
    console.error('[Hook] Review changes before push...');
    console.error('[Hook] Continuing with push (remove this hook to add interactive review)');
  }
  passthrough(raw);
})();
