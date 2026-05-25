// PostToolUse: log GitHub PR / GitLab MR URL with review command hints.

const { readEvent, passthrough } = require('./_lib/hook-stdin');

const GH_PR_URL = /https:\/\/github\.com\/[^/]+\/[^/]+\/pull\/\d+/;
const GLAB_MR_URL = /https?:\/\/labs\.cowave\.kr\/[^\s]+\/-\/merge_requests\/\d+/;

(async () => {
  const { raw, json } = await readEvent();
  const cmd = json.tool_input?.command || '';
  const out = json.tool_output?.output || '';

  if (/gh pr create/.test(cmd)) {
    const m = out.match(GH_PR_URL);
    if (m) {
      const repo = m[0].replace(/https:\/\/github\.com\/([^/]+\/[^/]+)\/pull\/\d+/, '$1');
      const pr = m[0].replace(/.*\/pull\/(\d+)/, '$1');
      console.error('[Hook] PR created: ' + m[0]);
      console.error('[Hook] To review: gh pr review ' + pr + ' --repo ' + repo);
    }
  }

  if (/glab mr create/.test(cmd)) {
    const m = out.match(GLAB_MR_URL);
    if (m) {
      const mr = m[0].replace(/.*\/merge_requests\/(\d+)/, '$1');
      console.error('[Hook] MR created: ' + m[0]);
      console.error('[Hook] To view: glab mr view ' + mr);
      console.error('[Hook] To approve: glab mr approve ' + mr);
    }
  }

  passthrough(raw);
})();
