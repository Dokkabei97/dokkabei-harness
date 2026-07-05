// PreToolUse(Agent|Task): 서브에이전트 호출을 근거(why)와 함께 skill-trace.jsonl 에 append.
// Agent 는 v2.1.63 에서 Task 가 개명된 툴명 — matcher 와 이중 가드 모두 양쪽을 허용한다.
// trigger 분류는 하지 않는다: 에이전트는 슬래시 직접 호출 경로가 없어 항상 모델 선택이다.
// 추적은 best-effort — 어떤 예외도 에이전트 실행을 막지 않도록 항상 조용히 종료(exit 0, stdout 무출력).
const { readEvent } = require("./_lib/hook-stdin");
const { enabled, logPath } = require("./_lib/trace");
const {
  readTranscript,
  extractTurnContext,
  findToolUseIndex,
  appendResolvingWhy,
} = require("./_lib/turn-context");

const AGENT_TOOLS = new Set(["Agent", "Task"]);
const trunc = (s, n) => {
  if (typeof s !== "string" || !s) return null;
  return s.length > n ? s.slice(0, n) + "…[truncated]" : s;
};

(async () => {
  try {
    if (!enabled()) return;
    const { json } = await readEvent();
    // matcher 오설정 대비 이중 가드 — Agent/Task 외 이벤트는 즉시 무시
    if (json.tool_name && !AGENT_TOOLS.has(json.tool_name)) return;

    const ti = json.tool_input || {};
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
        type: "agent",
        agent: ti.subagent_type || null, // 미지정이면 기본(general) 에이전트 — null 유지
        description: trunc(ti.description, 300),
        prompt_head: trunc(ti.prompt, 300), // 과업 원문 앞부분 — 선택 적합성 사후 평가용
        model: ti.model || null,
        why: ctx.why,
        why_source: ctx.why_source,
        prompt_id: json.prompt_id || null,
        tool_use_id: json.tool_use_id || null, // type:'result' 레코드와의 duration join 키
        parent_agent_id: json.agent_id || null, // 서브에이전트 내부에서의 재위임이면 부모 귀속
        parent_agent_type: json.agent_type || null,
      },
      json.transcript_path || null,
      json.tool_use_id || null,
      anchor >= 0,
    );
  } catch (_) {
    /* best-effort */
  }
})();
