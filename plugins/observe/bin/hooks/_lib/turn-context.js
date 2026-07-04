// 현재 턴 컨텍스트 추출 헬퍼 — transcript JSONL 에서 "현재 턴"의 사용자 발화와
// preamble(why)·커맨드 래퍼를 뽑는다 (trace-skill/trace-agent 공유).
//
// 설계 근거 (실제 transcript 실측 기반, 2026-07 셀프리뷰):
//   · PreToolUse 시점에 "현재" tool_use 는 transcript 에 아직 flush 되지 않는다 (정상 경로).
//     따라서 tool_use 앵커 탐색은 같은 스킬 반복 호출 시 이전 호출을 오귀속한다 → 폐기.
//   · transcript 레코드는 블록 1개씩 분리 기록된다(thinking/text/tool_use 각각 별도 레코드).
//   → why = "현재 턴"(마지막 실사용자 발화 이후)의 마지막 assistant 텍스트 레코드.
//     턴 경계를 넘지 않으므로 낡은 텍스트 오귀속이 원천 차단된다. 없으면 null.
const fs = require('fs');

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
      // 로컬 커맨드(/model 등) 출력 레코드는 isMeta 없이 기록됨을 실측(2026-07) —
      // 턴 중간에 끼면 가짜 경계가 되어 trigger/why/turn_command 를 오염시키므로 건너뛴다.
      if (/^<local-command-(stdout|caveat)/.test(text)) continue;
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

module.exports = { readTranscript, extractTurnContext, parseCommandWrapper };
