// Hook stdin helper — reads JSON event payload and provides passthrough.

exports.readEvent = () => new Promise((resolve) => {
  let buf = '';
  process.stdin.on('data', (c) => { buf += c; });
  process.stdin.on('end', () => {
    let json = {};
    try { json = JSON.parse(buf); } catch (_) {}
    resolve({ raw: buf, json });
  });
});

// stdin 에코는 Claude Code payload 일 때만 — 다른 런타임은 stdout 을 출력 스키마로 엄격 파싱한다.
// Codex(payload 에 turn_id): 에코된 입력 JSON 을 "invalid pre/post-tool-use JSON output" 으로 보고
//   매 Bash·apply_patch 호출마다 hook Failed 를 띄운다(실측 codex-cli 0.165). 무출력 exit 0 은 유효.
// Antigravity(camelCase payload, hook_event_name 없음): 출력 스키마가 {decision} 이라 에코 금지.
const isClaudeCodePayload = (raw) => {
  try {
    const j = JSON.parse(raw);
    return !!j && typeof j.hook_event_name === 'string' && j.turn_id === undefined;
  } catch (_) {
    return false;
  }
};

exports.passthrough = (raw) => { if (isClaudeCodePayload(raw)) console.log(raw); };
