// UserPromptSubmit: 사용자 프롬프트 원문을 skill-trace.jsonl 에 prompt 레코드로 append.
// stdout 에 아무것도 출력하지 않는다 — UserPromptSubmit hook 의 stdout 은 Claude 컨텍스트로
// 주입되므로 오염 0 을 보장해야 한다. 어떤 경우에도 exit 0 (프롬프트 제출을 막지 않는다).
const { readEvent } = require('./_lib/hook-stdin');
const { enabled, logPath, append } = require('./_lib/trace');

(async () => {
  try {
    if (!enabled()) return;
    const { json } = await readEvent();
    // 필드명 호환 방어 — 버전에 따라 prompt / user_prompt 둘 중 하나로 올 수 있다.
    const text = json.prompt || json.user_prompt || '';
    append(logPath(json.cwd), {
      ts: new Date().toISOString(),
      session_id: json.session_id || null,
      type: 'prompt',
      text,
      // ── additive 확장 (2026-07) ──
      prompt_id: json.prompt_id || null, // skill/agent 레코드와의 턴 단위 join 키
      // 슬래시 직접 호출 여부 — 미발화 후보 추출 시 분모에서 제외할 근사 신호.
      // 커맨드 토큰 형태(공백/끝 종결)를 요구해 "/Users/…" 같은 절대경로 선두 프롬프트의
      // 오탐을 배제한다 (커맨드 래퍼는 transcript 에만 있고 payload 에는 원문이 오므로 양쪽 검사).
      is_command: /^\s*\/[A-Za-z0-9_:-]+(\s|$)/.test(text) || /<command-name>/.test(text),
    });
  } catch (_) { /* best-effort */ }
})();
