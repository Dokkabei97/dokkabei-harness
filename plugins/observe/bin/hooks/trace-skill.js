// PreToolUse(Skill): 스킬 호출을 근거(why)·trigger와 함께 skill-trace.jsonl 에 append.
// 추적은 best-effort — 어떤 예외도 스킬 실행을 막지 않도록 항상 조용히 종료(exit 0, stdout 무출력).
//
// 설계 근거 (실제 transcript 실측 기반, 2026-07 셀프리뷰):
//   · PreToolUse 시점에 "현재" tool_use 는 transcript 에 아직 flush 되지 않는다 (정상 경로).
//     따라서 tool_use 앵커 탐색은 같은 스킬 반복 호출 시 이전 호출을 오귀속한다 → 폐기.
//   · transcript 레코드는 블록 1개씩 분리 기록된다(thinking/text/tool_use 각각 별도 레코드).
//   → why = "현재 턴"(마지막 실사용자 발화 이후)의 마지막 assistant 텍스트 레코드.
//     턴 경계를 넘지 않으므로 낡은 텍스트 오귀속이 원천 차단된다. 없으면 null.
const fs = require('fs');
const { readEvent } = require('./_lib/hook-stdin');
const { enabled, logPath, append } = require('./_lib/trace');

// transcript JSONL → 레코드 배열. 깨진 라인은 건너뛴다.
function readTranscript(p) {
  if (!p) return [];
  try {
    return fs.readFileSync(p, 'utf8').split('\n').filter(Boolean).map((l) => {
      try { return JSON.parse(l); } catch (_) { return null; }
    }).filter(Boolean);
  } catch (_) { return []; }
}

// 메시지 content(문자열 | 블록 배열)에서 text 블록만 모아 반환. tool_result 배열은 '' 가 된다.
function textOf(content) {
  if (typeof content === 'string') return content.trim();
  if (!Array.isArray(content)) return '';
  return content.filter((b) => b && b.type === 'text' && b.text)
    .map((b) => b.text.trim()).filter(Boolean).join('\n').trim();
}

const roleOf = (rec) => (rec && rec.message && rec.message.role) || rec.type || '';
const contentOf = (rec) => (rec && rec.message && rec.message.content);

// 슬래시 커맨드 래퍼 파싱 — user 레코드가 <command-name>/foo</command-name> 형태면
// {name, args} 반환, 아니면 null. 이 래퍼는 "사용자가 직접 친 커맨드"의 고정밀 신호다.
function parseCommandWrapper(text) {
  const m = /<command-name>\s*([^<]+?)\s*<\/command-name>/.exec(text || '');
  if (!m) return null;
  const a = /<command-args>\s*([^<]*?)\s*<\/command-args>/.exec(text);
  return { name: m[1].replace(/^\//, ''), args: a ? a[1] : '' };
}

// 현재 턴의 사용자 발화와 preamble(why)을 한 번의 역방향 스캔으로 추출.
//   boundary = 뒤에서부터 첫 "실사용자 발화" 레코드 (isMeta 제외, tool_result 는 textOf='' 라 자연 제외)
//   why      = boundary 이후(=현재 턴 내) 마지막 assistant 텍스트 레코드
// 반환: { why, why_source('preamble'|null), userText, command({name,args}|null) }
function extractTurnContext(records) {
  let why = null;
  for (let i = records.length - 1; i >= 0; i--) {
    const rec = records[i];
    const role = roleOf(rec);
    const text = textOf(contentOf(rec));
    if (!text) continue; // thinking/tool_use/tool_result 레코드 — 예산 소모 없이 통과

    if (role === 'assistant') {
      if (why === null) why = text; // 턴 내 "마지막" assistant 텍스트만 채택
      continue;
    }
    if (role === 'user') {
      if (rec.isMeta === true) continue; // caveat 등 meta 레코드는 턴 경계가 아니다
      return {
        why,
        why_source: why ? 'preamble' : null,
        userText: text,
        command: parseCommandWrapper(text),
      };
    }
  }
  return { why, why_source: why ? 'preamble' : null, userText: '', command: null };
}

// trigger 분류 — "user"(사용자가 직접 슬래시로 호출) | "model"(모델 자율 선택).
// user 호출을 걸러내야 "모델이 스킬을 알아서 잘 고르는가" 평가의 분모가 깨끗해진다.
// 판정 신호(정밀도 순):
//   ① 커맨드 래퍼 <command-name> 이 스킬명과 일치 — 최고 정밀도
//   ② 사용자 발화가 `/스킬명` 으로 시작 (네임스페이스 유무 양쪽 허용: /ns:name, /name)
//   ③ 그 외 전부 model — 커맨드가 다른 스킬을 연쇄 호출시킨 경우(예: /mvp-new 가
//      mvp-orchestrator 를 부름)도 model 로 둔다: 그 선택 자체는 모델의 수행이며,
//      모호 시 user 로 기울이면 자율 호출 표본이 부당하게 줄어든다.
function classifyTrigger(skillName, ctx) {
  if (!skillName) return null;
  const full = skillName.toLowerCase();               // "harness:verify-flow"
  const tail = full.split(':').pop();                 // "verify-flow"
  const matches = (tok) => {
    const t = (tok || '').replace(/^\//, '').toLowerCase();
    return t === full || t === tail || t.endsWith(':' + tail);
  };
  if (ctx.command && matches(ctx.command.name)) return 'user';
  if (/^\//.test(ctx.userText) && matches(ctx.userText.split(/\s+/)[0])) return 'user';
  return 'model';
}

(async () => {
  try {
    if (!enabled()) return;
    const { json } = await readEvent();
    // matcher 의미론 변경/오설정 대비 이중 가드 — Skill 외 이벤트는 즉시 무시
    if (json.tool_name && json.tool_name !== 'Skill') return;

    const skillName = (json.tool_input && json.tool_input.skill) || null;
    let args = (json.tool_input && json.tool_input.args) || '';
    if (typeof args === 'string' && args.length > 1000) args = args.slice(0, 1000) + '…[truncated]';

    const ctx = extractTurnContext(readTranscript(json.transcript_path));

    append(logPath(json.cwd), {
      ts: new Date().toISOString(),
      session_id: json.session_id || null,
      type: 'skill',
      skill: skillName,
      args,
      trigger: classifyTrigger(skillName, ctx) || null, // 판정 불가 시 명시적 null (why 규약과 통일)
      why: ctx.why,
      why_source: ctx.why_source,
    });
  } catch (_) { /* best-effort */ }
})();
