// Codex rollout → 턴 다이제스트(turn_summary) + 커밋 이벤트 파서, Codex 훅 보조(SKILL.md 읽기 휴리스틱·spawn_agent),
// detached worker 진입점. 저장(커서·락·upsert-skip)은 _lib/digest.js 의 run() — Claude 어댑터(adapters/claude/transcript.js)와
// 같은 함수·같은 확정 규칙(지연 1턴)을 쓰고, 명령 분석(execKind·hasGitSub·커밋 SHA 찾기)도 Claude 어댑터 것을 그대로 쓴다.
// 원문(프롬프트·명령·출력)은 결과에 남기지 않는다 — 카테고리·개수·상대경로·스킬 이름·SHA 만.
//
// rollout 실측 (~/.codex/sessions, CLI 0.101~0.144.1, 119 세션, 2026-10-25):
//   · 줄 = {timestamp, type, payload}. 첫 줄 type "session_meta"(payload.id = 세션 id, timestamp, cwd, cli_version, source,
//     git{branch}). 첫 줄이 session_meta 가 아니면 형식 불명 → 아무것도 하지 않는다(포맷 감지 실패 = skip).
//   · 턴 = event_msg task_started{turn_id, started_at(초)} ~ task_complete{duration_ms} | turn_aborted{reason:"interrupted"}(8건).
//     turn_context{turn_id, model, effort} 가 턴마다 있다. 사람 프롬프트 = event_msg user_message{message}.
//     user_message 없는 턴(46건 — 멀티에이전트 NEW_TASK·중단 알림)은 시스템 주입 → prompt_kind "notification".
//   · 툴 호출 = response_item function_call{name, arguments(JSON 문자열), call_id} | custom_tool_call{name, input, call_id} +
//     같은 call_id 의 function_call_output / custom_tool_call_output. 이름 실측: exec(코드 모드 JS, 0.144) 2313 · exec_command 851 ·
//     wait 138 · send_message 123 · apply_patch 111 · wait_agent 77 · list_agents 53 · spawn_agent 28 · followup_task 21 ·
//     write_stdin 18 · update_plan 15 · view_image 2 · imagegen 3 …
//     exec_command 출력은 "Process exited with code N" — 오래 걸리면 "Process running with session ID S" 뒤 write_stdin{session_id:S}
//     출력이 종료 코드를 싣는다. 0.128 은 event_msg exec_command_end{call_id, exit_code, aggregated_output} 도 남긴다(있으면 우선).
//     코드 모드 exec 의 input 은 JS(`tools.exec_command({"cmd":"…"})`) — 안쪽 호출 이름·cmd 를 정규식으로 펼친다(종료 코드 없음).
//   · 토큰 = event_msg token_count.info{total_token_usage(누적), last_token_usage(요청 1회)} — 누적값이 바뀐 이벤트의
//     last_token_usage 합(같은 누적값 재방송은 건너뜀). in = input − cached, cache_r = cached, cache_w 는 Codex 에 없다(null).
//   · 하위 에이전트 스레드(첫 session_meta.source.subagent)는 별도 rollout — Claude sidechain 처럼 세지 않는다(부모 턴의
//     spawn_agent 가 subagents[] 로 남는다). fork(첫 session_meta.forked_from_id)는 부모 기록을 원래 turn_id 그대로 복사한다
//     (줄 timestamp 는 복사 시각, task_started.started_at 은 원래 시각) → fork 생성 시각 전에 시작한 턴은 부모 몫이라 건너뛴다.
//   · 같은 세션이 평문 .jsonl 과 .jsonl.zst 로 공존한다(실측 119쌍). .zst 는 바이트 사본이 아니라 다시 쓴 형식이다(실측: 줄마다
//     ordinal, event_msg user_message·agent_message·exec_command_end·patch_apply_end 대신 event_msg item_completed{turn_id,
//     item{type UserMessage·AgentMessage·CommandExecution{id=call_id, exit_code, aggregated_output}·FileChange·Reasoning·WebSearch}};
//     response_item·task_started·turn_context·token_count·turn_aborted 는 같다) → 두 형식을 같은 요약으로 읽는다(검증: 같은 턴 동일).
//     다이제스트 키가 (runtime, session, turn) 이라 어느 쪽을 읽어도 upsert-skip. 바이트 offset 은 형식마다 달라서, 커서가
//     다른 파일(평문 ↔ .zst)을 가리키면 처음부터 다시 읽는다. .zst 는 zstd CLI 로 해제(없으면 skip).
//   · Codex Desktop 의 "외부 에이전트 세션 가져오기"(Claude Code 세션 import)는 turn_id "external-import-turn-N" 턴으로 남는다
//     (실측 27 rollout, 이 레포 cwd 3개 — 전부 import 턴뿐, agent_message "<EXTERNAL SESSION IMPORTED>", 툴은
//     "[external_agent_tool_call: Bash]" 텍스트뿐). 다른 런타임에서 한 작업의 사본이라 Codex 턴으로 세지 않는다(segment 에서 버림).
//   · 훅 실행은 rollout 에 기록되지 않는다(P0 실측). 사용자 툴 승인 거부 형식은 미실측(로컬 approval_policy 대부분 never) →
//     tools.rejected 는 0, cancelled 는 turn_aborted 만 근거로 한다.
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const P = require('../../_lib/paths');
const { CODEX, emit } = require('../../_lib/writer');
const { skillReads } = require('../../_lib/skill-read');
const C = require('../claude/transcript');

