// PostToolUse: validate Python syntax with py_compile after .py edits.

const { execFileSync } = require('child_process');
const fs = require('fs');
const { readEvent, passthrough } = require('./_lib/hook-stdin');

(async () => {
  const { raw, json } = await readEvent();
  const p = json.tool_input?.file_path;
  if (!p || !/\.py$/.test(p) || !fs.existsSync(p)) return passthrough(raw);

  try {
    // 인자 배열로 전달 — 셸을 거치지 않아 경로 내 $()/백틱 명령 치환(RCE) 원천 차단(format-prettier 패턴)
    execFileSync('python3', ['-m', 'py_compile', p], {
      encoding: 'utf8',
      stdio: ['pipe', 'pipe', 'pipe'],
    });
  } catch (e) {
    const out = (e.stdout || '') + (e.stderr || '');
    const lines = out.split('\n').filter((l) => l.trim()).slice(0, 10);
    if (lines.length) {
      console.error('[Hook] Python syntax error in ' + p);
      console.error(lines.join('\n'));
    }
  }
  passthrough(raw);
})();
