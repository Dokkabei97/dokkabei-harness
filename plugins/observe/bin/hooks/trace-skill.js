// PreToolUse(Skill): 스킬 호출을 근거(why)·trigger와 함께 skill-trace.jsonl 에 append.
// 추적은 best-effort — 어떤 예외도 스킬 실행을 막지 않도록 항상 조용히 종료(exit 0, stdout 무출력).
// 턴 컨텍스트(why/커맨드 래퍼) 추출 로직은 _lib/turn-context.js 공유 (trace-agent 와 동일 규약).
const { readEvent } = require("./_lib/hook-stdin");
const { enabled, logPath } = require("./_lib/trace");
const {
  readTranscript,
  extractTurnContext,
  findToolUseIndex,
  appendResolvingWhy,
} = require("./_lib/turn-context");

// trigger 분류 — "user"(사용자가 직접 슬래시로 호출) | "model"(모델 자율 선택).
// user 호출을 걸러내야 "모델이 스킬을 알아서 잘 고르는가" 평가의 분모가 깨끗해진다.
// 판정 신호(정밀도 순):
//   ① 커맨드 래퍼 <command-name> 이 스킬명과 일치 — 최고 정밀도
//   ② 사용자 발화가 `/스킬명` 으로 시작 (네임스페이스 유무 양쪽 허용: /ns:name, /name)
//   ③ 그 외 전부 model — 커맨드가 다른 스킬을 연쇄 호출시킨 경우(예: /mvp-new 가
//      mvp-orchestrator 를 부름)도 model 로 둔다: 그 선택 자체는 모델의 수행이며,
//      모호 시 user 로 기울이면 자율 호출 표본이 부당하게 줄어든다.
//      (연쇄의 provenance 는 turn_command 필드가 별도로 보존한다 — trigger 의미 불변)
function classifyTrigger(skillName, ctx) {
  if (!skillName) return null;
  const full = skillName.toLowerCase(); // "harness:verify-flow"
  const tail = full.split(":").pop(); // "verify-flow"
  const matches = (tok) => {
    const t = (tok || "").replace(/^\//, "").toLowerCase();
    return t === full || t === tail || t.endsWith(":" + tail);
  };
  if (ctx.command && matches(ctx.command.name)) return "user";
  if (/^\//.test(ctx.userText) && matches(ctx.userText.split(/\s+/)[0]))
    return "user";
  return "model";
}

(async () => {
  try {
    if (!enabled()) return;
    const { json } = await readEvent();
    // matcher 의미론 변경/오설정 대비 이중 가드 — Skill 외 이벤트는 즉시 무시
    if (json.tool_name && json.tool_name !== "Skill") return;

    const skillName = (json.tool_input && json.tool_input.skill) || null;
    let args = (json.tool_input && json.tool_input.args) || "";
    if (typeof args === "string" && args.length > 1000)
      args = args.slice(0, 1000) + "…[truncated]";

    // anchor(현재 호출의 tool_use_id 레코드) 기준 추출 — v2.1.201 은 훅 시점에 현재
    // 라운드 assistant 레코드가 미flush 라 anchor 미발견이 정상 경로다. 그 경우
    // appendResolvingWhy 가 detached 자식으로 flush 후 why 를 채워 기록한다 (훅 비차단).
    const records = readTranscript(json.transcript_path);
    const anchor = findToolUseIndex(records, json.tool_use_id);
    const ctx = extractTurnContext(records, anchor >= 0 ? anchor : undefined);

    appendResolvingWhy(
      logPath(json.cwd),
      {
        ts: new Date().toISOString(),
        session_id: json.session_id || null,
        type: "skill",
        skill: skillName,
        args,
        trigger: classifyTrigger(skillName, ctx) || null, // 판정 불가 시 명시적 null (why 규약과 통일)
        why: ctx.why,
        why_source: ctx.why_source,
        // ── additive 확장 (2026-07): 기존 필드 의미 불변, 소비자는 tolerant reader ──
        prompt_id: json.prompt_id || null, // 턴 단위 정밀 join 키 (미발화 분석)
        tool_use_id: json.tool_use_id || null, // type:'result' 레코드와의 duration join 키
        turn_command: ctx.command ? ctx.command.name : null, // 커맨드 연쇄 provenance (trigger 와 직교)
        agent_id: json.agent_id || null, // 서브에이전트 내부 호출이면 부모 에이전트 귀속
        agent_type: json.agent_type || null,
      },
      json.transcript_path || null,
      json.tool_use_id || null,
      anchor >= 0,
    );
  } catch (_) {
    /* best-effort */
  }
})();
