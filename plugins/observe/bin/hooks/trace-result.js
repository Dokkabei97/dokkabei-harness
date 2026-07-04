// PostToolUse(Skill|Agent|Task): 스킬/에이전트 호출의 "완료" 사실을 skill-trace.jsonl 에 append.
// PostToolUse 는 성공한 호출에만 발화하므로 이 레코드의 존재 자체가 완주 신호이며,
// tool_use_id 로 대응하는 type:'skill'/'agent' 레코드와 join 하면 소요시간이 나온다.
// 응답 본문은 기록하지 않는다(용량·민감정보) — 크기만 남겨 산출물 유무의 프록시로 쓴다.
// 추적은 best-effort — 항상 조용히 종료(exit 0, stdout 무출력).
const { readEvent } = require('./_lib/hook-stdin');
const { enabled, logPath, append } = require('./_lib/trace');

const TARGET_TOOLS = new Set(['Skill', 'Agent', 'Task']);

// tool_response 크기 근사 — 문자열/객체/배열 모두 직렬화 길이로 통일 (실패 시 null)
function responseBytes(resp) {
  if (resp === undefined || resp === null) return null;
  try {
    return Buffer.byteLength(typeof resp === 'string' ? resp : JSON.stringify(resp), 'utf8');
  } catch (_) { return null; }
}

(async () => {
  try {
    if (!enabled()) return;
    const { json } = await readEvent();
    // matcher 오설정 대비 이중 가드 — 대상 외 툴은 즉시 무시
    if (!json.tool_name || !TARGET_TOOLS.has(json.tool_name)) return;

    const ti = json.tool_input || {};
    append(logPath(json.cwd), {
      ts: new Date().toISOString(),
      session_id: json.session_id || null,
      type: 'result',
      tool: json.tool_name,
      // join 보조 키 — tool_use_id 부재(구버전) 시 세션 내 최근 동일 target 과 근사 join
      target: json.tool_name === 'Skill' ? (ti.skill || null) : (ti.subagent_type || null),
      tool_use_id: json.tool_use_id || null,
      prompt_id: json.prompt_id || null,
      response_bytes: responseBytes(json.tool_response),
    });
  } catch (_) { /* best-effort */ }
})();
