// 현재 턴 컨텍스트 추출 헬퍼 — transcript JSONL 에서 "현재 턴"의 사용자 발화와
// preamble(why)·커맨드 래퍼를 뽑는다 (trace-skill/trace-agent 공유).
//
// 설계 근거 (실제 transcript 실측, v2.1.201 재실측 2026-07):
//   · transcript 레코드는 블록 1개씩 분리 기록된다(thinking/text/tool_use 각각 별도 레코드).
//   · v2.1.201: 현재 라운드의 assistant 레코드 전부(thinking/text/tool_use)는
//     PreToolUse 훅이 끝난 뒤, 툴 실행 직전에야 transcript 에 flush 된다.
//     실측 근거: ① 훅 시점(+74~289ms) 역방향 스캔이 같은 턴 preamble 을 3/3 미발견(전부
//     why:null), ② 259초 장수명 Bash 의 tool_use 레코드 "뒤"에 실행 중 생성된 attachment
//     레코드가 이어짐 → flush 는 결과 시점이 아니라 툴 시작 시점(훅 완료 직후)이다.
//   → 훅 프로세스 안의 동기 대기/재시도는 원리적으로 불가(flush 가 훅 종료를 기다린다).
//   → 해법(appendResolvingWhy): 훅은 즉시 exit 0 하고, detached 자식 프로세스가 현재
//     호출의 anchor(tool_use_id) 레코드 flush 를 기다렸다가 why 를 채워 append 한다.
//   · anchor 탐색의 정밀성: PreToolUse stdin 이 현재 호출의 tool_use_id 를 제공하므로
//     (v2.1.201 실측) 과거 "마지막 tool_use" 휴리스틱의 반복 호출 오귀속이 없다.
//   · why = anchor(미발견 시 EOF)에서 역방향으로 현재 턴 경계(마지막 실사용자 발화) 안의
//     마지막 assistant 텍스트. 없으면 null 폴백 — 어떤 실패도 throw 하지 않는다.
const fs = require('fs');
const { append } = require('./trace');

const WHY_MAX = 1000;          // why 길이 상한 — 레코드 비대 방지 (trace-skill args 상한과 동일 규약)
const DEFER_POLL_MS = 100;     // deferred 자식의 anchor flush 폴링 주기
const DEFER_BUDGET_MS = 15000; // deferred 자식 폴링 총 예산 — 초과 시 무anchor 폴백 기록

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

// tool_use_id 로 현재 호출의 anchor 레코드 인덱스를 찾는다 (역방향 — 최신 우선). 없으면 -1.
function findToolUseIndex(records, toolUseId) {
  if (!toolUseId) return -1;
  for (let i = records.length - 1; i >= 0; i--) {
    const c = contentOf(records[i]);
    if (Array.isArray(c) && c.some((b) => b && b.type === 'tool_use' && b.id === toolUseId)) return i;
  }
  return -1;
}

// 현재 턴의 사용자 발화와 preamble(why)을 한 번의 역방향 스캔으로 추출.
//   fromIndex = 스캔 시작 인덱스(포함, 생략 시 EOF — 기존 픽스처 포맷 하위 호환).
//               현재 호출의 anchor 레코드를 알면 그 인덱스를 넘겨라: anchor "이후"
//               레코드(사후 재추출 시의 다음 턴 등)로의 오귀속이 차단되고, text 와
//               tool_use 가 같은 레코드에 공존하는 포맷에서도 anchor 자신의 text 를
//               preamble 로 잡는다 (v2.1.201 은 분리 기록이라 textOf='' 로 자연 통과).
//   boundary = 뒤에서부터 첫 "실사용자 발화" 레코드 (isMeta 제외, tool_result 는 textOf='' 라 자연 제외)
//   why      = boundary 이후(=현재 턴 내) 마지막 assistant 텍스트 레코드 (WHY_MAX 상한)
// 반환: { why, why_source('preamble'|null), userText, command({name,args}|null) }
function extractTurnContext(records, fromIndex) {
  let why = null;
  const start = Number.isInteger(fromIndex)
    ? Math.min(fromIndex, records.length - 1)
    : records.length - 1;
  for (let i = start; i >= 0; i--) {
    const rec = records[i];
    const role = roleOf(rec);
    const text = textOf(contentOf(rec));
    if (!text) continue; // thinking/tool_use/tool_result 레코드 — 예산 소모 없이 통과

    if (role === 'assistant') {
      if (why === null) {
        // 턴 내 "마지막" assistant 텍스트만 채택 — 길이 상한으로 레코드 비대 방지
        why = text.length > WHY_MAX ? text.slice(0, WHY_MAX) + '…[truncated]' : text;
      }
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

// 레코드 append + why 지연 해석 (trace-skill/trace-agent 공용 기록 경로).
//   anchorFound=true → 이미 flush 됨(사후 파이프 재실행·anchor 선기록 포맷) — 동기 append.
//   anchor 미발견 + tool_use_id·transcript 존재 → v2.1.201 훅 시점 미flush 정상 경로 —
//     detached 자식을 띄워 flush 후 why/why_source 만 갱신해 append (정확히 1회 기록,
//     훅 프로세스는 즉시 종료하므로 툴 실행을 차단하지 않는다).
//   그 외(tool_use_id 없음·transcript 없음 — 기존 픽스처 경로) → 동기 append (하위 호환).
//   spawn 실패 시 동기 폴백으로 레코드 유실을 막는다. 모든 실패는 삼킨다 (best-effort).
function appendResolvingWhy(file, record, transcriptPath, toolUseId, anchorFound) {
  try {
    if (!anchorFound && toolUseId && transcriptPath && fs.existsSync(transcriptPath)) {
      const payload = JSON.stringify({ file, record, transcriptPath, toolUseId });
      const child = require('child_process').spawn(
        process.execPath, [__filename, '--deferred-why', payload],
        { detached: true, stdio: 'ignore' },
      );
      child.unref();
      return;
    }
  } catch (_) { /* spawn 실패 → 동기 폴백 */ }
  append(file, record);
}

module.exports = {
  readTranscript,
  extractTurnContext,
  parseCommandWrapper,
  findToolUseIndex,
  appendResolvingWhy,
};

// ── deferred-why 자식 진입점 ─────────────────────────────────────────────────
// 훅(부모)이 spawn 한 detached 프로세스. anchor(tool_use_id) 레코드가 transcript 에
// flush 되기를 기다렸다가(실측: 훅 종료 직후 툴 시작 시점) why 를 해석해 레코드를
// append 한다. 예산 초과 시 무anchor 폴백(훅 시점과 동일한 EOF 스캔)으로라도 반드시
// 1회 기록한다. stdio 는 부모가 'ignore' 로 끊어 두어 컨텍스트 오염이 없다.
if (require.main === module && process.argv[2] === '--deferred-why') {
  (async () => {
    try {
      const { file, record, transcriptPath, toolUseId } = JSON.parse(process.argv[3]);
      const deadline = Date.now() + DEFER_BUDGET_MS;
      let records = readTranscript(transcriptPath);
      let anchor = findToolUseIndex(records, toolUseId);
      while (anchor < 0 && Date.now() < deadline) {
        await new Promise((r) => setTimeout(r, DEFER_POLL_MS));
        records = readTranscript(transcriptPath);
        anchor = findToolUseIndex(records, toolUseId);
      }
      const ctx = extractTurnContext(records, anchor >= 0 ? anchor : undefined);
      record.why = ctx.why;
      record.why_source = ctx.why_source;
      append(file, record);
    } catch (_) { /* best-effort */ }
    process.exit(0);
  })();
}