const RUNTIME = CODEX;
const ZSTD_MAX = 512 * 1024 * 1024; // 해제본 상한(실측 최대 평문 10.6MB)

// 툴 → 카테고리. Claude 카테고리 문자(LETTER)를 그대로 쓴다 — seq_compact 가 런타임 간 비교 가능하도록.
const CATS = {
  exec_command: 'exec', shell: 'exec', local_shell: 'exec', container_exec: 'exec', exec: 'exec', write_stdin: 'exec',
  apply_patch: 'edit', view_image: 'read', update_plan: 'plan', spawn_agent: 'subagent',
  web_search_call: 'web', web_search: 'web', web__run: 'web',
  // 훅 payload 의 Claude 호환 별칭(셸 → Bash, apply_patch → Edit/Write 매칭 — 문서) — SCOPE=tools 카운터가 other 로 새지 않게
  Bash: 'exec', Edit: 'edit', Write: 'edit',
};
const catOf = (name) => (/^mcp__|__/.test(String(name)) ? 'mcp' : CATS[name] || 'other');

const parseJson = (s) => { try { return JSON.parse(s); } catch (_) { return null; } };
// 명령 배열 ["/bin/zsh","-lc","git commit …"] → 안쪽 명령 문자열
const cmdOfArray = (a) => (a.length >= 3 && /^-l?c$/.test(String(a[1])) ? String(a[2]) : a.map(String).join(' '));
// 코드 모드 JS → 안쪽 툴 이름 목록·exec_command cmd 목록(등장 순)
function codeMode(js) {
  const s = String(js || '');
  const tools = [...s.matchAll(/\btools\.([A-Za-z_]\w*)\s*\(/g)].map((m) => m[1]);
  const cmds = [...s.matchAll(/["']?\bcmd["']?\s*:\s*"((?:\\.|[^"\\])*)"/g)].map((m) => parseJson(`"${m[1]}"`)).filter((c) => typeof c === 'string');
  return { tools, cmds };
}
// 출력 → 텍스트 (문자열 | {output} JSON 문자열 | [{type:"input_text", text}])
function outText(o) {
  if (typeof o === 'string') {
    const j = /^\s*\{/.test(o) ? parseJson(o) : null;
    return j && typeof j.output === 'string' ? { text: j.output, exit: j.metadata && Number.isFinite(j.metadata.exit_code) ? j.metadata.exit_code : null } : { text: o, exit: null };
  }
  if (Array.isArray(o)) return { text: o.map((b) => (b && typeof b.text === 'string' ? b.text : '')).join('\n'), exit: null };
  if (o && typeof o === 'object') return outText(o.content ?? o.output ?? '');
  return { text: '', exit: null };
}
const exitOf = (t) => { const m = /Process exited with code (-?\d+)/.exec(t); return m ? Number(m[1]) : null; };
const runningOf = (t) => { const m = /Process running with session ID (\d+)/.exec(t); return m ? m[1] : null; };

// 파일 → Buffer (평문 그대로, .zst 는 zstd CLI 해제). 실패·zstd 부재 → null
function loadBuffer(file) {
  try {
    if (/\.zst$/.test(file)) {
      return require('child_process').execFileSync('zstd', ['-dcq', '--', file], { maxBuffer: ZSTD_MAX, stdio: ['ignore', 'pipe', 'ignore'] });
    }
    return fs.readFileSync(file);
  } catch (_) { return null; }
}
// 첫 줄 session_meta payload (형식 감지) — 아니면 null
function metaOf(buf) {
  if (!buf || !buf.length) return null;
  const nl = buf.indexOf(0x0a);
  const first = parseJson(buf.toString('utf8', 0, nl < 0 ? buf.length : nl));
  return first && first.type === 'session_meta' && first.payload && first.payload.id ? first.payload : null;
}
const isImported = (id) => /^external-import-/.test(String(id || ''));
const isSubagent = (meta) => !!(meta && meta.source && typeof meta.source === 'object' && meta.source.subagent);

// [offset, 마지막 완결 라인 끝) 라인 파싱 (Claude readLines 와 같은 규칙, 입력이 Buffer)
function linesOf(buf, offset) {
  const start = offset > 0 && offset <= buf.length ? offset : 0;
  const lastNl = buf.lastIndexOf(0x0a);
  const lines = [];
  let pos = start;
  while (pos <= lastNl) {
    const nl = buf.indexOf(0x0a, pos);
    if (nl > pos) {
      const rec = parseJson(buf.toString('utf8', pos, nl));
      if (rec && typeof rec === 'object' && rec.type) lines.push({ off: pos, rec });
    }
    pos = nl + 1;
  }
  return { lines, end: lastNl < start ? start : lastNl + 1 };
}

// 라인 → 턴 분할 (turn_id 경계). 첫 경계 이전 레코드는 확정된 이전 턴의 꼬리(또는 세션 서두)라 버린다.
// import 턴(isImported)은 경계로만 쓰고 결과에 넣지 않는다 — 그 턴의 레코드는 다음 경계까지 버린다.
function segment(lines) {
  const turns = [];
  let cur = null;
  for (const { off, rec } of lines) {
    const p = rec.payload || {};
    const start = (rec.type === 'event_msg' && p.type === 'task_started') || rec.type === 'turn_context';
    if (start && p.turn_id && (!cur || cur.id !== p.turn_id)) {
      cur = { id: p.turn_id, off, recs: [], startedAt: null, prompt: null, imported: isImported(p.turn_id) };
      if (!cur.imported) turns.push(cur);
    }
    if (!cur || cur.imported) continue;
    if (rec.type === 'event_msg' && p.type === 'task_started' && Number.isFinite(p.started_at)) cur.startedAt = p.started_at * 1000;
    if (rec.type === 'event_msg' && p.type === 'user_message' && cur.prompt == null) cur.prompt = String(p.message || '');
    const it = rec.type === 'event_msg' && p.type === 'item_completed' ? p.item || {} : null; // .zst 형식
    if (it && it.type === 'UserMessage' && cur.prompt == null) cur.prompt = (it.content || []).map((b) => (b && typeof b.text === 'string' ? b.text : '')).join('\n');
    cur.recs.push(rec);
  }
  return turns;
}

// 턴 1개 → { summary, commits } (요약할 게 없으면 null)
function summarize(turn, next, session, root, meta) {
  const roots = root ? [...new Set([root, P.real(root)])] : [];
  const calls = new Map();   // call_id → use
  const order = [];          // 툴 사용 순서 (코드 모드 안쪽 호출은 펼친다)
  const bySession = new Map(); // exec 세션 id → 아직 끝나지 않은 exec_command use
  let model = null; let effort = null; let assistant = 0;
  let interrupt = 0; let fail = 0; let results = 0;
  let pushed = false; let branch = (meta && meta.git && meta.git.branch) || null;
  let tsEnd = null; let durMs = null;
  const tokens = { in: 0, out: 0, cache_r: 0, cache_w: null };
  let lastTotal = null;
  const edited = new Set(); let newN = 0; let readN = 0;
  const skills = []; const subagents = [];

  const addUse = (name, extra) => { const u = { name, cat: catOf(name), cmds: [], exit: null, out: '', ...extra }; order.push(u); return u; };
  const finish = (u, text, exit) => {
    if (!u) return;
    if (text) u.out += '\n' + text;
    if (exit != null) u.exit = exit;
  };

  for (const r of turn.recs) {
    if (r.timestamp && (!tsEnd || r.timestamp > tsEnd)) tsEnd = r.timestamp;
    const p = r.payload || {};
    if (r.type === 'turn_context') { model = p.model || model; effort = p.effort || effort; continue; }
    if (r.type === 'event_msg') {
      if (p.type === 'turn_aborted') interrupt++;
      else if (p.type === 'task_complete' && Number.isFinite(p.duration_ms)) durMs = p.duration_ms;
      else if (p.type === 'agent_message') assistant++;
      else if (p.type === 'token_count' && p.info && p.info.total_token_usage) {
        const tot = p.info.total_token_usage.total_tokens;
        const u = p.info.last_token_usage;
        if (u && tot !== lastTotal) {
          tokens.in += (u.input_tokens || 0) - (u.cached_input_tokens || 0);
          tokens.cache_r += u.cached_input_tokens || 0;
          tokens.out += u.output_tokens || 0;
        }
        lastTotal = tot;
      } else if (p.type === 'exec_command_end' && calls.has(p.call_id)) {
        const u = calls.get(p.call_id);
        u.exit = Number.isFinite(p.exit_code) ? p.exit_code : u.exit;
        if (typeof p.aggregated_output === 'string') u.out = p.aggregated_output;
      } else if (p.type === 'patch_apply_end' && calls.has(p.call_id) && p.success === false) calls.get(p.call_id).exit = 1;
      else if (p.type === 'item_completed' && p.item) { // .zst 형식 — 위 이벤트들의 대체
        const it = p.item;
        if (it.type === 'AgentMessage') assistant++;
        else if (it.type === 'CommandExecution' && calls.has(it.id)) {
          const u = calls.get(it.id);
          u.exit = Number.isFinite(it.exit_code) ? it.exit_code : u.exit;
          if (typeof it.aggregated_output === 'string') u.out = it.aggregated_output;
        } else if (it.type === 'FileChange' && calls.has(it.id) && /fail|declin|reject/i.test(String(it.status || ''))) calls.get(it.id).exit = 1;
      }
      continue;
    }
    if (r.type !== 'response_item') continue;
    if (p.type === 'message' && p.role === 'assistant') { assistant++; continue; }
    if (p.type === 'web_search_call') { addUse('web_search_call'); continue; }
    if (p.type === 'function_call' || p.type === 'custom_tool_call') {
      assistant++;
      const name = p.name;
      const args = p.type === 'function_call' ? parseJson(p.arguments) || {} : null;
      const input = p.type === 'custom_tool_call' ? String(p.input || '') : '';
      let u;
      if (name === 'exec' && p.type === 'custom_tool_call') {
        // 코드 모드 — 안쪽 호출을 각각 툴 사용으로 센다(없으면 exec 1회). 결과는 첫 안쪽 사용(대표)에 붙인다.
        const cm = codeMode(input);
        const inner = cm.tools.length ? cm.tools : ['exec'];
        let ci = 0;
        for (const t of inner) {
          const x = addUse(t, { ts: r.timestamp });
          if (t === 'exec_command' || t === 'exec') x.cmds = t === 'exec' ? cm.cmds : cm.cmds.slice(ci, ++ci);
          if (!u) u = x;
        }
        if (cm.tools.length && ci < cm.cmds.length) u.cmds.push(...cm.cmds.slice(ci));
        u.patch = input;
      } else {
        u = addUse(name, { ts: r.timestamp });
        if (args) {
          const c = args.cmd ?? args.command;
          if (typeof c === 'string') u.cmds = [c];
          else if (Array.isArray(c)) u.cmds = [cmdOfArray(c)];
          if (name === 'write_stdin' && args.session_id != null) u.stdinOf = String(args.session_id);
          if (name === 'spawn_agent') u.sub = { type: args.agent_type || null, agent_id: null, async: true, dur_ms: null, tools_n: null };
        }
        if (name === 'apply_patch') u.patch = input || (args && (args.input || args.patch)) || '';
      }
      if (u.sub) subagents.push(u.sub);
      calls.set(p.call_id, u);
      continue;
    }
    if (p.type === 'function_call_output' || p.type === 'custom_tool_call_output') {
      const u = calls.get(p.call_id);
      if (!u) continue;
      const { text, exit } = outText(p.output);
      const sid = runningOf(text);
      if (u.stdinOf) { // write_stdin — 원래 exec_command 의 종료를 싣는다
        const orig = bySession.get(u.stdinOf);
        const e = exitOf(text);
        finish(orig, text, e);
        if (orig && e != null) { bySession.delete(u.stdinOf); orig.endTs = r.timestamp; }
        continue;
      }
      results++;
      u.endTs = r.timestamp;
      if (sid) { bySession.set(sid, u); u.out += '\n' + text; continue; }
      finish(u, text, exit != null ? exit : exitOf(text));
      if (u.name === 'exec' && /^Script (?:failed|error)/i.test(text)) u.exit = 1;
      if (u.sub) { const j = parseJson(text); u.sub.agent_id = (j && (j.agent_id || j.task_name)) || null; }
    }
  }
  if (!assistant && !interrupt) return null;

  const counts = { read: 0, search: 0, edit: 0, exec: 0, web: 0, subagent: 0, skill: 0, mcp: 0, plan: 0, other: 0 };
  const execKinds = { test: 0, git: 0, lint: 0, build: 0, pkg: 0, other: 0 };
  const runs = [];
  const commits = []; const shaSeen = new Set();
  for (const u of order) {
    if (u.stdinOf) continue; // 입력 전달은 별도 툴 사용으로 세지 않는다(원래 exec 의 연장)
    counts[u.cat]++;
    if (u.cat === 'read') readN++;
    if (u.exit != null && u.exit !== 0) fail++;
    let tok = C.LETTER[u.cat];
    if (u.cat === 'exec') { const k = C.execKind(u.cmds[0] || ''); execKinds[k]++; tok += `(${k})`; }
    const lastRun = runs[runs.length - 1];
    if (lastRun && lastRun[0] === tok) lastRun[1]++;
    else runs.push([tok, 1]);
    for (const cmd of u.cmds) {
      for (const name of skillReads(cmd, roots)) if (!skills.some((s) => s.name === name)) skills.push({ name, trigger: 'model', detection: 'heuristic' });
      const ok = u.exit == null || u.exit === 0; // 코드 모드는 종료 코드가 없다 — 실패 표시가 없으면 성공으로 본다
      if (!ok) continue;
      if (C.hasGitSub(cmd, 'push')) pushed = true;
      if (!C.hasGitSub(cmd, 'commit')) continue;
      const found = [];
      for (const mm of String(u.out || '').matchAll(C.COMMIT_LINE_RE)) {
        found.push([mm[1], 'stdout']);
        const b = /^\[([^\]\s]+)/.exec(mm[0]);
        if (b) branch = b[1];
      }
      if (!found.length && u.endTs) for (const c of C.pickOwnCommit(C.gitCommitsBetween(root, Date.parse(u.ts), Date.parse(u.endTs)), cmd)) found.push([c.sha, c.source]);
      for (const [sha, source] of found) {
        if (shaSeen.has(sha)) continue;
        shaSeen.add(sha);
        commits.push({ sha, source, ts: u.endTs || u.ts });
      }
    }
    if (u.patch) {
      for (const m of String(u.patch).matchAll(/\*\*\* (Add|Update|Delete) File: ([^\n\\"]+)/g)) {
        const rel = C.relPath(m[2].trim(), roots);
        if (rel) edited.add(rel);
        if (m[1] === 'Add') newN++;
      }
    }
  }
  let seq = runs.slice(0, C.SEQ_MAX_RUNS).map(([t, n]) => t + n).join('>');
  if (runs.length > C.SEQ_MAX_RUNS) seq += `>…+${runs.length - C.SEQ_MAX_RUNS}`;

  // outcome — Claude 와 같은 우선순위·같은 corrected 규칙(스킬/서브에이전트 턴 직후의 평문 사람 프롬프트 = 교정 "후보")
  const nextIsPlain = next && next.prompt != null && !/^\s*[/$][A-Za-z]/.test(next.prompt);
  let outcome = 'unknown';
  if (commits.length) outcome = 'committed';
  else if (interrupt) outcome = 'cancelled';
  else if ((skills.length || subagents.length) && nextIsPlain) outcome = 'corrected';
  else if (results && fail / results >= C.FAIL_RATIO) outcome = 'failed';

  const first = turn.recs.find((r) => r.timestamp);
  const tsStart = first ? first.timestamp : null;
  const dur = Date.parse(tsEnd) - Date.parse(tsStart);
  const summary = {
    v: P.SCHEMA_VERSION, kind: 'turn_summary', runtime: RUNTIME, session, turn: turn.id, turn_src: 'native',
    prompt_kind: turn.prompt != null ? 'user' : 'notification',
    ts_start: tsStart, ts_end: tsEnd, dur_ms: Number.isFinite(durMs) ? durMs : Number.isFinite(dur) ? dur : null,
    model, effort, permission_mode: null, // Codex 는 approval_policy·sandbox 로 표현 — Claude permission_mode 와 어휘가 달라 비운다
    tokens,
    tools: { seq_compact: seq, counts, fail, interrupt, rejected: 0 },
    exec_kinds: execKinds,
    files: { edited: [...edited].slice(0, C.EDITED_MAX), edited_n: edited.size, read_n: readN, new_n: newN },
    skills,
    subagents,
    git: { branch, commits: commits.map((c) => c.sha), pushed },
    outcome,
  };
  const commitEvents = commits.map((c) => ({
    v: P.SCHEMA_VERSION, ts: c.ts, runtime: RUNTIME, session, turn: turn.id, turn_src: 'native',
    kind: 'commit', commit: { sha: c.sha, branch, source: c.source },
  }));
  return { summary, commits: commitEvents };
}

// digest.run 의 parse 콜백 본체 — 확정 규칙은 Claude parseTurns 와 같다(final=false 면 마지막 사람 턴 + 그 뒤 시스템 턴 보류).
function parseBuffer(buf, meta, offset, final, root, session) {
  const { lines, end } = linesOf(buf, offset);
  if (isSubagent(meta)) return { turns: [], offset: end };
  const forkAt = meta.forked_from_id ? Date.parse(meta.timestamp) : NaN;
  const turns = segment(lines);
  let upto = turns.length;
  if (!final) { upto = 0; for (let i = turns.length - 1; i >= 0; i--) if (turns[i].prompt != null) { upto = i; break; } }
  const out = [];
  for (let i = 0; i < upto; i++) {
    if (Number.isFinite(forkAt) && Number.isFinite(turns[i].startedAt) && turns[i].startedAt < forkAt) continue; // fork 가 복사한 부모 턴
    let j = i + 1;
    while (j < turns.length && turns[j].prompt == null) j++;
    const s = summarize(turns[i], turns[j] || null, session, root, meta);
    if (s) out.push(s);
  }
  return { turns: out, offset: upto < turns.length ? turns[upto].off : end };
}

// 한 rollout 증분 처리 (Stop 훅·worker·백필 공용). 형식 불명·해제 실패는 null(아무것도 안 씀).
// 세션 키는 rollout 의 session_meta.id — 평문/.zst 어느 쪽에서 들어와도, 훅 payload 와 백필이 같은 키를 쓰게.
function digestSession(root, session, transcript, final) {
  if (!transcript) return null;
  const buf = loadBuffer(transcript);
  const meta = metaOf(buf);
  if (!meta) return null;
  const sid = meta.id || session;
  const D = require('../../_lib/digest');
  const cur = D.readCursor(root, RUNTIME, sid);
  const same = !cur || D.untildify(cur.transcript) === transcript; // 평문 ↔ .zst 전환이면 offset 이 맞지 않는다 → 0 부터
  return D.run(root, RUNTIME, sid, transcript, (t, off, fin, r) => parseBuffer(buf, meta, same ? off : 0, fin, r, sid), { final });
}

// ── 훅 보조 (PostToolUse — trace-tool.js 가 runtime codex 일 때 부른다) ──────────────────────────
// payload 의 tool_input → 셸 명령 문자열 목록. Bash 별칭({command})·exec_command({cmd})·명령 배열·코드 모드 JS 모두 허용
// (Codex 훅 payload 의 tool_name/tool_input 모양은 미실측 — 바이너리 스키마상 tool_input 은 임의 JSON).
function hookCommands(name, ti) {
  if (ti == null) return [];
  if (typeof ti === 'string') return name === 'exec' ? codeMode(ti).cmds : [ti];
  if (typeof ti !== 'object') return [];
  const c = ti.command ?? ti.cmd;
  if (typeof c === 'string') return [c];
  if (Array.isArray(c)) return [cmdOfArray(c)];
  if (typeof ti.input === 'string') return codeMode(ti.input).cmds;
  return [];
}
// (session, turn, skill) 1회 표식 — 병렬 PostToolUse(async) 끼리도 O_EXCL 로 한 번만 통과. 실패는 false(기록 안 함).
// 표식은 살아 있는 턴의 중복 방지용이라 세션 마감(worker end)에서 지운다(clearSeen) — inode 무한 누적 방지.
// 디렉터리는 남기고 표식 파일만 지운다(세션당 빈 디렉터리 1개 — 커서 파일과 같은 규모): 디렉터리째 지우면 동시에 도는
// claimOnce 의 mkdir→open 사이가 ENOENT 로 끊겨 그 skill_use 를 잃는다(검증 재현 2/8). resume 뒤 턴은 새 turn_id 라
// 지운 표식과 겹치지 않는다.
const seenDir = (root, session) => P.cursorFile(root, RUNTIME, session).replace(/\.json$/, '.seen');
function clearSeen(root, session) {
  if (!session) return;
  const dir = seenDir(root, session);
  let names = [];
  try { names = fs.readdirSync(dir); } catch (_) { return; }
  for (const n of names) { try { fs.unlinkSync(path.join(dir, n)); } catch (_) { /* best-effort */ } }
}
// mkdir 와 open 사이에 디렉터리가 사라지면(수동 삭제·이전 버전 clearSeen) ENOENT(macOS 는 삭제 중이면 EINVAL 도 실측) —
// EEXIST(이미 표식 있음 = 정상 중복) 가 아니면 한 번만 다시 만든다.
function claimOnce(root, session, turn, skill) {
  const dir = seenDir(root, session);
  const f = path.join(dir, crypto.createHash('sha1').update(`${turn || ''}\0${skill}`).digest('hex'));
  for (let i = 0; i < 2; i++) {
    try {
      fs.mkdirSync(dir, { recursive: true });
      fs.closeSync(fs.openSync(f, 'wx'));
      return true;
    } catch (e) { if (!e || e.code === 'EEXIST') return false; }
  }
  return false;
}
// SKILL.md 읽기 → skill_use(heuristic), spawn_agent → subagent. 원문은 남기지 않는다(writer 가 raw 로 분리할 필드도 없다).
function onPostToolUse(root, json) {
  if (P.isHome(root) || !json.session_id) return;
  const ts = new Date().toISOString();
  const turn = json.turn_id || null;
  const names = [];
  const roots = [...new Set([root, P.real(root)])];
  for (const cmd of hookCommands(json.tool_name, json.tool_input)) for (const n of skillReads(cmd, roots)) if (!names.includes(n)) names.push(n);
  for (const name of names) {
    require('../../_lib/writer').ensureSkeleton(root); // 표식 디렉터리보다 .gitignore("*") 가 먼저
    if (!claimOnce(root, json.session_id, turn, name)) continue;
    emit(root, { ts, session_id: json.session_id, type: 'skill', skill: name, trigger: 'model', detection: 'heuristic', prompt_id: turn, tool_use_id: json.tool_use_id || null }, RUNTIME);
  }
  if (json.tool_name === 'spawn_agent') {
    const ti = json.tool_input && typeof json.tool_input === 'object' ? json.tool_input : {};
    emit(root, { ts, session_id: json.session_id, type: 'agent', agent: ti.agent_type || null, model: ti.model || null, prompt_id: turn, tool_use_id: json.tool_use_id || null }, RUNTIME);
  }
}

// ── detached worker (SessionEnd 마감 · SessionStart 따라잡기) — Claude transcript.js runJob 과 같은 규칙 ──
function spawnWorker(job) {
  try {
    const child = require('child_process').spawn(process.execPath, [__filename, '--worker', JSON.stringify(job)],
      { detached: true, stdio: 'ignore' });
    child.unref();
  } catch (_) { /* best-effort */ }
}
function runJob(job) {
  const D = require('../../_lib/digest');
  if (job.mode === 'end') {
    try { return digestSession(job.root, job.session, job.transcript, true); } finally { clearSeen(job.root, job.session); }
  }
  if (job.mode !== 'catchup') return null;
  if (job.session && job.transcript && metaOf(loadBuffer(job.transcript))) D.ensureCursor(job.root, RUNTIME, job.session, job.transcript);
  const now = job.now || Date.now();
  for (const c of D.listCursors(job.root, RUNTIME)) {
    const t = c.session === job.session ? job.transcript : D.untildify(c.transcript);
    if (!t || (c.final && !D.grownSince(c, t))) continue;
    let mtime;
    try { mtime = fs.statSync(t).mtimeMs; } catch (_) { continue; }
    const final = c.session !== job.session && now - mtime > C.IDLE_FINAL_MS;
    try { digestSession(job.root, c.session, t, final); } catch (_) { /* 세션 하나 실패가 나머지를 막지 않게 */ }
  }
  return null;
}

module.exports = { RUNTIME, catOf, codeMode, loadBuffer, metaOf, isImported, isSubagent, linesOf, segment, summarize, parseBuffer, digestSession, hookCommands, onPostToolUse, spawnWorker, runJob };

if (require.main === module && process.argv[2] === '--worker') {
  try { runJob(JSON.parse(process.argv[3])); } catch (_) { /* best-effort */ }
}
