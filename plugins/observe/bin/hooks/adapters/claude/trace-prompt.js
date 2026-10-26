// UserPromptSubmit: 사용자 프롬프트를 prompt 레코드로 기록 — writer 가 원문은 레드액션해 .tracer/raw/ 로,
// 파생 특징(길이·커맨드 여부·커맨드명)만 .tracer/events/ 로 나눠 쓴다 (events 에 원문 0).
// stdout 에 아무것도 출력하지 않는다 — UserPromptSubmit hook 의 stdout 은 Claude 컨텍스트로
// 주입되므로 오염 0 을 보장해야 한다. 어떤 경우에도 exit 0 (프롬프트 제출을 막지 않는다).
// Codex 도 같은 hooks.json 으로 이 훅을 부른다(stdout 은 developer 컨텍스트로 주입 — 같은 무출력 계약) — runtimeOf 가
// 런타임을 가르고, 턴 키는 Claude prompt_id / Codex turn_id(UserPromptSubmit 필수 필드, 바이너리 스키마 실측).
const { readEvent } = require('../../_lib/hook-stdin');
const { enabled, emit, runtimeOf } = require('../../_lib/writer');
const { repoRoot } = require('../../_lib/paths');

(async () => {
  try {
    if (!enabled()) return;
    const { json } = await readEvent();
    // 빈/깨진 stdin(json={})·비객체 payload·문자열이 아닌 session_id(파일명 키) 는 기록하지 않는다 — session_id:null 쓰레기 레코드 방지
    if (!json || typeof json.session_id !== 'string' || !json.session_id) return;
    // 필드명 호환 방어 — 버전에 따라 prompt / user_prompt 둘 중 하나로 올 수 있다.
    const text = json.prompt || json.user_prompt || '';
    const runtime = runtimeOf(json);
    emit(repoRoot(json.cwd), {
      ts: new Date().toISOString(),
      session_id: json.session_id || null,
      type: 'prompt',
      text,
      // ── additive 확장 (2026-07) ──
      prompt_id: json.prompt_id || json.turn_id || null, // skill/agent 레코드와의 턴 단위 join 키 (Codex 는 turn_id)
      // 슬래시 직접 호출 여부 — 미발화 후보 추출 시 분모에서 제외할 근사 신호.
      // 커맨드 토큰 형태(공백/끝 종결)를 요구해 "/Users/…" 같은 절대경로 선두 프롬프트의
      // 오탐을 배제한다 (커맨드 래퍼는 transcript 에만 있고 payload 에는 원문이 오므로 양쪽 검사).
      is_command: /^\s*\/[A-Za-z0-9_:-]+(\s|$)/.test(text) || /<command-name>/.test(text),
    }, runtime);
  } catch (_) { /* best-effort */ }
})();
