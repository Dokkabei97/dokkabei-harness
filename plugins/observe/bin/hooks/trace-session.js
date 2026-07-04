// SessionStart/SessionEnd: 세션 경계를 skill-trace.jsonl 에 append — 하나의 스크립트가
// hook_event_name 으로 두 이벤트를 판별한다 (레코드 type: session_start | session_end).
// session_start 의 plugin_root 는 이 훅이 실행된 "설치 루트"의 근거로,
// 리포트가 미사용 자산의 분모(인벤토리)를 트레이스와 같은 설치본에서 열거하게 해준다
// (repo 디렉터리명과 설치 네임스페이스의 드리프트로 인한 join 오류 방지).
// SessionStart hook 의 stdout 은 컨텍스트로 주입되므로 무출력 필수. 항상 exit 0.
const { readEvent } = require('./_lib/hook-stdin');
const { enabled, logPath, append } = require('./_lib/trace');

(async () => {
  try {
    if (!enabled()) return;
    const { json } = await readEvent();
    const event = json.hook_event_name;
    if (event !== 'SessionStart' && event !== 'SessionEnd') return; // 오설정 이중 가드

    const base = {
      ts: new Date().toISOString(),
      session_id: json.session_id || null,
    };
    if (event === 'SessionStart') {
      append(logPath(json.cwd), {
        ...base,
        type: 'session_start',
        source: json.source || null, // startup | resume | clear | compact 등
        plugin_root: process.env.CLAUDE_PLUGIN_ROOT || null,
      });
    } else {
      append(logPath(json.cwd), {
        ...base,
        type: 'session_end',
        reason: json.reason || null, // clear | logout | prompt_input_exit | other 등
      });
    }
  } catch (_) { /* best-effort */ }
})();
