// PostToolUse / PostToolUseFailure (async, 선택): 툴 호출 경량 카운터 — OBSERVE_TRACE_SCOPE 에 "tools" 가 있을 때만.
// stdin 만 쓰고 transcript 는 읽지 않는다. 남기는 것: 툴 이름·카테고리·성공 여부·중단 여부·duration_ms(payload 에 있으면).
// 원문(tool_input/tool_response/error)은 남기지 않는다. 툴을 사용자가 취소하면 PostToolUseFailure 가 발화하지 않으므로
// 이 카운터의 실패·중단 수는 하한이다 — 턴 단위 정본은 Stop 다이제스트(turn_summary.tools)다.
// OBSERVE_TRACE(on/off) 는 그대로 두고 범위는 별도 변수로 — OBSERVE_TRACE=tools 는 기록 전체를 끈다(정규식 불일치).
// Codex 도 같은 hooks.json 으로 이 훅을 부른다(matcher "*" 가 exec_command·apply_patch·spawn_agent 등 모든 로컬 툴에 걸린다 —
// Codex 에는 Skill/Agent 툴이 없어 trace-skill/agent/result 는 영원히 불발). 그래서 Codex 의 스킬 사용(SKILL.md 경로 읽기
// 휴리스틱, (turn, skill) 1회)과 spawn_agent 는 matcher 를 늘리지 않고 이 스크립트 안에서 거른다 — 범위 변수와 무관하게
// OBSERVE_TRACE 만으로 기록(Claude 의 trace-skill/agent 와 같은 기본 범위). 처리는 adapters/codex/rollout.js onPostToolUse.
const { readEvent } = require('../../_lib/hook-stdin');
const { enabled, appendV1, runtimeOf, CODEX } = require('../../_lib/writer');
const P = require('../../_lib/paths');

const scoped = () => /(^|[,\s])tools($|[,\s])/.test(process.env.OBSERVE_TRACE_SCOPE || '');

(async () => {
  try {
    if (!enabled()) return;
    // Claude 빠른 경로(P6 이전과 같은 비용): Claude 훅 env(CLAUDE_PROJECT_DIR 있음·Codex 의 PLUGIN_ROOT 없음)에서 범위 밖이면
    // stdin 도 읽지 않는다 — stdin 뒤 작업(Codex 휴리스틱)은 Codex 몫이다.
    if (!scoped() && process.env.CLAUDE_PROJECT_DIR && !process.env.PLUGIN_ROOT) return;
    const { json } = await readEvent();
    if (!json || typeof json.session_id !== 'string' || !json.session_id || !json.tool_name) return;
    const ev = json.hook_event_name;
    if (ev !== 'PostToolUse' && ev !== 'PostToolUseFailure') return;
    const runtime = runtimeOf(json);
    if (runtime === CODEX && ev === 'PostToolUse') require('../codex/rollout').onPostToolUse(P.repoRoot(json.cwd), json);
    if (!scoped()) return;
    // 게이트 뒤에서 로드 — 꺼진 상태의 프로세스 비용 최소화
    const catOf = runtime === CODEX ? require('../codex/rollout').catOf : require('./transcript').catOf;
    const ts = new Date().toISOString();
    const root = P.repoRoot(json.cwd);
    const turn = json.prompt_id || json.turn_id || null;
    appendV1(root, P.eventsFile(root, runtime, json.session_id, ts), {
      v: P.SCHEMA_VERSION, ts, runtime, session: json.session_id,
      turn, turn_src: turn ? 'native' : null,
      kind: 'tool_call',
      tool: {
        name: String(json.tool_name).slice(0, 200), cat: catOf(json.tool_name),
        ok: ev === 'PostToolUse', interrupt: json.is_interrupt === true,
        duration_ms: Number.isFinite(json.duration_ms) ? json.duration_ms : null,
      },
      ext: { [runtime]: { tool_use_id: json.tool_use_id || null } },
    });
  } catch (_) { /* best-effort */ }
})();
