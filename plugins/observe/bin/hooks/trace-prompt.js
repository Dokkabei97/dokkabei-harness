// UserPromptSubmit: 사용자 프롬프트 원문을 skill-trace.jsonl 에 prompt 레코드로 append.
// stdout 에 아무것도 출력하지 않는다 — UserPromptSubmit hook 의 stdout 은 Claude 컨텍스트로
// 주입되므로 오염 0 을 보장해야 한다. 어떤 경우에도 exit 0 (프롬프트 제출을 막지 않는다).
const { readEvent } = require('./_lib/hook-stdin');
const { enabled, logPath, append } = require('./_lib/trace');

(async () => {
  try {
    if (!enabled()) return;
    const { json } = await readEvent();
    append(logPath(json.cwd), {
      ts: new Date().toISOString(),
      session_id: json.session_id || null,
      type: 'prompt',
      // 필드명 호환 방어 — 버전에 따라 prompt / user_prompt 둘 중 하나로 올 수 있다.
      text: json.prompt || json.user_prompt || '',
    });
  } catch (_) { /* best-effort */ }
})();
