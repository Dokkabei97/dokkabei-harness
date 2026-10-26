// Stop: 턴 다이제스트(turn_summary)·커밋 이벤트 기록 — 기록 전용. 증분 커서(.tracer/cursors/claude-code/<session>.json)
// 이후만 읽어 "다음 턴 경계가 이미 기록된" 턴을 확정한다(현재 턴은 다음 Stop·SessionEnd 가 확정 — transcript.js 참고).
// 절대 규칙: stdout 무출력·decision/additionalContext 미출력·항상 exit 0 — Stop 을 막으면 연속 8블록 상한을 소모하고
// harness generic 루프와 간섭한다. stop_hook_active=true(다른 Stop 훅의 차단으로 재진입)면 커서도 건드리지 않고 즉시 종료 —
// 그 턴은 루프가 끝난 뒤 다음 비재진입 Stop 이나 SessionEnd 가 한 번에 처리한다(중복 0).
// Codex 도 같은 hooks.json 으로 부른다(Stop payload 에 stop_hook_active·turn_id — 바이너리 스키마) — runtimeOf 가 codex 면
// rollout 어댑터(adapters/codex/rollout.js)로 같은 digest.run 을 돈다. Codex Stop 도 exit 0 시 평문 stdout 금지(JSON 필수) — 무출력.
const { readEvent } = require('../../_lib/hook-stdin');
const { enabled, runtimeOf, CODEX } = require('../../_lib/writer');
const { repoRoot } = require('../../_lib/paths');

(async () => {
  try {
    if (!enabled()) return;
    const { json } = await readEvent();
    if (!json || typeof json.session_id !== 'string' || !json.session_id || !json.transcript_path) return;
    if (json.stop_hook_active === true) return;
    if (json.hook_event_name && json.hook_event_name !== 'Stop') return; // 오설정 이중 가드
    const adapter = runtimeOf(json) === CODEX ? '../codex/rollout' : './transcript';
    require(adapter).digestSession(repoRoot(json.cwd), json.session_id, json.transcript_path, false);
  } catch (_) { /* best-effort */ }
})();
